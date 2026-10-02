// SPDX-License-Identifier: GPL-2.0-only
/*
 * SiliconFile SR200PC20 (Hynix Hi-253 family) 2MP YUV sensor with on-chip ISP.
 *
 * Front camera of the Samsung Galaxy Tab A 9.7 (SM-T550). Single-lane MIPI CSI-2,
 * UYVY output; register tables from Samsung's downstream driver (sr200pc20_regs.h).
 * Registers are 8-bit and paged: register 0x03 selects the page.
 */

#include <linux/clk.h>
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/of_graph.h>
#include <linux/pm_runtime.h>
#include <linux/regulator/consumer.h>
#include <media/v4l2-ctrls.h>
#include <media/v4l2-fwnode.h>
#include <media/v4l2-subdev.h>

struct sr200pc20_reg {
	u8 reg;
	u8 val;
};

#include "sr200pc20_regs.h"

#define SR200PC20_REG_PAGE		0x03
#define SR200PC20_REG_CHIP_ID		0x04	/* page 0 */
#define SR200PC20_CHIP_ID		0xb4
#define SR200PC20_REG_DELAY		0xff	/* table pseudo-register: sleep n * 10 ms */

/* ~24 MHz MIPI byte clock on one lane (downstream PLL comments), DDR */
#define SR200PC20_LINK_FREQ		96000000LL
/* 16 bpp UYVY on one lane: bit rate / 16 */
#define SR200PC20_PIXEL_RATE		(SR200PC20_LINK_FREQ * 2 / 16)

static const s64 sr200pc20_link_freqs[] = { SR200PC20_LINK_FREQ };

static const char * const sr200pc20_supply_names[] = {
	"vdig",		/* 1.2 V core, GPIO-switched on SM-T550 */
	"vana",		/* 2.8 V analog, GPIO-switched on SM-T550 */
	"vio",		/* 1.8 V I/O, optional (always on on later boards) */
};

struct sr200pc20_mode {
	u32 width;
	u32 height;
	const struct sr200pc20_reg *init;	/* full init, ends streaming SVGA */
	unsigned int num_init;
	const struct sr200pc20_reg *regs;	/* applied after the init table */
	unsigned int num_regs;
};

static const struct sr200pc20_mode sr200pc20_modes[] = {
	/* Fixed 24 fps preview (the auto-fps init drops to ~10 fps indoors) */
	{ .width = 800, .height = 600,
	  .init = sr200pc20_svga_24fps_50hz, .num_init = ARRAY_SIZE(sr200pc20_svga_24fps_50hz) },
	{ .width = 1600, .height = 1200,
	  .init = sr200pc20_init_50hz, .num_init = ARRAY_SIZE(sr200pc20_init_50hz),
	  .regs = sr200pc20_capture_uxga, .num_regs = ARRAY_SIZE(sr200pc20_capture_uxga) },
};

struct sr200pc20 {
	struct device *dev;
	struct i2c_client *client;
	struct v4l2_subdev sd;
	struct media_pad pad;
	struct clk *xclk;
	struct regulator_bulk_data supplies[ARRAY_SIZE(sr200pc20_supply_names)];
	struct gpio_desc *reset_gpio;
	struct gpio_desc *pwdn_gpio;
	struct v4l2_ctrl_handler ctrls;
	const struct sr200pc20_mode *mode;
};

static inline struct sr200pc20 *to_sr200pc20(struct v4l2_subdev *sd)
{
	return container_of(sd, struct sr200pc20, sd);
}

static int sr200pc20_write(struct sr200pc20 *s, u8 reg, u8 val)
{
	int ret = i2c_smbus_write_byte_data(s->client, reg, val);

	if (ret < 0)
		dev_err(s->dev, "write 0x%02x=0x%02x failed: %d\n", reg, val, ret);
	return ret;
}

static int sr200pc20_write_table(struct sr200pc20 *s,
				 const struct sr200pc20_reg *regs, unsigned int n)
{
	unsigned int i;
	int ret;

	for (i = 0; i < n; i++) {
		if (regs[i].reg == SR200PC20_REG_DELAY) {
			if (regs[i].val)
				msleep(regs[i].val * 10);
			continue;
		}
		ret = sr200pc20_write(s, regs[i].reg, regs[i].val);
		if (ret < 0)
			return ret;
	}
	return 0;
}

