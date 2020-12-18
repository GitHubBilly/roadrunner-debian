#!/usr/bin/env bash
#
# This script chroots to a given Debian rootfs and runs a command.
#
declare ROOTFS_BASE=${1:-'rootfs'}
declare CMD=${2:-'/bin/bash'}

: ${CHROOT:='/usr/sbin/chroot'}
: ${FINDMNT:='/bin/findmnt'}
: ${MKDIR:='/bin/mkdir'}
: ${MOUNT:='/bin/mount'}
: ${UMOUNT:='/bin/umount'}
: ${SUDO:='/usr/bin/sudo'}

umount-rootfs ()
{
    $SUDO $UMOUNT -f "${ROOTFS_BASE}/"{sys,proc,dev/pts,dev} 2>/dev/null || true
    $SUDO $UMOUNT -f "${ROOTFS_BASE}/dev" 2>/dev/null || true
}

trap 'umount-rootfs; exit' 0 1 2 15

$SUDO $MKDIR -p ${ROOTFS_BASE}/{proc,dev/pts,sys}

if ! $FINDMNT ${ROOTFS_BASE}/proc >/dev/null; then
    $SUDO $MOUNT -t proc /proc ${ROOTFS_BASE}/proc
fi

for fs in /sys /dev /dev/pts; do
    if ! $FINDMNT "${ROOTFS_BASE}/${fs}" >/dev/null; then
        $SUDO $MOUNT -o bind "$fs" "${ROOTFS_BASE}${fs}"
    fi
done

$SUDO $CHROOT "$ROOTFS_BASE" "$CMD"
