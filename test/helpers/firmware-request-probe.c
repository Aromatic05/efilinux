#include <linux/device.h>
#include <linux/firmware.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>

static char *firmware_path = "iwlwifi-ty-a0-gf-a0-89.ucode";
module_param_named(path, firmware_path, charp, 0444);
MODULE_PARM_DESC(path, "firmware path to request");

static struct device *probe_device;

static int __init firmware_request_probe_init(void)
{
    const struct firmware *firmware;
    int error;

    probe_device = root_device_register("efilinux-firmware-probe");
    if (IS_ERR(probe_device))
        return PTR_ERR(probe_device);

    error = request_firmware(&firmware, firmware_path, probe_device);
    if (error) {
        root_device_unregister(probe_device);
        probe_device = NULL;
        return error;
    }

    pr_info(
        "EFILINUX_FIRMWARE_REQUEST_OK name=%s size=%zu\n",
        firmware_path,
        firmware->size);
    release_firmware(firmware);
    return 0;
}

static void __exit firmware_request_probe_exit(void)
{
    if (probe_device)
        root_device_unregister(probe_device);
}

module_init(firmware_request_probe_init);
module_exit(firmware_request_probe_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("EFI Linux firmware loader acceptance probe");
