#!/usr/bin/env bash
#
readonly ARCH_CPU="32BIT"

# U-Boot
readonly G_UBOOT_SRC_DIR="${DEF_SRC_DIR}/uboot"
readonly G_UBOOT_GIT="https://github.com/revolution-robotics/roadrunner-uboot-imx.git"
readonly G_UBOOT_BRANCH="imx_v2018.03_4.14.78_1.0.0_ga_var01_rr01"
readonly G_UBOOT_REV="d03d3714d7f2d9c081e19574256283aff91172a7"
readonly G_UBOOT_DEF_CONFIG_MMC='mx7d_roadrunner_defconfig'
readonly G_UBOOT_DEF_CONFIG_NAND='mx7d_roadrunner_nand_defconfig'
readonly G_UBOOT_NAME_FOR_EMMC='u-boot.img.mmc'
readonly G_SPL_NAME_FOR_EMMC='SPL.mmc'
readonly G_UBOOT_NAME_FOR_NAND='u-boot.img.nand'
readonly G_SPL_NAME_FOR_NAND='SPL.nand'

# Linux kernel
readonly G_LINUX_KERNEL_SRC_DIR="${DEF_SRC_DIR}/kernel"
readonly G_LINUX_KERNEL_GIT="https://github.com/revolution-robotics/roadrunner-linux-imx.git"
readonly G_LINUX_KERNEL_BRANCH="imx_4.14.78_1.0.0_ga_var01_rr01"
readonly G_LINUX_KERNEL_REV="d121ea4fddb34bc2c7b9f90731ea0eed8fb94b83"
readonly G_LINUX_KERNEL_DEF_CONFIG='imx_v7_roadrunner_defconfig'
G_LINUX_DTB="imx7d-roadrunner-mixio.dtb
        imx7d-roadrunner-dio.dtb"

UBOOT_SCRIPT="boot.scr"
UBOOT_PROVISION_SCRIPT="provision.scr"
BUILD_IMAGE_TYPE="uImage"
if test ."$BUILD_IMAGE_TYPE" = .'uImage'; then
    UIMAGE_LOADADDR=0x80800000
fi
KERNEL_BOOT_IMAGE_SRC="arch/arm/boot/"
KERNEL_DTB_IMAGE_PATH="arch/arm/boot/dts/"

# SDMA Firmware
readonly G_IMX_SDMA_FW_SRC_DIR="${G_VENDOR_PATH}/deb/firmware-misc-nonfree"

# Broadcom BT/WIFI firmware
readonly G_BCM_FW_SRC_DIR="${DEF_SRC_DIR}/bcmfw"
readonly G_BCM_FW_GIT="https://github.com/varigit/bcm_4343w_fw.git"
readonly G_BCM_FW_GIT_BRANCH="6.0.0.121"
readonly G_BCM_FW_GIT_REV="7bce9b69b51ffd967176c1597feed79305927370"

# ubi
readonly G_UBI_FILE_NAME='rootfs.ubi.img'

# Node version and user
NODE_BASE=v14
NODE_GROUP=revo
NODE_USER=revo
