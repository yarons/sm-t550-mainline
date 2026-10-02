// SPDX-License-Identifier: GPL-2.0-only
/*
 * SiliconFile (Hynix) SR544 5MP raw Bayer camera sensor.
 *
 * Rear camera of the Samsung Galaxy Tab A 9.7 (SM-T550): two-lane MIPI CSI-2,
 * RAW10 BGGR (measured on a test chart). Registers are 16-bit with 16-bit values. The register tables,
 * which include a sensor firmware upload, come from Samsung's Marvell b52
 * driver (sr544_regs.h). The sensor has no on-chip ISP: exposure and gain
 * are driven by the host (libcamera).
 */

#include <linux/clk.h>
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/pm_runtime.h>
#include <linux/regulator/consumer.h>
#include <linux/unaligned.h>
#include <media/v4l2-ctrls.h>
#include <media/v4l2-fwnode.h>
#include <media/v4l2-subdev.h>

struct sr544_reg {
	u16 reg;
	u16 val;
};

#include "sr544_regs.h"

#define SR544_REG_MODE_SELECT		0x0118
#define SR544_MODE_STREAMING		0x0100
#define SR544_MODE_STANDBY		0x0000
#define SR544_REG_COARSE_EXPOSURE	0x0004
#define SR544_REG_FRAME_LENGTH		0x0006
#define SR544_REG_ANALOG_GAIN		0x003a
#define SR544_REG_CHIP_ID		0x0f16
#define SR544_CHIP_ID			0x4405

#define SR544_NATIVE_WIDTH		2592
#define SR544_NATIVE_HEIGHT		1944
#define SR544_VTS_MIN			0x07c8
#define SR544_VTS_MAX			0x7fff
/* line_length_pck, in units of the reported pixel rate (measured: 18.1 us per line) */
#define SR544_HTS			0x0b40
#define SR544_EXPOSURE_MIN		4
#define SR544_EXPOSURE_MARGIN		4
#define SR544_AGAIN_MIN			0x10	/* 1x, 1/16 steps */
#define SR544_AGAIN_MAX			0xff

/* PLL from the init table: pre-divider 4, multiplier 67, MIPI divider 1 */
#define SR544_PLL_PREDIV		4
#define SR544_PLL_MULT			67
#define SR544_LANES			2
#define SR544_BPP			10

static const char * const sr544_supply_names[] = {
	"vdig",		/* 1.2 V core, GPIO-switched on SM-T550 (shared with the front camera) */
	"vana",		/* 2.8 V analog, GPIO-switched on SM-T550 (shared with the front camera) */
	"vaf",		/* 2.8 V autofocus actuator (pm8916 L10) */
};

struct sr544_mode {
	u32 width;
	u32 height;
	const struct sr544_reg *regs;	/* ends with the stream-on write */
	unsigned int num_regs;
};

static const struct sr544_mode sr544_modes[] = {
	{ .width = 2592, .height = 1944,
	  .regs = sr544_mode_5m, .num_regs = ARRAY_SIZE(sr544_mode_5m) },
	{ .width = 1296, .height = 972,
	  .regs = sr544_mode_1296x972, .num_regs = ARRAY_SIZE(sr544_mode_1296x972) },
	{ .width = 1280, .height = 720,
	  .regs = sr544_mode_720p, .num_regs = ARRAY_SIZE(sr544_mode_720p) },
};

struct sr544 {
	struct device *dev;
	struct i2c_client *client;
	struct v4l2_subdev sd;
	struct media_pad pad;
	struct clk *xclk;
	struct regulator_bulk_data supplies[ARRAY_SIZE(sr544_supply_names)];
	struct gpio_desc *reset_gpio;
	struct gpio_desc *pwdn_gpio;
	s64 link_freq;

	struct v4l2_ctrl_handler ctrls;
	struct v4l2_ctrl *exposure;
	struct v4l2_ctrl *vblank;
	struct v4l2_ctrl *hblank;