/* Power sequence from the SM-T550 downstream DT/blob (front camera). */
static int sr200pc20_power_on(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct sr200pc20 *s = to_sr200pc20(sd);
	int ret;

	gpiod_set_value_cansleep(s->pwdn_gpio, 1);
	gpiod_set_value_cansleep(s->reset_gpio, 1);

	ret = regulator_bulk_enable(ARRAY_SIZE(s->supplies), s->supplies);
	if (ret)
		return ret;
	usleep_range(5000, 6000);

	gpiod_set_value_cansleep(s->pwdn_gpio, 0);

	ret = clk_prepare_enable(s->xclk);
	if (ret) {
		regulator_bulk_disable(ARRAY_SIZE(s->supplies), s->supplies);
		return ret;
	}
	msleep(30);

	gpiod_set_value_cansleep(s->reset_gpio, 0);
	msleep(20);

	return 0;
}

static int sr200pc20_power_off(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct sr200pc20 *s = to_sr200pc20(sd);

	gpiod_set_value_cansleep(s->reset_gpio, 1);
	clk_disable_unprepare(s->xclk);
	gpiod_set_value_cansleep(s->pwdn_gpio, 1);
	regulator_bulk_disable(ARRAY_SIZE(s->supplies), s->supplies);

	return 0;
}

static int sr200pc20_enum_mbus_code(struct v4l2_subdev *sd,
				    struct v4l2_subdev_state *state,
				    struct v4l2_subdev_mbus_code_enum *code)
{
	if (code->index > 0)
		return -EINVAL;
	code->code = MEDIA_BUS_FMT_UYVY8_1X16;
	return 0;
}

static int sr200pc20_enum_frame_size(struct v4l2_subdev *sd,
				     struct v4l2_subdev_state *state,
				     struct v4l2_subdev_frame_size_enum *fse)
{
	if (fse->code != MEDIA_BUS_FMT_UYVY8_1X16 ||
	    fse->index >= ARRAY_SIZE(sr200pc20_modes))
		return -EINVAL;

	fse->min_width = fse->max_width = sr200pc20_modes[fse->index].width;
	fse->min_height = fse->max_height = sr200pc20_modes[fse->index].height;
	return 0;
}

static int sr200pc20_set_fmt(struct v4l2_subdev *sd,
			     struct v4l2_subdev_state *state,
			     struct v4l2_subdev_format *format)
{
	struct sr200pc20 *s = to_sr200pc20(sd);
	const struct sr200pc20_mode *mode;
	struct v4l2_mbus_framefmt *fmt;

	mode = v4l2_find_nearest_size(sr200pc20_modes, ARRAY_SIZE(sr200pc20_modes),
				      width, height, format->format.width,
				      format->format.height);

	fmt = v4l2_subdev_state_get_format(state, 0);
	fmt->width = mode->width;
	fmt->height = mode->height;
	fmt->code = MEDIA_BUS_FMT_UYVY8_1X16;
	fmt->field = V4L2_FIELD_NONE;
	fmt->colorspace = V4L2_COLORSPACE_SRGB;
	format->format = *fmt;

	if (format->which == V4L2_SUBDEV_FORMAT_ACTIVE)
		s->mode = mode;

	return 0;
}

static int sr200pc20_init_state(struct v4l2_subdev *sd,
				struct v4l2_subdev_state *state)
{
	struct v4l2_subdev_format fmt = {
		.which = V4L2_SUBDEV_FORMAT_TRY,
		.format = {
			.width = sr200pc20_modes[0].width,
			.height = sr200pc20_modes[0].height,
		},
	};

	return sr200pc20_set_fmt(sd, state, &fmt);
}

static int sr200pc20_get_selection(struct v4l2_subdev *sd,
				  struct v4l2_subdev_state *state,
				  struct v4l2_subdev_selection *sel)
{
	switch (sel->target) {
	case V4L2_SEL_TGT_CROP:
	case V4L2_SEL_TGT_CROP_DEFAULT:
	case V4L2_SEL_TGT_CROP_BOUNDS:
	case V4L2_SEL_TGT_NATIVE_SIZE:
		/* The on-chip ISP scales the whole array down for SVGA */
		sel->r.left = 0;
		sel->r.top = 0;
		sel->r.width = 1600;
		sel->r.height = 1200;
		return 0;
	}
	return -EINVAL;
}

