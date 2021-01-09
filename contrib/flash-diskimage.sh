#!/usr/bin/env bash
#
# @(#) flash-diskimage
#
# Copyright © 2020 Revolution Robotics, Inc.
#
declare -r SCRIPT_NAME=${0##*/}

declare -r LOOP_MAJOR=7
declare COMPRESSION_SUFFIX='{bz2,gz,img,lz,lzma,lzo,xz,zip}'
declare ZCAT='gzip -dc'

declare PARAM_DEBUG=0
declare PARAM_OUTPUT_DIR=${HOME}/output
declare PARAM_BLOCK_DEVICE=na
declare PARAM_DISK_IMAGE=na
declare BYTES_WRITTEN=na
declare BYTES_VERIFIED=na

usage ()
{
    cat <<EOF
Usage: $SCRIPT_NAME OPTIONS
Options:
  -h|--help   -- print this help, then exit
  -d|--dev    -- removable block device to flash to (e.g., -d /dev/sde)
  -i|--image diskimage
              -- disk image to flash from (see also option -o)
  -o|--output -- directory of disk image(s) (default: "$PARAM_OUTPUT_DIR")

Example:
  flash image to SD card:           ./${SCRIPT_NAME}
EOF
}

pr-error ()
{
    echo "E: $@"
}

pr-info ()
{
    echo "I: $@"
}

get-range ()
{
    size=$1

    if (( size > 9 )); then
        echo "1-$size"
    else
        echo $(seq $size) | tr ' ' '|'
    fi
}

select-from-list ()
{
    local -n choices=$1
    local prompt=$2

    local choice
    local count=${#choices[*]}

    case "$count" in
        0)
            pr-error "Nothing to choose"
            return 1
            ;;
        1)
            choice=${choices[0]}
            ;;
        *)
            echo "$prompt" >&2
            PS3="Selection [$(get-range $count)]? "
            select choice in "${choices[@]}"; do
                case "$choice" in
                    '')
                        echo "$REPLY: Invalid choice - Please try again:" >&2
                        ;;
                    *)
                        break
                        ;;
                esac
            done
    esac
    echo "$choice"
}

get-disk-images ()
{
    local -a archives
    local archive
    local kind

    mapfile -t archives < <(eval ls "${PARAM_OUTPUT_DIR}/"*.$COMPRESSION_SUFFIX 2>/dev/null)
    for archive in "${archives[@]}"; do
        get-decompressor "$archive"
        case $($ZCAT "$archive" | file -) in
            *DOS/MBR*)
                echo "$archive"
                ;;
        esac
    done
}

get-removable-devices ()
{
    local -a devices
    local device
    local vendor
    local model

    mapfile -t devices < <(
        grep -lv '^0$' '/sys/block/'*'/removable' |
            sed -e 's;removable$;device/uevent;' |
            xargs grep -l '^DRIVER=sd$' |
            sed -e 's;device/uevent;size;' |
            xargs grep -lv '^0' |
            cut -d/ -f4
    )

    for device in "${devices[@]}"; do
        vendor=$(echo $(< "/sys/block/${device}/device/vendor"))
        model=$(echo $(< "/sys/block/${device}/device/model"))
        echo "/dev/$device ($vendor $model)"
    done
}

select-disk-image ()
{
    declare -a disk_images

    mapfile -t disk_images < <(get-disk-images)
    select-from-list disk_images 'Please choose an image to flash from:'
}

select-removable-device ()
{
    declare -a removable_devices

    mapfile -t removable_devices < <(get-removable-devices)
    select-from-list removable_devices 'Please choose a device to flash to:'
}