	const struct sr544_mode *mode;
};

static inline struct sr544 *to_sr544(struct v4l2_subdev *sd)
{
	return container_of(sd, struct sr544, sd);
}

static int sr544_write(struct sr544 *s, u16 reg, u16 val)
{
	u8 buf[4];
	int ret;

	put_unaligned_be16(reg, buf);
	put_unaligned_be16(val, buf + 2);
	ret = i2c_master_send(s->client, buf, sizeof(buf));
	if (ret < 0) {
		dev_err(s->dev, "write 0x%04x=0x%04x failed: %d\n", reg, val, ret);
		return ret;
	}
	return 0;
}

static int sr544_read(struct sr544 *s, u16 reg, u16 *val)
{
	u8 addr[2], data[2];
	struct i2c_msg msgs[] = {
		{ .addr = s->client->addr, .len = 2, .buf = addr },
		{ .addr = s->client->addr, .flags = I2C_M_RD, .len = 2, .buf = data },
	};
	int ret;

	put_unaligned_be16(reg, addr);
	ret = i2c_transfer(s->client->adapter, msgs, ARRAY_SIZE(msgs));
	if (ret != ARRAY_SIZE(msgs))
		return ret < 0 ? ret : -EIO;
	*val = get_unaligned_be16(data);
	return 0;
}

static int sr544_write_table(struct sr544 *s, const struct sr544_reg *regs,
			     unsigned int n)
{
	unsigned int i;
	int ret;

	for (i = 0; i < n; i++) {
		ret = sr544_write(s, regs[i].reg, regs[i].val);
		if (ret)
			return ret;
	}
	return 0;
}

/* Power sequence from the SM-T550 downstream camera DT (rear sensor). */
static int sr544_power_on(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct sr544 *s = to_sr544(sd);
	int ret;

	gpiod_set_value_cansleep(s->pwdn_gpio, 1);
	gpiod_set_value_cansleep(s->reset_gpio, 1);

	ret = regulator_bulk_enable(ARRAY_SIZE(s->supplies), s->supplies);
	if (ret)
		return ret;
	usleep_range(2000, 3000);

	gpiod_set_value_cansleep(s->pwdn_gpio, 0);

	ret = clk_prepare_enable(s->xclk);
	if (ret) {
		regulator_bulk_disable(ARRAY_SIZE(s->supplies), s->supplies);
		return ret;
	}
	usleep_range(5000, 6000);

	gpiod_set_value_cansleep(s->reset_gpio, 0);
	msleep(20);

	return 0;
}

static int sr544_power_off(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct sr544 *s = to_sr544(sd);

	gpiod_set_value_cansleep(s->reset_gpio, 1);
	clk_disable_unprepare(s->xclk);
	gpiod_set_value_cansleep(s->pwdn_gpio, 1);
	regulator_bulk_disable(ARRAY_SIZE(s->supplies), s->supplies);

	return 0;
}

static int sr544_set_ctrl(struct v4l2_ctrl *ctrl)
{
	struct sr544 *s = container_of(ctrl->handler, struct sr544, ctrls);
	int ret = 0;

	if (ctrl->id == V4L2_CID_VBLANK) {
		/* Keep the exposure inside the new frame length */
		s32 max = s->mode->height + ctrl->val - SR544_EXPOSURE_MARGIN;

		__v4l2_ctrl_modify_range(s->exposure, s->exposure->minimum, max,
					 s->exposure->step,
					 min(s->exposure->default_value, max));
	}

	if (!pm_runtime_get_if_in_use(s->dev))
		return 0;

	switch (ctrl->id) {
	case V4L2_CID_EXPOSURE:
		ret = sr544_write(s, SR544_REG_COARSE_EXPOSURE, ctrl->val);
		break;
	case V4L2_CID_ANALOGUE_GAIN:
		/* 8-bit gain code in the high byte; 0x003b is read-only */
		ret = sr544_write(s, SR544_REG_ANALOG_GAIN, ctrl->val << 8);
		break;
	case V4L2_CID_VBLANK:
		ret = sr544_write(s, SR544_REG_FRAME_LENGTH,
				  s->mode->height + ctrl->val);
		break;
	}

	pm_runtime_put(s->dev);
	return ret;
}

