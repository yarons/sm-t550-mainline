// SPDX-License-Identifier: GPL-2.0
/*
 * cdcpoke: test-only module that updates one register of the PM8916 analog codec through the PMIC's regmap
 * (regmap debugfs is read-only in this kernel). Loads, writes, prints before/after, and refuses to stay loaded.
 *   insmod cdcpoke.ko reg=0xf143 mask=0xff val=0x10
 */
#include <linux/device.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/regmap.h>

static uint reg = 0xf143, mask = 0xff, val;
module_param(reg, uint, 0444);
module_param(mask, uint, 0444);
module_param(val, uint, 0444);

static int __init cdcpoke_init(void)
{
	struct device *dev;
	struct regmap *map;
	uint before = 0, after = 0;
	int ret;

	dev = bus_find_device_by_name(&platform_bus_type, NULL, "200f000.spmi:pmic@1:audio-codec@f000");
	if (!dev)
		return -ENODEV;
	map = dev_get_regmap(dev->parent, NULL);
	if (!map) {
		put_device(dev);
		return -ENXIO;
	}
	regmap_read(map, reg, &before);
	ret = regmap_update_bits(map, reg, mask, val);
	regmap_read(map, reg, &after);
	pr_info("cdcpoke: reg 0x%x: 0x%02x -> 0x%02x (mask 0x%02x val 0x%02x) ret %d\n", reg, before, after, mask, val, ret);
	put_device(dev);
	return -EAGAIN;	/* done: do not stay loaded */
}
module_init(cdcpoke_init);
MODULE_DESCRIPTION("PM8916 analog codec register poke (test only)");
MODULE_LICENSE("GPL");