is-removable-device ()
{
    local device=${1#/dev/}

    local removable
    local drive
    local gdbus_is_removable

    # Check that parameter is a valid block device
    if test ! -b "/dev/$device"; then
        pr-error "/dev/$device: Not a valid block device"
        return 1
    fi

    # Check that /sys/block/$dev exists
    if test ! -d "/sys/block/$device"; then
        pr-error "/sys/block/$device: No such directory"
        return 1
    fi

    # Get device parameters
    removable=$(cat "/sys/block/${device}/removable")

    # Non removable SD card readers require additional check
    if test ."$removable" != .'1'; then
        drive=$(udisksctl info -b "/dev/$device" |
                    awk -F\' '/Drive:/ { print $2 }')
        gdbus_is_removable=$(
            gdbus call --system --dest org.freedesktop.UDisks2 \
                  --object-path "$drive" \
                  --method org.freedesktop.DBus.Properties.Get \
                  org.freedesktop.UDisks2.Drive MediaRemovable 2>/dev/null
                          )
        if [[ ."$gdbus_is_removable" =~ ^\..*true ]]; then
            removable=1
        fi
    fi

    # Device not removable
    if test ."$removable" != .'1'; then
        pr-error "/dev/$device: Not a removable device"
        return 1
    fi
}

select-media ()
{
    local total_size
    local total_size_bytes
    local total_size_gib
    local -i i

    if test ! -f "$PARAM_DISK_IMAGE"; then
        if test -f "${PARAM_OUTPUT_DIR}/${PARAM_DISK_IMAGE}"; then
            PARAM_DISK_IMAGE=${PARAM_OUTPUT_DIR}/${PARAM_DISK_IMAGE}
        else
            PARAM_DISK_IMAGE=$(select-disk-image)
        fi
        if test ! -f "$PARAM_DISK_IMAGE"; then
            pr-error "Image not available"
            exit 1
        fi
    fi

    if ! is-removable-device "$PARAM_BLOCK_DEVICE" >/dev/null 2>&1; then
        PARAM_BLOCK_DEVICE=$(select-removable-device | awk '{ print $1 }')
        if test ! -b "$PARAM_BLOCK_DEVICE"; then
            pr-error "Device not available"
            exit 1
        fi
    fi

    total_size=$(sudo blockdev --getsz "$PARAM_BLOCK_DEVICE")
    total_size_bytes=$(( total_size * 512 ))
    total_size_gib=$(perl -e "printf '%.1f', $total_size_bytes / 1024 ** 3")

    echo '============================================='
    pr-info "Image: ${PARAM_DISK_IMAGE##*/}"
    pr-info "Device: $PARAM_BLOCK_DEVICE, $total_size_gib GiB"
    echo '============================================='
    read -p "Press Enter to continue"
}

get-decompressor ()
{
    local archive=$1

    case $(file "$archive") in
        *bzip2*)
            ZCAT='bzip2 -dc'
            ;;
        *lzip*)
            ZCAT='lzip -dc'
            ;;
        *LZMA*)
            ZCAT='lzma -dc'
            ;;
        *lzop*)
            ZCAT='lzop -dc'
            ;;
        *gzip*)
            ZCAT='gzip -dc'
            ;;
        *XZ*)
            ZCAT='xz -dc'
            ;;
        *Zip*)
            ZCAT='unzip -p'
            ;;
        *'ISO 9660'*|*'DOS/MBR boot sector'*)
            ZCAT=cat
            ;;
    esac
}

flash-diskimage ()
{
    pr-info "Flashing image to device..."

    for (( i=0; i < 10; i++ )); do
        if test -n "$(findmnt -n "${PARAM_BLOCK_DEVICE}${i}")"; then
            sudo umount -f "${PARAM_BLOCK_DEVICE}${i}"
        fi
    done

    errfile=$(mktemp "/tmp/${SCRIPT_NAME}.XXXXX")
    trap 'rm -f "$errfile"; exit' 0 1 2 15 RETURN

    if ! $ZCAT "$PARAM_DISK_IMAGE" |
            sudo dd of="$PARAM_BLOCK_DEVICE" bs=1M 2>"$errfile"; then
        pr-error "Flash did not complete successfully."
        echo "*** Please check media and try again! ***"
    fi


    BYTES_WRITTEN=$(awk '/bytes/ { print $1 }' "$errfile")

    rm -f "$errfile"
    trap - 0 1 2 15 RETURN
}

verify-diskimage ()
{
    pr-info "Verifying device against image..."

    errfile=$(mktemp "/tmp/${SCRIPT_NAME}.XXXXX")
    trap 'rm "$errfile"; exit' 0 1 2 15 RETURN

    $ZCAT "$PARAM_DISK_IMAGE" |
        sudo cmp -n "$BYTES_WRITTEN" "$PARAM_BLOCK_DEVICE" - >"$errfile" 2>&1

    BYTES_VERIFIED=$(sed -nE -e 's/.*differ: byte +([0-9]+).*$/\1/p' "$errfile")
    if test ! -s "$errfile"; then
        pr-info "Compared: $BYTES_WRITTEN bytes"
        pr-info 'Device successfully verified'
    else
        pr-error "Device and image differ at byte: $BYTES_VERIFIED"
    fi

    rm -f "$errfile"
    trap - 0 1 2 15 RETURN
}

## parse input arguments ##
declare -r SHORTOPTS=d:i:o:h
declare -r LONGOPTS=debug,dev:,image:,output:,help

declare ARGS=$(
    getopt -s bash --options "$SHORTOPTS"  \
           --longoptions "$LONGOPTS" --name "$SCRIPT_NAME" -- "$@"
        )

eval set -- "$ARGS"

while true; do
    case "$1" in
        --debug)
            PARAM_DEBUG=1
            ;;
        -d|--dev) # SD card block device
            shift
            if test -e "$1"; then
                PARAM_BLOCK_DEVICE=$1
            fi
            ;;
        -h|--help) # get help
            usage
            exit 0
            ;;
        -i|--image) # Disk image
            shift
            if test -e "$1"; then
                PARAM_DISK_IMAGE=$1
            fi
            ;;
        -o|--output) # select output dir
            shift
            PARAM_OUTPUT_DIR=$1
            ;;
        --)
            shift
            break
            ;;
        *)
            shift
            break
            ;;
    esac
    shift
done

# enable trace option in debug mode
if test ."$PARAM_DEBUG" = .'1'; then
    echo "Debug mode enabled!"
    set -x
fi

select-media
get-decompressor "$PARAM_DISK_IMAGE"
flash-diskimage
verify-diskimage