static const struct v4l2_ctrl_ops sr544_ctrl_ops = {
	.s_ctrl = sr544_set_ctrl,
};

static void sr544_update_blanking(struct sr544 *s)
{
	u32 vblank_min = SR544_VTS_MIN - s->mode->height;
	u32 hblank = SR544_HTS - s->mode->width;

	__v4l2_ctrl_modify_range(s->vblank, vblank_min,
				 SR544_VTS_MAX - s->mode->height, 1, vblank_min);
	__v4l2_ctrl_s_ctrl(s->vblank, vblank_min);
	__v4l2_ctrl_modify_range(s->hblank, hblank, hblank, 1, hblank);
}

static int sr544_enum_mbus_code(struct v4l2_subdev *sd,
				struct v4l2_subdev_state *state,
				struct v4l2_subdev_mbus_code_enum *code)
{
	if (code->index > 0)
		return -EINVAL;
	code->code = MEDIA_BUS_FMT_SBGGR10_1X10;
	return 0;
}

static int sr544_enum_frame_size(struct v4l2_subdev *sd,
				 struct v4l2_subdev_state *state,
				 struct v4l2_subdev_frame_size_enum *fse)
{
	if (fse->code != MEDIA_BUS_FMT_SBGGR10_1X10 ||
	    fse->index >= ARRAY_SIZE(sr544_modes))
		return -EINVAL;

	fse->min_width = fse->max_width = sr544_modes[fse->index].width;
	fse->min_height = fse->max_height = sr544_modes[fse->index].height;
	return 0;
}

static int sr544_set_fmt(struct v4l2_subdev *sd,
			 struct v4l2_subdev_state *state,
			 struct v4l2_subdev_format *format)
{
	struct sr544 *s = to_sr544(sd);
	const struct sr544_mode *mode;
	struct v4l2_mbus_framefmt *fmt;

	mode = v4l2_find_nearest_size(sr544_modes, ARRAY_SIZE(sr544_modes),
				      width, height, format->format.width,
				      format->format.height);

	fmt = v4l2_subdev_state_get_format(state, 0);
	fmt->width = mode->width;
	fmt->height = mode->height;
	fmt->code = MEDIA_BUS_FMT_SBGGR10_1X10;
	fmt->field = V4L2_FIELD_NONE;
	fmt->colorspace = V4L2_COLORSPACE_RAW;
	fmt->ycbcr_enc = V4L2_YCBCR_ENC_601;
	fmt->quantization = V4L2_QUANTIZATION_FULL_RANGE;
	fmt->xfer_func = V4L2_XFER_FUNC_NONE;
	format->format = *fmt;

	if (format->which == V4L2_SUBDEV_FORMAT_ACTIVE && s->mode != mode) {
		s->mode = mode;
		sr544_update_blanking(s);
	}

	return 0;
}

static int sr544_get_selection(struct v4l2_subdev *sd,
			       struct v4l2_subdev_state *state,
			       struct v4l2_subdev_selection *sel)
{
	switch (sel->target) {
	case V4L2_SEL_TGT_CROP:
	case V4L2_SEL_TGT_CROP_DEFAULT:
	case V4L2_SEL_TGT_CROP_BOUNDS:
	case V4L2_SEL_TGT_NATIVE_SIZE:
		sel->r.left = 0;
		sel->r.top = 0;
		sel->r.width = SR544_NATIVE_WIDTH;
		sel->r.height = SR544_NATIVE_HEIGHT;
		return 0;
	}
	return -EINVAL;
}