/* The init tables end with sleep off: the sensor streams SVGA afterwards. */
static int sr200pc20_start(struct sr200pc20 *s)
{
	int ret;

	ret = sr200pc20_write_table(s, s->mode->init, s->mode->num_init);
	if (!ret && s->mode->regs)
		ret = sr200pc20_write_table(s, s->mode->regs, s->mode->num_regs);
	return ret;
}

static int sr200pc20_enable_streams(struct v4l2_subdev *sd,
				    struct v4l2_subdev_state *state, u32 pad,
				    u64 streams_mask)
{
	struct sr200pc20 *s = to_sr200pc20(sd);
	int ret;

	ret = pm_runtime_resume_and_get(s->dev);
	if (ret < 0)
		return ret;

	ret = sr200pc20_start(s);
	if (ret) {
		/*
		 * Occasionally the first CCI transfer after power-up times out.
		 * CCI resets itself on a timeout, so power-cycle the sensor and
		 * try once more instead of failing the stream (a failed start
		 * leaves the CAMSS pipeline busy until the modules are reloaded).
		 */
		dev_warn(s->dev, "start failed (%d), power-cycling the sensor\n", ret);
		sr200pc20_power_off(s->dev);
		msleep(20);
		ret = sr200pc20_power_on(s->dev);
		if (!ret)
			ret = sr200pc20_start(s);
	}
	if (ret) {
		dev_err(s->dev, "could not start %ux%u\n", s->mode->width, s->mode->height);
		pm_runtime_put_sync(s->dev);
		return ret;
	}

	return 0;
}

static int sr200pc20_disable_streams(struct v4l2_subdev *sd,
				     struct v4l2_subdev_state *state, u32 pad,
				     u64 streams_mask)
{
	struct sr200pc20 *s = to_sr200pc20(sd);
	int ret;

	ret = sr200pc20_write_table(s, sr200pc20_stop_stream,
				    ARRAY_SIZE(sr200pc20_stop_stream));
	pm_runtime_put_autosuspend(s->dev);

	return ret;
}

static const struct v4l2_subdev_video_ops sr200pc20_video_ops = {
	.s_stream = v4l2_subdev_s_stream_helper,
};

static const struct v4l2_subdev_pad_ops sr200pc20_pad_ops = {
	.enum_mbus_code = sr200pc20_enum_mbus_code,
	.enum_frame_size = sr200pc20_enum_frame_size,
	.get_fmt = v4l2_subdev_get_fmt,
	.set_fmt = sr200pc20_set_fmt,
	.get_selection = sr200pc20_get_selection,
	.enable_streams = sr200pc20_enable_streams,
	.disable_streams = sr200pc20_disable_streams,
};

static const struct v4l2_subdev_ops sr200pc20_subdev_ops = {
	.video = &sr200pc20_video_ops,
	.pad = &sr200pc20_pad_ops,
};

static const struct v4l2_subdev_internal_ops sr200pc20_internal_ops = {
	.init_state = sr200pc20_init_state,
};

