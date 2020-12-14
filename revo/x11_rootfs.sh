#!/usr/bin/env bash
#

remove-charmaps ()
{
    # Remove non-essential charmaps from /usr/share/i18n/charmaps
    local charmap quoted
    local -a find_args=()
    local -a charmaps=(
        $(tr -s ' ' '\n' <<<"$LOCALES UTF-8 ISO-8859-1" |
              sed -e 's/.*\.//' |
              sort -u)
    )
    for charmap in "${charmaps[@]}"; do
        printf -v quoted "%q.gz" "$charmap";

        if (( ${#find_args[*]} == 0 )); then
            find_args=( -name "$quoted" )
        else
            find_args+=( -or -name "$quoted" )
        fi
    done
    eval find "${ROOTFS_BASE}/usr/share/i18n/charmaps" -type f \
          ${find_args[0]:+"-not \\( ${find_args[@]} \\)"} -delete
}

remove-locales ()
{
    # Remove non-essential charmaps from /usr/share/i18n/locales
    local charmap quoted
    local -a find_args=()
    local -a locales=(
        $(tr -s ' ' '\n' <<<"$LOCALES" |
            sed -n -e 's/\..*//' -e '/_/p' -e 's/_.*//p')
    )
    local locale

    locales+=( C POSIX )
    for locale in "${locales[@]}"; do
        printf -v quoted "%q" "$locale";

        if (( ${#find_args[*]} == 0 )); then
            find_args=( -name "$quoted" )

            # If keeping, e.g., `en_IE', also keep `en_IE@euro'.
            if [[ ."$quoted" =~ \.[^_]+_[^@]+$ ]]; then
                find_args+=( -or -name "${quoted}@*" )
            fi
        else
            find_args+=( -or -name "$quoted" )

            # If keeping, e.g., `en_IE', also keep `en_IE@euro'.
            if [[ ."$quoted" =~ \.[^_]+_[^@]+$ ]]; then
                find_args+=( -or -name "${quoted}@*" )
            fi
        fi
    done
    eval find "${ROOTFS_BASE}/usr/share/i18n/locales" -type f \
          ${find_args[0]:+"-not \\( ${find_args[@]} \\)"} -delete
}

# Must be called after make_prepare in main script
# function generate rootfs in input dir
# $1 - rootfs base dir
make_debian_x11_rootfs ()
{
    local ROOTFS_BASE=$1

    pr_info "Make debian(${DEB_RELEASE}) rootfs start..."

    # umount previus mounts (if fail)
    umount -f ${ROOTFS_BASE}/{sys,proc,dev/pts,dev} 2>/dev/null || true

    # clear rootfs dir
    rm -rf ${ROOTFS_BASE}/*

    pr_info "rootfs: debootstrap"
    debootstrap --verbose  --foreign --arch armhf \
                --keyring='/etc/apt/trusted.gpg' \
                ${DEB_RELEASE} ${ROOTFS_BASE}/ ${PARAM_DEB_LOCAL_MIRROR}

    # prepare qemu
    pr_info "rootfs: debootstrap in rootfs (second-stage)"
    install -m 0755 ${G_VENDOR_PATH}/qemu_32bit/qemu-arm-static ${ROOTFS_BASE}/usr/bin/qemu-arm-static

    umount_rootfs ()
    {
        umount -f ${ROOTFS_BASE}/{sys,proc,dev/pts,dev} 2>/dev/null || true
        umount -f ${ROOTFS_BASE}/dev 2>/dev/null || true
    }

    trap 'umount_rootfs' RETURN
    trap 'umount_rootfs; exit' 0 1 2 15

    if ! findmnt ${ROOTFS_BASE}/proc >/dev/null; then
        mount -t proc /proc ${ROOTFS_BASE}/proc
    fi

    for fs in /sys /dev /dev/pts; do
        if ! findmnt "${ROOTFS_BASE}/${fs}" >/dev/null; then
            mount -o bind "$fs" "${ROOTFS_BASE}/${fs}"
        fi
    done

    chroot $ROOTFS_BASE /debootstrap/debootstrap --second-stage

    # delete unused folder
    chroot $ROOTFS_BASE rm -rf  ${ROOTFS_BASE}/debootstrap

    pr_info "rootfs: generate default configs"
    mkdir -p ${ROOTFS_BASE}/etc/sudoers.d/
    echo "user ALL=(root) /usr/bin/apt, /usr/bin/apt-get, /usr/bin/dpkg, /sbin/reboot, /sbin/shutdown, /sbin/halt" > ${ROOTFS_BASE}/etc/sudoers.d/user
    chmod 0440 ${ROOTFS_BASE}/etc/sudoers.d/user
    mkdir -p ${ROOTFS_BASE}/srv/local-apt-repository

    # udisk2
    cp -r ${G_VENDOR_PATH}/deb/udisks2/* \
       ${ROOTFS_BASE}/srv/local-apt-repository
    # gstreamer-imx
    cp -r ${G_VENDOR_PATH}/deb/gstreamer-imx/* \
       ${ROOTFS_BASE}/srv/local-apt-repository
    # shared-mime-info
    # cp -r ${G_VENDOR_PATH}/deb/shared-mime-info/* \
    #    ${ROOTFS_BASE}/srv/local-apt-repository

    # BEGIN -- REVO i.MX7D security
    mkdir -p ${ROOTFS_BASE}/etc/sudoers.d/
    echo "revo ALL=(ALL:ALL) NOPASSWD: ALL" > ${ROOTFS_BASE}/etc/sudoers.d/revo
    chmod 0440 ${ROOTFS_BASE}/etc/sudoers.d/revo

    cp -r ${G_VENDOR_PATH}/deb/smallstep/* \
       ${ROOTFS_BASE}/srv/local-apt-repository

    cp -r ${G_VENDOR_PATH}/deb/firewalld/* \
       ${ROOTFS_BASE}/srv/local-apt-repository
    # END -- REVO i.MX7D security

    # add mirror to source list
    cat >${ROOTFS_BASE}/etc/apt/sources.list <<EOF
deb ${PARAM_DEB_LOCAL_MIRROR} ${DEB_RELEASE} main contrib non-free
deb-src ${PARAM_DEB_LOCAL_MIRROR} ${DEB_RELEASE} main contrib non-free
deb ${PARAM_DEB_LOCAL_MIRROR} ${DEB_RELEASE}-backports main contrib non-free
deb-src ${PARAM_DEB_LOCAL_MIRROR} ${DEB_RELEASE}-backports main contrib non-free
EOF

    # raise backports priority
    cat >${ROOTFS_BASE}/etc/apt/preferences.d/backports <<EOF
Package: *
Pin: release n=${DEB_RELEASE}-backports
Pin-Priority: 500
EOF

    # maximize local repo priority
    cat >${ROOTFS_BASE}/etc/apt/preferences.d/local <<EOF
Package: *
Pin: origin ""
Pin-Priority: 1000
EOF

    cat >${ROOTFS_BASE}/etc/fstab <<EOF

# /dev/mmcblk0p1  /boot           vfat    defaults        0       0
EOF

    # Unique hostname generated on boot (see below).
    # echo "$MACHINE" > etc/hostname

    # "127.0.1.1 $hostname"  added when hostname generated on boot
    cat >${ROOTFS_BASE}/etc/hosts <<EOF
127.0.0.1	localhost

# The following lines are desirable for IPv6 capable hosts
::1		ip6-localhost ip6-loopback
fe00::0		ip6-localnet
ff00::0		ip6-mcastprefix
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
EOF

#     echo "auto lo
# iface lo inet loopback
# " > etc/network/interfaces

    cat >${ROOTFS_BASE}/debconf.set <<EOF
locales locales/locales_to_be_generated multiselect $LOCALES
locales locales/default_environment_locale select ${LOCALES%% *}
console-common	console-data/keymap/policy	select	Select keymap from full list
keyboard-configuration keyboard-configuration/variant select 'English (US)'
openssh-server openssh-server/permit-root-login select true
EOF

    pr_info "rootfs: prepare install packages in rootfs"

    # Run apt install without invoking daemons.
    cat > ${ROOTFS_BASE}/usr/sbin/policy-rc.d << EOF
#!/bin/sh
exit 101
EOF

    chmod +x ${ROOTFS_BASE}/usr/sbin/policy-rc.d

    # third packages stage
    cat > ${ROOTFS_BASE}/third-stage << EOF
#!/bin/bash
# apply debconfig options
echo 'LANG="${LOCALES%% *}"' >/etc/default/locale
dpkg-reconfigure --frontend=noninteractive locales
debconf-set-selections /debconf.set
rm -f /debconf.set

protected_install ()
{
    local _name=\${1}
    local repeated_cnt=5
    local RET_CODE=1

    for (( c=0; c < \${repeated_cnt}; c++ )); do
        apt -y install \${_name} && {
            RET_CODE=0
            break
        }

        echo ""
        echo "###########################"
        echo "## Fix missing packeges ###"
        echo "###########################"
        echo ""

        sleep 2
        apt -y --fix-broken install && {
                RET_CODE=0
                break
        }
    done

    return \${RET_CODE}
}

# BEGIN -- REVO i.MX7D: additions
# silence some apt warnings
protected_install dialog

# Replace mawk with gawk
protected_install gawk
apt -y purge mawk
# END -- REVO i.MX7D: additions

# update packages and install base
apt update
apt -y full-upgrade

# local-apt-repository support
protected_install local-apt-repository
protected_install reprepro
reprepro rereference

# update packages and install base
apt update

protected_install locales
protected_install ntp
protected_install openssh-server
protected_install nfs-common

# packages required when flashing emmc
protected_install dosfstools

# fix config for sshd (permit root login)
sed -i -e 's/#PermitRootLogin.*/PermitRootLogin\tyes/g' /etc/ssh/sshd_config

# rng-tools
protected_install rng-tools

# udisk2
protected_install udisks2

# gvfs
protected_install gvfs

# gvfs-daemons
protected_install gvfs-daemons

# net-tools (ifconfig, etc.)
protected_install net-tools

# enable graphical desktop
protected_install xorg
protected_install xfce4
protected_install xfce4-goodies

# network manager
protected_install network-manager-gnome

# net-tools (ifconfig, etc.)
protected_install net-tools

## fix lightdm config (added autologin x_user) ##
sed -i -e 's/\#autologin-user=/autologin-user=x_user/g' /etc/lightdm/lightdm.conf
sed -i -e 's/\#autologin-user-timeout=0/autologin-user-timeout=0/g' /etc/lightdm/lightdm.conf

# added alsa & alsa utilites
protected_install alsa-utils
protected_install gstreamer1.0-alsa

protected_install gstreamer1.0-plugins-bad
protected_install gstreamer1.0-plugins-base
protected_install gstreamer1.0-plugins-ugly
protected_install gstreamer1.0-plugins-good
protected_install gstreamer1.0-tools

# added gstreamer-imx
protected_install gstreamer-imx

# added i2c tools
protected_install i2c-tools

# added usb tools
protected_install usbutils

# added net tools
protected_install iperf

# mtd
protected_install mtd-utils

# bluetooth
protected_install bluetooth
protected_install bluez-obexd
protected_install bluez-tools
protected_install blueman
protected_install gconf2

# shared-mime-info
protected_install shared-mime-info

# wifi support packages
# protected_install hostapd
# protected_install udhcpd

# disable the hostapd service by default
# systemctl disable hostapd.service

# can support
protected_install can-utils

# pm-utils
protected_install pm-utils

# BEGIN -- REVO i.MX7D networking and security
protected_install firewalld
protected_install step-cli
protected_install step-certificates

# ifupdown is superceded by NetworkManager
apt -y purge ifupdown
rm -f /etc/network/interfaces

# iptables is superceded by nftables, but NetworkManager still depends
# on compatibility interface, iptables-nft, provided by iptables.
# See https://www.redhat.com/en/blog/using-iptables-nft-hybrid-linux-firewall.
# apt -y purge iptables
DEBIAN_FRONTEND=noninteractive apt -y install iptables-persistent
rm -f /etc/iptables/rules.v[46]

# Defaults, starting with Debian buster:
# update-alternatives --set iptables /usr/sbin/iptables-nft
# update-alternatives --set ip6tables /usr/sbin/ip6tables-nft
# update-alternatives --set arptables /usr/sbin/arptables-nft
# update-alternatives --set ebtables /usr/sbin/ebtables-nft

# Install firewalld with nftables backend.
apt -y install firewalld nftables
sed -i -e 's/^\(FirewallBackend=\).*/\1nftables/' /etc/firewalld/firewalld.conf
# END -- REVO i.MX7D networking

apt -y autoremove

apt -y install --reinstall libgdk-pixbuf2.0-0

# create users and set password
echo "root:root" | chpasswd

useradd -m -G audio,video -s /bin/bash user
useradd -m -G audio,video -s /bin/bash x_user
# echo "user:user" | chpasswd
# passwd -d x_user

# BEGIN -- REVO i.MX7D users
useradd -m -G audio,bluetooth,lp,pulse,pulse-access,video -s /bin/bash -c "REVO Roadrunner" revo
useradd -m -s /bin/bash -c "Smallstep PKI" step
# END -- REVO i.MX7D users

rm -f /third-stage
EOF

    pr_info "rootfs: install selected debian packages (third-stage)"
    chmod +x ${ROOTFS_BASE}/third-stage
    LANG=C chroot ${ROOTFS_BASE} /third-stage
    # fourth-stage

    # BEGIN -- REVO i.MX7D updates
    # Update logrotate
    install -m 0644 "${G_VENDOR_PATH}/${MACHINE}/logrotate/logrotate.conf" \
            "${ROOTFS_BASE}/etc"
    install -m 0644 "${G_VENDOR_PATH}/${MACHINE}/logrotate/rsyslog" \
            "${ROOTFS_BASE}/etc/logrotate.d"

    # Generate unique hostname on first boot
    install -m 0644 "${G_VENDOR_PATH}/${MACHINE}/systemd/hostname-commit.service" \
            "${ROOTFS_BASE}/lib/systemd/system"
    install -d -m 0755 "${ROOTFS_BASE}/etc/systemd/system/network.target.wants"
    ln -s '/lib/systemd/system/hostname-commit.service' \
       "${ROOTFS_BASE}/etc/systemd/system/network.target.wants"
    install -m 0755 "${G_VENDOR_PATH}/${MACHINE}/systemd/commit-hostname" "${ROOTFS_BASE}/usr/sbin"

    # Remove machine ID and hostname to force generation of unique ones.
    rm -f "${ROOTFS_BASE}/etc/machine-id" \
       "${ROOTFS_BASE}/var/lib/dbus/machine-id" \
       "${ROOTFS_BASE}/etc/hostname"

    # Exim mailname is updated when hostname generated
    # echo "$MACHINE" > "${ROOTFS_BASE}/etc/mailname"

    # Regenerate SSH keys on first boot
    install -m 0644 "${G_VENDOR_PATH}/${MACHINE}/systemd/regenerate-ssh-host-keys.service" \
            "${ROOTFS_BASE}/lib/systemd/system"
    ln -s '/lib/systemd/system/regenerate-ssh-host-keys.service' \
       "${ROOTFS_BASE}/etc/systemd/system/multi-user.target.wants"

    # Support resizing a serial console - taken from Debian xterm package.
    if test ! -f "${ROOTFS_BASE}/usr/bin/resize"; then
        install -m 0755 ${G_VENDOR_PATH}/${MACHINE}/resize \
                ${ROOTFS_BASE}/usr/bin
    fi

    # Set PATH and resize serial console window.
    install -m 0755 "${G_VENDOR_PATH}/${MACHINE}/bash.bashrc" \
            "${ROOTFS_BASE}/etc"
    install -m 0755 "${G_VENDOR_PATH}/${MACHINE}/profile" \
            "${ROOTFS_BASE}/etc"
    install -d -m 0755 "${ROOTFS_BASE}/etc/profile.d"
    install -m 0644 "${G_VENDOR_PATH}/${MACHINE}/set_window_title.sh" \
            "${ROOTFS_BASE}/etc/profile.d"

    # Install redirect-web-ports.
    install -m 0755 "${G_VENDOR_PATH}/resources/redirect-web-ports" \
            "${ROOTFS_BASE}/usr/sbin"

    # Add RS485 mode configuration utility.
    install -m 0755 "${G_VENDOR_PATH}/${MACHINE}/rs485" \
            "${ROOTFS_BASE}/usr/bin"

    # Mount /tmp, /var/tmp and /var/log on tmpfs.
    install -m 0644 "${ROOTFS_BASE}/usr/share/systemd/tmp.mount" \
            "${ROOTFS_BASE}/lib/systemd/system"
    install -m 0644 "${G_VENDOR_PATH}/${MACHINE}/systemd/var-"{log,tmp}.mount \
            "${ROOTFS_BASE}/lib/systemd/system"
    install -m 0644 "${G_VENDOR_PATH}/${MACHINE}/systemd/var-log.conf" \
            "${ROOTFS_BASE}/usr/lib/tmpfiles.d"

    # Mount systemd journal on tmpfs, /run/log/journal.
    install -m 0644 "${G_VENDOR_PATH}/${MACHINE}/systemd/journald.conf" \
            "${ROOTFS_BASE}/etc/systemd"

    # Install flash-emmc service.
    install -m 0644 "${G_VENDOR_PATH}/${MACHINE}/systemd/flash-emmc.service" \
            "${ROOTFS_BASE}/lib/systemd/system"
    install -d -m 0755 "${ROOTFS_BASE}/lib/systemd/system/system-update.target.wants"
    ln -s '../flash-emmc.service' \
       "${ROOTFS_BASE}/lib/systemd/system/system-update.target.wants"
    install -m 0755 "${G_VENDOR_PATH}/${MACHINE}/systemd/flash-emmc" "${ROOTFS_BASE}/usr/sbin"

    # Install recover-emmc-monitor service
    install -m 0755 "${G_VENDOR_PATH}/${MACHINE}/systemd/recover-emmc-monitor" \
            "${ROOTFS_BASE}/usr/sbin"
    install -m 0644 "${G_VENDOR_PATH}/${MACHINE}/systemd/recover-emmc-monitor.service" \
            "${ROOTFS_BASE}/lib/systemd/system"
    ln -s '/lib/systemd/system/recover-emmc-monitor.service' \
       "${ROOTFS_BASE}/etc/systemd/system/multi-user.target.wants"

    # Install reset-usbboot service.
    install -m 0644 "${G_VENDOR_PATH}/${MACHINE}/systemd/reset-usbboot.service" \
            "${ROOTFS_BASE}/lib/systemd/system"
    ln -s '/lib/systemd/system/reset-usbboot.service' \
       "${ROOTFS_BASE}/etc/systemd/system/multi-user.target.wants"

    # Enable NetworkManager dispatcher
    ln -sf '/lib/systemd/system/NetworkManager-dispatcher.service' \
       "${ROOTFS_BASE}/etc/systemd/system/dbus-org.freedesktop.nm-dispatcher.service"

    # Fix NetworkManager dispatch permissions set by Git
    chmod -R g-w "${G_VENDOR_PATH}/NetworkManager/"*
    chmod 750 "${G_VENDOR_PATH}/NetworkManager/etc/NetworkManager/dispatcher.d/30-link-led"

    # Install NetworkManager scripts
    tar -C "${G_VENDOR_PATH}/NetworkManager" -cf - . |
        tar -C "${ROOTFS_BASE}" -oxf -

    rm -f "${ROOTFS_BASE}/etc/NetworkManager/dispatcher.d/"*ifupdown

    # END -- REVO i.MX7D update

    # install variscite-bt service
    install -m 0755 ${G_VENDOR_PATH}/resources/brcm_patchram_plus \
            ${ROOTFS_BASE}/usr/bin
    install -d ${ROOTFS_BASE}/etc/bluetooth
    install -m 0644 ${G_VENDOR_PATH}/${MACHINE}/variscite-bt.conf \
            ${ROOTFS_BASE}/etc/bluetooth
    install -m 0755 ${G_VENDOR_PATH}/resources/variscite-bt \
            ${ROOTFS_BASE}/etc/bluetooth
    install -m 0644 ${G_VENDOR_PATH}/resources/variscite-bt.service \
            ${ROOTFS_BASE}/lib/systemd/system
    ln -s /lib/systemd/system/variscite-bt.service \
       ${ROOTFS_BASE}/etc/systemd/system/multi-user.target.wants/variscite-bt.service

    # install BT audio and main config
    install -m 0644 ${G_VENDOR_PATH}/resources/bluez5/files/audio.conf \
            ${ROOTFS_BASE}/etc/bluetooth/
    install -m 0644 ${G_VENDOR_PATH}/resources/bluez5/files/main.conf \
            ${ROOTFS_BASE}/etc/bluetooth/

    # install obexd configuration
    install -m 0644 ${G_VENDOR_PATH}/resources/bluez5/files/obexd.conf \
            ${ROOTFS_BASE}/etc/dbus-1/system.d

    install -m 0644 ${G_VENDOR_PATH}/resources/bluez5/files/obex.service \
            ${ROOTFS_BASE}/lib/systemd/system
    ln -s /lib/systemd/system/obex.service \
       ${ROOTFS_BASE}/etc/systemd/system/multi-user.target.wants/obex.service

    # install pulse audio configuration
    install -m 0644 ${G_VENDOR_PATH}/resources/pulseaudio/pulseaudio.service \
            ${ROOTFS_BASE}/lib/systemd/system
    ln -s /lib/systemd/system/pulseaudio.service \
       ${ROOTFS_BASE}/etc/systemd/system/multi-user.target.wants/pulseaudio.service
    install -m 0644 ${G_VENDOR_PATH}/resources/pulseaudio/pulseaudio-bluetooth.conf \
            ${ROOTFS_BASE}/etc/dbus-1/system.d
    install -m 0644 ${G_VENDOR_PATH}/resources/pulseaudio/system.pa \
            ${ROOTFS_BASE}/etc/pulse/

    # Add alsa default configs
    install -m 0644 ${G_VENDOR_PATH}/resources/asound.state \
            ${ROOTFS_BASE}/var/lib/alsa/
    install -m 0644 ${G_VENDOR_PATH}/resources/asound.conf ${ROOTFS_BASE}/etc/

    # install variscite-wifi service
    install -d ${ROOTFS_BASE}/etc/wifi
    install -m 0644 ${G_VENDOR_PATH}/resources/blacklist.conf \
            ${ROOTFS_BASE}/etc/wifi
    install -m 0644 ${G_VENDOR_PATH}/${MACHINE}/variscite-wifi.conf \
            ${ROOTFS_BASE}/etc/wifi
    install -m 0644 ${G_VENDOR_PATH}/resources/variscite-wifi-common.sh \
            ${ROOTFS_BASE}/etc/wifi
    install -m 0755 ${G_VENDOR_PATH}/resources/variscite-wifi \
            ${ROOTFS_BASE}/etc/wifi
    install -m 0644 ${G_VENDOR_PATH}/resources/variscite-wifi.service \
            ${ROOTFS_BASE}/lib/systemd/system
    ln -s /lib/systemd/system/variscite-wifi.service \
       ${ROOTFS_BASE}/etc/systemd/system/multi-user.target.wants/variscite-wifi.service

    # remove pm-utils default scripts and install wifi / bt pm-utils script
    rm -rf ${ROOTFS_BASE}/usr/lib/pm-utils/sleep.d/
    rm -rf ${ROOTFS_BASE}/usr/lib/pm-utils/module.d/
    rm -rf ${ROOTFS_BASE}/usr/lib/pm-utils/power.d/
    install -m 0755 ${G_VENDOR_PATH}/${MACHINE}/wifi.sh \
            ${ROOTFS_BASE}/etc/pm/sleep.d/

    # tar -xzf ${G_VENDOR_PATH}/deb/shared-mime-info/mime_image_prebuilt.tar.gz -C \
    #     ${ROOTFS_BASE}/
    ## end packages stage ##
    if test ."${G_USER_PACKAGES}" != .''; then

        pr_info "rootfs: install user defined packages (user-stage)"
        pr_info "rootfs: G_USER_PACKAGES \"${G_USER_PACKAGES}\" "

        cat > ${ROOTFS_BASE}/user-stage << EOF
#!/bin/bash
# update packages
apt update

# install all user packages from backports
DEBIAN_FRONTEND=noninteractive apt -yq -t ${DEB_RELEASE}-backports install ${G_USER_PACKAGES}
pip3 install minimalmodbus
pip3 install pystemd
pip3 install pytz

rm -f /user-stage
EOF

        chmod +x ${ROOTFS_BASE}/user-stage
        LANG=C chroot ${ROOTFS_BASE} /user-stage

    fi

    # binaries rootfs patching
    install -m 0644 ${G_VENDOR_PATH}/issue ${ROOTFS_BASE}/etc/
    install -m 0644 ${G_VENDOR_PATH}/issue.net ${ROOTFS_BASE}/etc/
    install -m 0755 ${G_VENDOR_PATH}/resources/rc.local ${ROOTFS_BASE}/etc/
    install -m 0644 ${G_VENDOR_PATH}/resources/hostapd.conf ${ROOTFS_BASE}/etc/
    install -d ${ROOTFS_BASE}/boot/
    install -m 0644 ${G_VENDOR_PATH}/splash.bmp ${ROOTFS_BASE}/boot/
    install -m 0644 ${G_VENDOR_PATH}/wallpaper.png \
            ${ROOTFS_BASE}/usr/share/images/desktop-base/default

    # disable light-locker
    install -m 0755 ${G_VENDOR_PATH}/resources/disable-lightlocker \
            ${ROOTFS_BASE}/usr/local/bin/
    install -m 0644 ${G_VENDOR_PATH}/resources/disable-lightlocker.desktop \
            ${ROOTFS_BASE}/etc/xdg/autostart/

    # Revert regular booting
    rm -f ${ROOTFS_BASE}/usr/sbin/policy-rc.d

    # install kernel modules in rootfs
    install_kernel_modules \
        ${G_CROSS_COMPILER_PATH}/${G_CROSS_COMPILER_PREFIX} \
        ${G_LINUX_KERNEL_DEF_CONFIG} ${G_LINUX_KERNEL_SRC_DIR} \
        ${ROOTFS_BASE}

    # copy all kernel headers for development
    mkdir -p ${ROOTFS_BASE}/usr/local/src/linux-imx/drivers/staging/android/uapi
    cp ${G_LINUX_KERNEL_SRC_DIR}/drivers/staging/android/uapi/* \
       ${ROOTFS_BASE}/usr/local/src/linux-imx/drivers/staging/android/uapi
    cp -r ${G_LINUX_KERNEL_SRC_DIR}/include \
       ${ROOTFS_BASE}/usr/local/src/linux-imx/

    # copy custom files
    install -m 0755 ${G_VENDOR_PATH}/${MACHINE}/kobs-ng ${ROOTFS_BASE}/usr/bin
    install -m 0755 ${PARAM_OUTPUT_DIR}/fw_printenv-mmc ${ROOTFS_BASE}/usr/bin
    # cp ${PARAM_OUTPUT_DIR}/fw_printenv-nand ${ROOTFS_BASE}/usr/bin
    # ln -sf fw_printenv ${ROOTFS_BASE}/usr/bin/fw_printenv-nand
    # ln -sf fw_printenv ${ROOTFS_BASE}/usr/bin/fw_setenv
    ln -sf fw_printenv-mmc ${ROOTFS_BASE}/usr/bin/fw_printenv
    ln -sf fw_printenv ${ROOTFS_BASE}/usr/bin/fw_setenv
    install -m 0644 ${G_VENDOR_PATH}/${MACHINE}/fw_env.config ${ROOTFS_BASE}/etc

    # BEGIN -- REVO i.MX7D post-packages stage
    # Run curl with system root certificates file.
    mv "${ROOTFS_BASE}/usr/bin/curl"{,.dist}
    install -m 755 "${G_VENDOR_PATH}/resources/curl/curl" \
            "${ROOTFS_BASE}/usr/bin/curl"

    # Install node installation script.
    install -m 0755 ${G_VENDOR_PATH}/resources/nodejs/install-node-lts \
            ${ROOTFS_BASE}/usr/bin
    sed -i -e "s;@NODE_BASE@;${NODE_BASE};" \
        -e "s;@NODE_GROUP@;${NODE_GROUP};" \
        -e "s;@NODE_USER@;${NODE_USER};" \
        ${ROOTFS_BASE}/usr/bin/install-node-lts

    # Configure /etc/default/zramswap
    install -m 0644 "${G_VENDOR_PATH}/${MACHINE}/zramswap" \
            "${ROOTFS_BASE}/etc/default"

    # Enable zramswap service
    ln -s "${ROOTFS_BASE}/lib/systemd/system/zramswap.service" \
       "${ROOTFS_BASE}/etc/systemd/system/multi-user.target.wants/"

    # Mask e2scrub_{all,reap} services.
    ln -s /dev/null "${ROOTFS_BASE}/etc/systemd/system/e2scrub_all.timer"
    ln -s /dev/null "${ROOTFS_BASE}/etc/systemd/system/e2scrub_all.service"
    ln -s /dev/null "${ROOTFS_BASE}/etc/systemd/system/e2scrub_reap.service"

    ## post-packages command
    cat > ${ROOTFS_BASE}/post-packages << EOF
#!/bin/bash

# Install node via nvm
install-node-lts

# Remove non-default locales.
DEBIAN_FRONTEND=noninteractive apt -y install localepurge
sed -i -e 's/^USE_DPKG/#USE_DPKG/' /etc/locale.nopurge
localepurge

# XXX: Why is 'linux-image*' installed???
apt -y purge 'linux-image*' initramfs-tools{,-core} \
    cryptsetup cryptsetup-bin cryptsetup-initramfs cryptsetup-run \
    dmeventd dmraid dracut dracut-core lvm2 \
    thin-provisioning-tools

apt -y autoremove --purge

# apt -y install apparmor-profiles-extra
apt -y install apparmor{,-utils,-profiles}

# Set apparamor profiles to complain mode by default.
for f in $(find /etc/apparmor.d -maxdepth 1 -type f); do
  aa-complain "$f"
done

apt clean

rm -f /post-packages
EOF

    pr_info "rootfs: post-packages stage"
    chmod +x ${ROOTFS_BASE}/post-packages
    chroot "${ROOTFS_BASE}" /post-packages

    # kill latest dbus-daemon instance due to qemu-arm-static
    QEMU_PROC_ID=$(ps axf | grep dbus-daemon | grep qemu-arm-static | awk '{print $1}')
    if test -n "$QEMU_PROC_ID"; then
        kill -9 "$QEMU_PROC_ID"
    fi

    rm "${ROOTFS_BASE}/usr/bin/qemu-arm-static"
    # END -- REVO i.MX7D post-packages stage


    # BEGIN -- REVO i.MX7D cleanup
    remove-charmaps
    remove-locales
    rm -rf "${ROOTFS_BASE}/usr/share/doc/"*
    rm -rf "${ROOTFS_BASE}/var/lib/apt/lists/"*

    # Restore APT source list to default Debian mirror.
    cat >"${ROOTFS_BASE}/etc/apt/sources.list" <<EOF
deb ${DEF_DEBIAN_MIRROR} ${DEB_RELEASE} main contrib non-free
#deb-src ${DEF_DEBIAN_MIRROR} ${DEB_RELEASE} main contrib non-free
deb ${DEF_DEBIAN_MIRROR} ${DEB_RELEASE}-backports main contrib non-free
#deb-src ${DEF_DEBIAN_MIRROR} ${DEB_RELEASE}-backports main contrib non-free
EOF

    # Limit kernel messages to the console.
    sed -i -e '/^#kernel.printk/s/^#*//' "${ROOTFS_BASE}/etc/sysctl.conf"

    # Enable colorized `ls' and alias h='history 50' for `root'.
    sed -i -e '/export LS/s/^# *//' -e '/eval.*dircolors/s/^# *//' \
        -e '/alias ls/s/^# *//' -e '/alias l=/a alias h="history 50"' \
        "${ROOTFS_BASE}/root/.bashrc"

    # Prepare /var/log to be mounted as tmpfs.
    # NB: *~ is excluded from rootfs tarball.
    rm -rf "${ROOTFS_BASE}/var/log"
    install -d -m 755 "${ROOTFS_BASE}/var/log"
    # END -- REVO i.MX7D cleanup

    umount_rootfs
    trap - 0 1 2 15
    trap - RETURN
}

# Must be called after make_debian_x11_rootfs in main script
# function generate ubi rootfs in input dir
# $1 - rootfs ubifs base dir
prepare_x11_ubifs_rootfs ()
{
    local UBIFS_ROOTFS_BASE=$1
    pr_info "Make debian(${DEB_RELEASE}) rootfs for UBIFS start..."

    # Below removals are to free space to fit in a NAND flash
    # Remove foreign man pages and locales
    rm -rf ${UBIFS_ROOTFS_BASE}/usr/share/man/??
    rm -rf ${UBIFS_ROOTFS_BASE}/usr/share/man/??_*
    rm -rf ${UBIFS_ROOTFS_BASE}/var/cache/man/??
    rm -rf ${UBIFS_ROOTFS_BASE}/var/cache/man/??_*
    (cd ${UBIFS_ROOTFS_BASE}/usr/share/locale; ls | grep -v en_[GU] | xargs rm -rf)

    # Remove document files
    rm -rf ${UBIFS_ROOTFS_BASE}/usr/share/doc

    # Remove deb package lists
    rm -rf ${UBIFS_ROOTFS_BASE}/var/lib/apt/lists/deb.*
}

# make bootable image for device
# $1 -- block device
# $2 -- output images dir
make_x11_image ()
{
    local LPARAM_BLOCK_DEVICE=$1
    local LPARAM_OUTPUT_DIR=$2
    local LPARAM_TARBALL=$3

    local P1_MOUNT_DIR=${G_TMP_DIR}/p1
    local P2_MOUNT_DIR=${G_TMP_DIR}/p2

    local BOOTLOAD_RESERVE_SIZE=4
    local SPARE_SIZE=8
    local part=''

    format_device ()
    {
        pr_info "Formating device partitions"
        if ! mkfs.vfat -n BOOT "${LPARAM_BLOCK_DEVICE}${part}1" >/dev/null 2>&1; then
            pr_error "Format did not complete successfully."
            echo "*** Please check media and try again! ***"
            return 1
        elif ! mkfs.ext4 -L rootfs "${LPARAM_BLOCK_DEVICE}${part}2" >/dev/null 2>&1; then
            pr_error "Format did not complete successfully."
            echo "*** Please check media and try again! ***"
            return 1
        fi
    }

    flash_device ()
    {
        pr_info "Flashing \"BOOT\" partition"
        if test ."${LPARAM_TARBALL%%.*}" = .'provisionfs'; then
            if test -f "${LPARAM_OUTPUT_DIR}/${UBOOT_PROVISION_SCRIPT}"; then
                pr_info "${UBOOT_PROVISION_SCRIPT} => ${UBOOT_SCRIPT}"
                install -m 0644 "${LPARAM_OUTPUT_DIR}/${UBOOT_PROVISION_SCRIPT}" \
                        "${P1_MOUNT_DIR}/${UBOOT_SCRIPT}"
            fi
        elif test -f "${LPARAM_OUTPUT_DIR}/boot-${ACCESS_CONTROL,,}.scr"; then
            install -m 0644 "${LPARAM_OUTPUT_DIR}/boot-"*.scr \
                    "$P1_MOUNT_DIR"

            pr_info "boot-${ACCESS_CONTROL,,}.scr => ${UBOOT_SCRIPT}"
            install -m 0644 "${P1_MOUNT_DIR}/boot-${ACCESS_CONTROL,,}.scr" \
                    "${P1_MOUNT_DIR}/${UBOOT_SCRIPT}"
            echo "${ACCESS_CONTROL,,}" >"${P1_MOUNT_DIR}/access-control"
        elif test -f "${LPARAM_OUTPUT_DIR}/${UBOOT_SCRIPT}"; then
            install -m 0644 "${LPARAM_OUTPUT_DIR}/${UBOOT_SCRIPT}" \
                    "$P1_MOUNT_DIR"
        fi
        install -m 0644 "${LPARAM_OUTPUT_DIR}/"*.dtb	"$P1_MOUNT_DIR"
        install -m 0644 "${LPARAM_OUTPUT_DIR}/${BUILD_IMAGE_TYPE}" \
                "$P1_MOUNT_DIR"
        sync

        pr_info "Flashing \"${LPARAM_TARBALL%%.*}\" partition"
        if ! tar -C "$P2_MOUNT_DIR" -zxpf "${LPARAM_OUTPUT_DIR}/${LPARAM_TARBALL}"; then
            pr_error "Flash did not complete successfully."
            echo "*** Please check media and try again! ***"
            return 1
        fi
    }

    copy_debian_images ()
    {
        mkdir -p "${P2_MOUNT_DIR}/${G_IMAGES_DIR}"

        pr_info "Copying Debian images to /${G_IMAGES_DIR}"
        if test -f "${LPARAM_OUTPUT_DIR}/boot-${ACCESS_CONTROL,,}.scr"; then
            install -m 0644 "${LPARAM_OUTPUT_DIR}/boot-"*.scr \
                    "${P2_MOUNT_DIR}/${G_IMAGES_DIR}"

            pr_info "boot-${ACCESS_CONTROL,,}.scr => ${UBOOT_SCRIPT}"
            install -m 0644 "${P2_MOUNT_DIR}/${G_IMAGES_DIR}/boot-${ACCESS_CONTROL,,}.scr" \
                    "${P2_MOUNT_DIR}/${G_IMAGES_DIR}/${UBOOT_SCRIPT}"
            echo "${ACCESS_CONTROL,,}" >"${P2_MOUNT_DIR}/${G_IMAGES_DIR}/access-control"
        elif test -f "${LPARAM_OUTPUT_DIR}/${UBOOT_SCRIPT}"; then
            install -m 0644 "${LPARAM_OUTPUT_DIR}/${UBOOT_SCRIPT}" \
                    "${P2_MOUNT_DIR}/${G_IMAGES_DIR}"
        fi
        install -m 0644 "${LPARAM_OUTPUT_DIR}/${BUILD_IMAGE_TYPE}" \
                "${P2_MOUNT_DIR}/${G_IMAGES_DIR}"
        # if test ."$MACHINE" = .'imx6ul-var-dart' ||
        #        test ."$MACHINE" = .'var-som-mx7' ||
        #        test ."$MACHINE" = .'revo-roadrunner-mx7'; then
        #     install -m 0644 ${LPARAM_OUTPUT_DIR}/rootfs.ubi.img \
        #        ${P2_MOUNT_DIR}/${G_IMAGES_DIR}/
        # fi
        install -m 0644 "${LPARAM_OUTPUT_DIR}/${DEF_ROOTFS_TARBALL_NAME}" \
                "${P2_MOUNT_DIR}/${G_IMAGES_DIR}"
        install -m 0644 "${LPARAM_OUTPUT_DIR}/${DEF_RECOVERYFS_TARBALL_NAME}" \
                "${P2_MOUNT_DIR}/${G_IMAGES_DIR}"
        install -m 0644 "${LPARAM_OUTPUT_DIR}/"*.dtb \
                "${P2_MOUNT_DIR}/${G_IMAGES_DIR}"

        # pr_info "Copying NAND U-Boot to /${G_IMAGES_DIR}"
        # install -m 0644 "${LPARAM_OUTPUT_DIR}/${G_SPL_NAME_FOR_NAND}" \
        #    "${P2_MOUNT_DIR}/${G_IMAGES_DIR}"
        # install -m 0644 "${LPARAM_OUTPUT_DIR}/${G_UBOOT_NAME_FOR_NAND}" \
        #    "${P2_MOUNT_DIR}/${G_IMAGES_DIR}"

        pr_info "Copying MMC U-Boot to /${G_IMAGES_DIR}"
        install -m 0644 "${LPARAM_OUTPUT_DIR}/${G_SPL_NAME_FOR_EMMC}" \
                "${P2_MOUNT_DIR}/${G_IMAGES_DIR}"
        install -m 0644 "${LPARAM_OUTPUT_DIR}/${G_UBOOT_NAME_FOR_EMMC}" \
                "${P2_MOUNT_DIR}/${G_IMAGES_DIR}"

        return 0
    }

    flash_u-boot ()
    {
        pr_info "Flashing U-Boot"
        if ! dd if="${LPARAM_OUTPUT_DIR}/${G_SPL_NAME_FOR_EMMC}" \
             of="$LPARAM_BLOCK_DEVICE" bs=1K seek=1 >/dev/null 2>&1; then
            pr_error "Flash did not complete successfully."
            echo "*** Please check media and try again! ***"
            return 1
        fi
        sync
        if ! dd if="${LPARAM_OUTPUT_DIR}/${G_UBOOT_NAME_FOR_EMMC}" \
             of="$LPARAM_BLOCK_DEVICE" bs=1K seek=69 >/dev/null 2>&1; then
            pr_error "Flash did not complete successfully."
            echo "*** Please check media and try again! ***"
            return 1
        fi
    }

    if test ."$LPARAM_BLOCK_DEVICE" = .'na'; then
        LPARAM_BLOCK_DEVICE=$(sed -e 's/ .*//' <<<$(select_removable_device))
        if test ."$LPARAM_BLOCK_DEVICE" = .''; then
            pr_error "Device not available"
            exit 1
        fi
    fi

    if [[ ."$LPARAM_BLOCK_DEVICE" =~ \./dev/mmcblk ]] ||
       is_loop_device "$LPARAM_BLOCK_DEVICE"; then
        part="p"
    fi

    # Check that we're using a valid device
    if ! is_removable_device "$LPARAM_BLOCK_DEVICE"; then
        LPARAM_BLOCK_DEVICE=$(sed -e 's/ .*//' <<<$(select_removable_device))
        if test ."$LPARAM_BLOCK_DEVICE" = .''; then
            pr_error "Device not available"
            exit 1
        fi
    fi


    # Get total card size in blocks
    local total_size=$(blockdev --getsz "$LPARAM_BLOCK_DEVICE")
    local total_size_bytes=$(( total_size * 512 ))
    local total_size_gib=$(perl -e "printf '%.1f', $total_size_bytes / 1024 ** 3")

    # Convert to MB
    total_size=$(( total_size / 2048 ))
    local rootfs_offset=$(( BOOTLOAD_RESERVE_SIZE + SPARE_SIZE ))
    local rootfs_size=$(( total_size - rootfs_offset ))

    pr_info "Device: ${LPARAM_BLOCK_DEVICE}, ${total_size_gib} GiB"
    echo "============================================="
    read -p "Press Enter to continue"

    pr_info "Creating new partitions"
    pr_info "ROOT SIZE=$rootfs_size MiB, TOTAl SIZE=$total_size MiB"

    local part1_start="${BOOTLOAD_RESERVE_SIZE}MiB"
    local part1_size="${SPARE_SIZE}MiB"
    local part2_start="${rootfs_offset}MiB"

    for (( i=0; i < 10; i++ )); do
        if test -n "$(findmnt -n "${LPARAM_BLOCK_DEVICE}${part}${i}")"; then
            umount "${LPARAM_BLOCK_DEVICE}${part}${i}"
        fi
        if test -b "${LPARAM_BLOCK_DEVICE}${part}${i}"; then
            tune2fs -L '' "${LPARAM_BLOCK_DEVICE}${part}${i}" >/dev/null 2>&1 || true
            wipefs -a "${LPARAM_BLOCK_DEVICE}${part}${i}" >/dev/null 2>&1
        fi
    done
    wipefs -a "$LPARAM_BLOCK_DEVICE" >/dev/null 2>&1

    if ! dd if=/dev/zero of="$LPARAM_BLOCK_DEVICE" bs=1M count="$rootfs_offset" >/dev/null 2>&1; then
        pr_error "Flash did not complete successfully."
        echo "*** Please check media and try again! ***"
        return 1
    fi
    sleep 2
    sync

    flock "$LPARAM_BLOCK_DEVICE" sfdisk --wipe=always "$LPARAM_BLOCK_DEVICE" >/dev/null 2>&1 <<EOF
$part1_start,$part1_size,c
$part2_start,-,L
EOF

    # blockdev --rereadpt "$LPARAM_BLOCK_DEVICE"
    partprobe "$LPARAM_BLOCK_DEVICE"
    sleep 2
    sync

    # Format the partitions
    format_device || return 1
    sleep 2
    sync

    # Mount the partitions
    mkdir -p "$P1_MOUNT_DIR"
    mkdir -p "$P2_MOUNT_DIR"
    sync

    mount -t vfat "${LPARAM_BLOCK_DEVICE}${part}1"  "$P1_MOUNT_DIR" >/dev/null 2>&1 || return 1
    mount -t ext4 "${LPARAM_BLOCK_DEVICE}${part}2"  "$P2_MOUNT_DIR" >/dev/null 2>&1 || return 1
    sleep 2
    sync

    flash_device || return 1
    copy_debian_images

    flash_u-boot || return 1

    pr_info "Sync device..."
    sleep 2
    sync
    umount "$P1_MOUNT_DIR"
    umount "$P2_MOUNT_DIR"

    rm -rf "$P1_MOUNT_DIR"
    rm -rf "$P2_MOUNT_DIR"

    pr_info "Make bootable image completed successfully"
}