static int sr544_init_state(struct v4l2_subdev *sd,
			    struct v4l2_subdev_state *state)
{
	struct v4l2_subdev_format fmt = {
		.which = V4L2_SUBDEV_FORMAT_TRY,
		.format = {
			.width = sr544_modes[0].width,
			.height = sr544_modes[0].height,
		},
	};

	return sr544_set_fmt(sd, state, &fmt);
}

static int sr544_start(struct sr544 *s)
{
	int ret;

	/* Firmware + PLL (lost on every power-down) */
	ret = sr544_write_table(s, sr544_init, ARRAY_SIZE(sr544_init));
	if (ret)
		return ret;

	/* Mode setup without its trailing stream-on */
	ret = sr544_write_table(s, s->mode->regs, s->mode->num_regs - 1);
	if (ret)
		return ret;

	ret = __v4l2_ctrl_handler_setup(&s->ctrls);
	if (ret)
		return ret;

	return sr544_write(s, SR544_REG_MODE_SELECT, SR544_MODE_STREAMING);
}

static int sr544_enable_streams(struct v4l2_subdev *sd,
				struct v4l2_subdev_state *state, u32 pad,
				u64 streams_mask)
{
	struct sr544 *s = to_sr544(sd);
	int ret;

	ret = pm_runtime_resume_and_get(s->dev);
	if (ret < 0)
		return ret;

	ret = sr544_start(s);
	if (ret) {
		/* CCI resets itself after a timeout: power-cycle and retry once */
		dev_warn(s->dev, "start failed (%d), power-cycling the sensor\n", ret);
		sr544_power_off(s->dev);
		msleep(20);
		ret = sr544_power_on(s->dev);
		if (!ret)
			ret = sr544_start(s);
	}
	if (ret) {
		dev_err(s->dev, "could not start %ux%u\n", s->mode->width, s->mode->height);
		pm_runtime_put_sync(s->dev);
		return ret;
	}

	return 0;
}

static int sr544_disable_streams(struct v4l2_subdev *sd,
				 struct v4l2_subdev_state *state, u32 pad,
				 u64 streams_mask)
{
	struct sr544 *s = to_sr544(sd);
	int ret;

	ret = sr544_write(s, SR544_REG_MODE_SELECT, SR544_MODE_STANDBY);
	/*
	 * Power down right away: the next start uploads the sensor firmware
	 * again, and doing that while the sensor still runs wedges it.
	 */
	pm_runtime_put_sync_suspend(s->dev);

	return ret;
}

static const struct v4l2_subdev_video_ops sr544_video_ops = {
	.s_stream = v4l2_subdev_s_stream_helper,
};

static const struct v4l2_subdev_pad_ops sr544_pad_ops = {
	.enum_mbus_code = sr544_enum_mbus_code,
	.enum_frame_size = sr544_enum_frame_size,
	.get_fmt = v4l2_subdev_get_fmt,
	.set_fmt = sr544_set_fmt,
	.get_selection = sr544_get_selection,
	.enable_streams = sr544_enable_streams,
	.disable_streams = sr544_disable_streams,
};

static const struct v4l2_subdev_ops sr544_subdev_ops = {
	.video = &sr544_video_ops,
	.pad = &sr544_pad_ops,
};

static const struct v4l2_subdev_internal_ops sr544_internal_ops = {
	.init_state = sr544_init_state,
};