static int sr200pc20_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct v4l2_fwnode_endpoint ep = { .bus_type = V4L2_MBUS_CSI2_DPHY };
	struct v4l2_fwnode_device_properties props;
	struct fwnode_handle *endpoint;
	struct sr200pc20 *s;
	struct v4l2_ctrl *ctrl;
	unsigned int i;
	int ret, id;

	s = devm_kzalloc(dev, sizeof(*s), GFP_KERNEL);
	if (!s)
		return -ENOMEM;
	s->dev = dev;
	s->client = client;
	s->mode = &sr200pc20_modes[0];

	endpoint = fwnode_graph_get_next_endpoint(dev_fwnode(dev), NULL);
	if (!endpoint)
		return dev_err_probe(dev, -EINVAL, "endpoint node not found\n");
	ret = v4l2_fwnode_endpoint_parse(endpoint, &ep);
	fwnode_handle_put(endpoint);
	if (ret)
		return dev_err_probe(dev, ret, "parsing endpoint failed\n");

	s->xclk = devm_clk_get(dev, NULL);
	if (IS_ERR(s->xclk))
		return dev_err_probe(dev, PTR_ERR(s->xclk), "could not get xclk\n");

	for (i = 0; i < ARRAY_SIZE(sr200pc20_supply_names); i++)
		s->supplies[i].supply = sr200pc20_supply_names[i];
	ret = devm_regulator_bulk_get(dev, ARRAY_SIZE(s->supplies), s->supplies);
	if (ret)
		return dev_err_probe(dev, ret, "could not get supplies\n");

	s->reset_gpio = devm_gpiod_get(dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(s->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(s->reset_gpio), "no reset gpio\n");
	s->pwdn_gpio = devm_gpiod_get(dev, "powerdown", GPIOD_OUT_HIGH);
	if (IS_ERR(s->pwdn_gpio))
		return dev_err_probe(dev, PTR_ERR(s->pwdn_gpio), "no powerdown gpio\n");

	v4l2_i2c_subdev_init(&s->sd, client, &sr200pc20_subdev_ops);
	s->sd.internal_ops = &sr200pc20_internal_ops;
	s->sd.flags |= V4L2_SUBDEV_FL_HAS_DEVNODE;
	s->sd.dev = dev;
	s->sd.entity.function = MEDIA_ENT_F_CAM_SENSOR;
	s->pad.flags = MEDIA_PAD_FL_SOURCE;

	ret = v4l2_fwnode_device_parse(dev, &props);
	if (ret)
		return ret;

	v4l2_ctrl_handler_init(&s->ctrls, 4);
	v4l2_ctrl_new_std(&s->ctrls, NULL, V4L2_CID_PIXEL_RATE,
			  SR200PC20_PIXEL_RATE, SR200PC20_PIXEL_RATE, 1,
			  SR200PC20_PIXEL_RATE);
	ctrl = v4l2_ctrl_new_int_menu(&s->ctrls, NULL, V4L2_CID_LINK_FREQ, 0, 0,
				      sr200pc20_link_freqs);
	if (ctrl)
		ctrl->flags |= V4L2_CTRL_FLAG_READ_ONLY;
	v4l2_ctrl_new_fwnode_properties(&s->ctrls, NULL, &props);
	if (s->ctrls.error) {
		ret = s->ctrls.error;
		goto err_ctrls;
	}
	s->sd.ctrl_handler = &s->ctrls;

	ret = media_entity_pads_init(&s->sd.entity, 1, &s->pad);
	if (ret)
		goto err_ctrls;

	ret = sr200pc20_power_on(dev);
	if (ret)
		goto err_entity;

	ret = sr200pc20_write(s, SR200PC20_REG_PAGE, 0x00);
	id = ret < 0 ? ret : i2c_smbus_read_byte_data(client, SR200PC20_REG_CHIP_ID);
	if (id != SR200PC20_CHIP_ID) {
		ret = dev_err_probe(dev, -ENODEV, "chip id 0x%02x != 0x%02x\n",
				    id & 0xff, SR200PC20_CHIP_ID);
		goto err_power;
	}
	dev_info(dev, "SR200PC20 detected at 0x%02x\n", client->addr);

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
	sr200pc20_power_off(dev);
err_entity:
	media_entity_cleanup(&s->sd.entity);
err_ctrls:
	v4l2_ctrl_handler_free(&s->ctrls);
	return ret;
}

static void sr200pc20_remove(struct i2c_client *client)
{
	struct v4l2_subdev *sd = i2c_get_clientdata(client);
	struct sr200pc20 *s = to_sr200pc20(sd);

	v4l2_async_unregister_subdev(sd);
	v4l2_subdev_cleanup(sd);
	media_entity_cleanup(&sd->entity);
	v4l2_ctrl_handler_free(&s->ctrls);

	pm_runtime_disable(s->dev);
	if (!pm_runtime_status_suspended(s->dev))
		sr200pc20_power_off(s->dev);
	pm_runtime_set_suspended(s->dev);
}

static DEFINE_RUNTIME_DEV_PM_OPS(sr200pc20_pm_ops, sr200pc20_power_off,
				 sr200pc20_power_on, NULL);

static const struct of_device_id sr200pc20_of_match[] = {
	{ .compatible = "siliconfile,sr200pc20" },
	{ }
};
MODULE_DEVICE_TABLE(of, sr200pc20_of_match);

static struct i2c_driver sr200pc20_driver = {
	.driver = {
		.name = "sr200pc20",
		.of_match_table = sr200pc20_of_match,
		.pm = pm_ptr(&sr200pc20_pm_ops),
	},
	.probe = sr200pc20_probe,
	.remove = sr200pc20_remove,
};
module_i2c_driver(sr200pc20_driver);

MODULE_DESCRIPTION("SiliconFile SR200PC20 camera sensor driver");
MODULE_LICENSE("GPL");
