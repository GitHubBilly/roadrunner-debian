#!/usr/bin/env bash
#
# @(#) boot.sh
#
# Copyright © 2020, Revolution Robotics, Inc.
#
# This U-Boot script probes for expansion modules and selects the
# appropriate flattened device tree (FDT) file. It then checks if
# recovery is requested, either by software `recovery_request' or by
# hardware reset button. If so booting to USB drive takes precedence.
#
# If recovery is not requested, but `usbboot_request' is set to
# `allow', then again booting to USB drive takes precedence.
#
# After an eMMC recovery procedure (e.g., from USB drive), the U-Boot
# environment variable `usbboot_request' must be assigned the value
# `override' to force booting to eMMC rootfs. From rootfs, the systemd
# service `reset-usbboot.service' then clears `usbboot_request' so
# that a USB drive can be booted on subsequent power cycle.
#
# To prevent ever booting to USB drive, the U-Boot environment
# variable `usbboot_request' should be set to `deny'. This is enforced
# until a recovery is requested. Once recovery is initiated, booting
# from USB drive takes precedence.

# NB: U-Boot && and || operators are evidently grouped by right
#     associativity - i.e.,
#         cmd1 && cmd2 || cmd3
#     is equivalent to
#         cmd1 && { cmd2 || cmd3; }
#     (except that U-Boot doesn't have curly brackets). This differs
#     from all Unix shells (which use left associativity), so should be
#     considered a bug and not used.

if test ."$usbboot_request" = .''; then
    usbboot_request=allow
fi

# Ensure that software recovery request doesn't persist across reboots.
sw_reset=$recovery_request
setenv recovery_request
saveenv

# Enable cgroup v2 and "mandatory access control (MAC)" security via SELinux.
setenv kernelargs $kernelargs systemd.unified_cgroup_hierarchy=1 security=selinux selinux=1 enforcing=0

reset_pin=83
usbdev=0
usbbootpart=1
usbrootpart=2
setenv usbloadimage 'load usb ${usbdev}:${usbbootpart} ${loadaddr} ${bootdir}/${image}'
setenv usbargs 'setenv bootargs console=${console},${baudrate} root=/dev/sda${usbrootpart} rootwait rw'
setenv usbloadfdt 'echo fdt_file=${fdt_file}; load usb ${usbdev}:${usbbootpart} ${fdt_addr} ${bootdir}/${fdt_file}'
setenv usbboot 'echo Booting from usb ...; run usbargs; run optargs; if test ${boot_fdt} = yes || test ${boot_fdt} = try; then if run usbloadfdt; then bootm ${loadaddr} - ${fdt_addr}; else if test ${boot_fdt} = try; then bootm; else echo WARN: Cannot load the DT; fi; fi;  else bootm; fi'
setenv green_pwr_led_off 'setenv silent 1; gpio clear 61; setenv silent'
setenv green_pwr_led_on 'setenv silent 1; gpio set 61; setenv silent'
setenv red_leds_on 'setenv silent 1; gpio set 60; gpio set 75; gpio set 74; setenv silent'
setenv red_leds_off 'setenv silent 1; gpio clear 60; gpio clear 75; gpio clear 74; setenv silent'
setenv hw_reset 'setenv silent 1; if gpio input $reset_pin; then enable_recovery=true; setenv reset_count 0xA; while itest.b $reset_count > 0; do setexpr reset_count $reset_count - 0x1; if $enable_recovery; then run red_leds_on; sleep 0.5; run red_leds_off; sleep 0.5; if gpio input $reset_pin; then true; else enable_recovery=false; fi; fi; done; $enable_recovery; else false; fi'

setenv silent 1
i2c dev 1
i2c probe 23
status23=$?
i2c probe 49
status49=$?
setenv silent

# If 0x23 is a valid I2C address...
if test $status23 -eq 0; then
    echo 'REVO digital GPIO expansion board detected'
    setenv fdt_file imx7d-roadrunner-dio.dtb
    setenv kernelargs "$kernelargs REVO_IND-GPIO-16_v1.0"

# If 0x49 is a valid I2C address...
elif test $status49 -eq 0; then
    echo 'REVO mixed-signal expansion board detected'
    setenv fdt_file imx7d-roadrunner-mixio.dtb
    setenv kernelargs "$kernelargs REVO_IOMIX-A_v1.0"

# Otherwise...
else
    echo 'Expansion board not detected'
fi

usb start
run green_pwr_led_off

# If eMMC is jumpered...
if test $mmcdev -eq 1; then

    # If either reset button pressed or software reset requested...
    if test ."$sw_reset" = .'true' || run hw_reset; then
        setenv silent
        run red_leds_on
        sleep 5
        run red_leds_off
        run green_pwr_led_on

        # If bootable USB drive present...
        if run usbloadimage; then
            setenv kernelargs "$kernelargs flash_emmc_from_usb"
            echo "Processing USB recovery request..."
            run usbboot

        # Otherwise, if bootable eMMC or SD drive present...
        elif run loadimage; then

            # Use recovery partition.
            setenv mmcrootpart 3
            setenv kernelargs "$kernelargs flash_emmc_from_emmc"
            echo "Processing eMMC recovery request..."
            run mmcboot

        # Otherwise, try booting over the network...
        else
            setenv kernelargs "$kernelargs flash_emmc_from_net"
            echo "Processing net recovery request..."
            run netboot
        fi
    fi
fi

# Otherwise, if USB boot is enabled and bootable USB drive present...
if test ."$usbboot_request" = .'allow' && run usbloadimage; then
    run green_pwr_led_on
    if test $mmcdev -eq 1; then
        setenv kernelargs "$kernelargs flash_emmc_from_usb"
        echo "Processing USB recovery request..."
    fi
    run usbboot

# Otherwise, if bootable eMMC or SD drive present...
elif run loadimage; then
    run green_pwr_led_on
    if test ."$usbboot_request" = .'override'; then
       setenv kernelargs "$kernelargs reset_usbboot"
    fi
    run mmcboot

# Otherwise, try booting over the network...
else
    run netboot
fi