static int sr544_init_controls(struct sr544 *s)
{
	struct v4l2_fwnode_device_properties props;
	const struct v4l2_ctrl_ops *ops = &sr544_ctrl_ops;
	u32 vblank_min = SR544_VTS_MIN - s->mode->height;
	u32 hblank = SR544_HTS - s->mode->width;
	/* RAW10 over two lanes: bits per second / bits per pixel */
	u64 pixel_rate = div_u64(s->link_freq * 2 * SR544_LANES, SR544_BPP);
	struct v4l2_ctrl *ctrl;
	int ret;

	ret = v4l2_fwnode_device_parse(s->dev, &props);
	if (ret)
		return ret;

	v4l2_ctrl_handler_init(&s->ctrls, 8);

	v4l2_ctrl_new_std(&s->ctrls, ops, V4L2_CID_PIXEL_RATE,
			  pixel_rate, pixel_rate, 1, pixel_rate);
	ctrl = v4l2_ctrl_new_int_menu(&s->ctrls, ops, V4L2_CID_LINK_FREQ, 0, 0,
				      &s->link_freq);
	if (ctrl)
		ctrl->flags |= V4L2_CTRL_FLAG_READ_ONLY;

	s->vblank = v4l2_ctrl_new_std(&s->ctrls, ops, V4L2_CID_VBLANK, vblank_min,
				      SR544_VTS_MAX - s->mode->height, 1, vblank_min);
	s->hblank = v4l2_ctrl_new_std(&s->ctrls, ops, V4L2_CID_HBLANK, hblank,
				      hblank, 1, hblank);
	if (s->hblank)
		s->hblank->flags |= V4L2_CTRL_FLAG_READ_ONLY;

	s->exposure = v4l2_ctrl_new_std(&s->ctrls, ops, V4L2_CID_EXPOSURE,
					SR544_EXPOSURE_MIN,
					SR544_VTS_MIN - SR544_EXPOSURE_MARGIN, 1,
					SR544_VTS_MIN - SR544_EXPOSURE_MARGIN);
	v4l2_ctrl_new_std(&s->ctrls, ops, V4L2_CID_ANALOGUE_GAIN,
			  SR544_AGAIN_MIN, SR544_AGAIN_MAX, 1, SR544_AGAIN_MIN);

	v4l2_ctrl_new_fwnode_properties(&s->ctrls, ops, &props);

	if (s->ctrls.error) {
		ret = s->ctrls.error;
		v4l2_ctrl_handler_free(&s->ctrls);
		return ret;
	}

	s->sd.ctrl_handler = &s->ctrls;
	return 0;
}

