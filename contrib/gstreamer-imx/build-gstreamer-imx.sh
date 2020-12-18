#!/usr/bin/env bash
#
# @(#) build-gstreamer-imx.sh
#
# This script builds and installs the gstreamer-imx package in a
# chroot'ed REVO Roadrunner rootfs. To use:
#
#    $ sudo cp build-gstreamer-imx.sh /path/to/rootfs
#    $ contrib/chrootfs.sh /path/to/rootfs /build-gstreamer-imx.sh
#    $ rm -rf /path/to/rootfs/gstreamer-imx
#    $ rm /path/to/rootfs/build-gstreamer.sh
#
# See also <https://github.com/Freescale/gstreamer-imx#building-and-installing>
# and <https://github.com/Freescale/gstreamer-imx/blob/master/docs/debian-ubuntu.md>
#
fetch-and-unpack ()
{
    local url=$1
    local dist=${1##*/}

    curl -C - -LO "$url"
    chmod +x "./${dist}"
    "./${dist}" --auto-accept --force
}

install-gstreamer1.0 ()
{
    # Assume that build-essential, gcc, etc. are already installed...
    apt -y install autoconf automake libtool pkgconf
    apt -y install gstreamer1.0-x gstreamer1.0-tools
    apt -y install libgstreamer1.0-dev

    # Install videoparserbad for video parsers like h264parse,
    # mpegvideoparse and mpeg4videoparse.
    apt -y install gstreamer1.0-plugins-good gstreamer1.0-plugins-bad
    apt -y install libgstreamer-plugins-base1.0-dev
    apt -y install libgstreamer-plugins-bad1.0-dev
    apt -y install libpango1.0-dev

    # Install ALSA plugin.
    apt -y install gstreamer1.0-alsa
}

install-vpu-firmware ()
{
    local vpu_firmware=$1

    fetch-and-unpack "${fslmirror}/${vpu_firmware}.bin"

    echo 'Installing VPU firmware => /lib/firmware/vpu'
    install -d -m 0755 /lib/firmware/vpu
    install -m 0644 "${vpu_firmware}/firmware/vpu/"*imx6*.bin /lib/firmware/vpu
}

install-lib-vpu ()
{
    local imx_vpu=$1

    fetch-and-unpack "${fslmirror}/${imx_vpu}.bin"
    cd "./${imx_vpu}"
    make PLATFORM=IMX6Q all

    echo 'Installing vpu_lib.h, vpu_io.h => /usr/include'
    echo 'Installing libvpu.* => /usr/lib'
    make install
    cd -
}

install-fsl-codec ()
{
    local lib_fslcodec=$1

    fetch-and-unpack "${fslmirror}/${lib_fslcodec}.bin"
    cd "./${lib_fslcodec}"
    ./autogen.sh --prefix=/usr --enable-fhw --enable-vpu
    make all

    echo 'Installing FSL video codec => /usr/lib/imx-mm/video-codec'
    echo 'Installing FSL audeo codec => /usr/lib/imx-mm/audio-codec'
    make install

    echo 'Moving FSL codecs => /usr/lib'
    mv /usr/lib/imx-mm/video-codec/* /usr/lib
    mv /usr/lib/imx-mm/audio-codec/* /usr/lib
    rm -rf /usr/lib/imx-mm/
    cd -
}

install-imx-lib ()
{
    local imx_lib=$1

    curl -C - -LO "${fslmirror}/${imx_lib}.tar.gz"
    tar -zxf "${imx_lib}.tar.gz"
    cd  "./${imx_lib}"

    make PLATFORM="IMX6Q"

    echo 'Installing imx-lib'
    make PLATFORM="IMX6Q" install
    cd -
}

install-imx-gnu-viv ()
{
    local imx_gpu_viv=$1

    fetch-and-unpack "${fslmirror}/${imx_gpu_viv}.bin"
    cd "./${imx_gpu_viv}"
    cp g2d/usr/include/* /usr/include/
    cp -a g2d/usr/lib/* /usr/lib/
    cp -a gpu-core/usr/* /usr
    cp -a gpu-demos/opt /
    cp -a gpu-tools/gmem-info/usr/bin/* /usr/bin/
    cd -
}

install-gstreamer-imx ()
{
    git clone https://github.com/Freescale/gstreamer-imx.git
    cd ./gstreamer-imx
    ./waf configure --prefix=/usr --kernel-headers=/usr/include
    ./waf

    echo 'Installing gstreamer-imx...'
    ./waf install
    cd -
}

debian-package-version ()
{
    local head_commit=$(git rev-list -n 1 HEAD)
    local tag=$(
        git tag |
            sort -V |
            egrep -v 'alpha|beta|delta|gamma' |
            tail -1
          )
    local tag_commit=$(git rev-list -n 1 $tag)
    local version=$tag

    if test ."$head_commit" != ."$tag_commit"; then
        version+=-g${head_commit:0:6}
    fi
    echo "$version"
}

get-build-dependencies ()
{
    :
}

# If running this script, as opposed to sourcing it...
if test ."$0" = ."${BASH_SOURCE[0]}"; then
    declare shell_script=${0##*/}
    declare script_dir=${0%/*}

    declare fslmirror=http://www.nxp.com/lgfiles/NMG/MAD/YOCTO
    declare vpu_firmware=firmware-imx-5.3
    declare imx_vpu=imx-vpu-5.4.32
    declare lib_fslcodec=libfslcodec-4.0.8
    declare imx_lib=imx-lib-5.1
    declare imx_gpu_viv=imx-gpu-viv-5.0.11.p7.4-hfp
    declare xorg_imx_viv=xserver-xorg-video-imx-viv-5.0.11.p7.4.tar.gz

    mkdir -p gstreamer-imx
    cd ./gstreamer-imx
    install-gstreamer1.0

    # i.MX7D has no graphics acceleration hardware
    # install-vpu-firmware "$vpu_firmware"
    # install-lib-vpu "$imx_vpu"
    install-fsl-codec "$lib_fslcodec"
    # install-imx-lib "$imx_lib"
    # install-imx-gnu-viv "$imx_gpu_viv"
    install-gstreamer-imx
    cd "$script_dir"
fi