static int sr544_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct v4l2_fwnode_endpoint ep = { .bus_type = V4L2_MBUS_CSI2_DPHY };
	struct fwnode_handle *endpoint;
	struct sr544 *s;
	unsigned long xclk_rate;
	unsigned int i;
	u16 id;
	int ret;

	s = devm_kzalloc(dev, sizeof(*s), GFP_KERNEL);
	if (!s)
		return -ENOMEM;
	s->dev = dev;
	s->client = client;
	s->mode = &sr544_modes[0];

	endpoint = fwnode_graph_get_next_endpoint(dev_fwnode(dev), NULL);
	if (!endpoint)
		return dev_err_probe(dev, -EINVAL, "endpoint node not found\n");
	ret = v4l2_fwnode_endpoint_parse(endpoint, &ep);
	fwnode_handle_put(endpoint);
	if (ret)
		return dev_err_probe(dev, ret, "parsing endpoint failed\n");
	if (ep.bus.mipi_csi2.num_data_lanes != SR544_LANES)
		return dev_err_probe(dev, -EINVAL, "only 2 data lanes are supported\n");

	s->xclk = devm_clk_get(dev, NULL);
	if (IS_ERR(s->xclk))
		return dev_err_probe(dev, PTR_ERR(s->xclk), "could not get xclk\n");
	xclk_rate = clk_get_rate(s->xclk);
	s->link_freq = div_u64((u64)xclk_rate * SR544_PLL_MULT, SR544_PLL_PREDIV);

	for (i = 0; i < ARRAY_SIZE(sr544_supply_names); i++)
		s->supplies[i].supply = sr544_supply_names[i];
	ret = devm_regulator_bulk_get(dev, ARRAY_SIZE(s->supplies), s->supplies);
	if (ret)
		return dev_err_probe(dev, ret, "could not get supplies\n");

	s->reset_gpio = devm_gpiod_get(dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(s->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(s->reset_gpio), "no reset gpio\n");
	s->pwdn_gpio = devm_gpiod_get(dev, "powerdown", GPIOD_OUT_HIGH);
	if (IS_ERR(s->pwdn_gpio))
		return dev_err_probe(dev, PTR_ERR(s->pwdn_gpio), "no powerdown gpio\n");

	v4l2_i2c_subdev_init(&s->sd, client, &sr544_subdev_ops);
	s->sd.internal_ops = &sr544_internal_ops;
	s->sd.flags |= V4L2_SUBDEV_FL_HAS_DEVNODE;
	s->sd.dev = dev;
	s->sd.entity.function = MEDIA_ENT_F_CAM_SENSOR;
	s->pad.flags = MEDIA_PAD_FL_SOURCE;

	ret = sr544_init_controls(s);
	if (ret)
		return dev_err_probe(dev, ret, "controls init failed\n");

	ret = media_entity_pads_init(&s->sd.entity, 1, &s->pad);
	if (ret)
		goto err_ctrls;

	ret = sr544_power_on(dev);
	if (ret)
		goto err_entity;

	ret = sr544_read(s, SR544_REG_CHIP_ID, &id);
	if (ret || id != SR544_CHIP_ID) {
		ret = dev_err_probe(dev, -ENODEV, "chip id 0x%04x != 0x%04x (%d)\n",
				    id, SR544_CHIP_ID, ret);
		goto err_power;
	}
	dev_info(dev, "SR544 detected at 0x%02x, xclk %lu Hz, link %lld Hz\n",
		 client->addr, xclk_rate, s->link_freq);

	s->sd.state_lock = s->ctrls.lock;
	ret = v4l2_subdev_init_finalize(&s->sd);
	if (ret)
		goto err_power;

	pm_runtime_set_active(dev);
	pm_runtime_get_noresume(dev);
	pm_runtime_enable(dev);

	ret = v4l2_async_register_subdev_sensor(&s->sd);
	if (ret)
		goto err_pm;

	pm_runtime_set_autosuspend_delay(dev, 1000);
	pm_runtime_use_autosuspend(dev);
	pm_runtime_put_autosuspend(dev);

	return 0;

err_pm:
	pm_runtime_disable(dev);
	pm_runtime_put_noidle(dev);
	v4l2_subdev_cleanup(&s->sd);
err_power:
	sr544_power_off(dev);
err_entity:
	media_entity_cleanup(&s->sd.entity);
err_ctrls:
	v4l2_ctrl_handler_free(&s->ctrls);
	return ret;
}

static void sr544_remove(struct i2c_client *client)
{
	struct v4l2_subdev *sd = i2c_get_clientdata(client);
	struct sr544 *s = to_sr544(sd);

	v4l2_async_unregister_subdev(sd);
	v4l2_subdev_cleanup(sd);
	media_entity_cleanup(&sd->entity);
	v4l2_ctrl_handler_free(&s->ctrls);

	pm_runtime_disable(s->dev);
	if (!pm_runtime_status_suspended(s->dev))
		sr544_power_off(s->dev);
	pm_runtime_set_suspended(s->dev);
}

static DEFINE_RUNTIME_DEV_PM_OPS(sr544_pm_ops, sr544_power_off, sr544_power_on, NULL);

static const struct of_device_id sr544_of_match[] = {
	{ .compatible = "siliconfile,sr544" },
	{ }
};
MODULE_DEVICE_TABLE(of, sr544_of_match);

static struct i2c_driver sr544_driver = {
	.driver = {
		.name = "sr544",
		.of_match_table = sr544_of_match,
		.pm = pm_ptr(&sr544_pm_ops),
	},
	.probe = sr544_probe,
	.remove = sr544_remove,
};
module_i2c_driver(sr544_driver);

MODULE_DESCRIPTION("SiliconFile SR544 camera sensor driver");
MODULE_LICENSE("GPL");
