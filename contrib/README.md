# Contrib scripts
The following scripts are intended to simplify routine tasks and
described in following sections:

- [chrootfs.sh](#chrootfssh)
- [firewalld](#firewalld)
- [flash-diskimage.sh](#flash-diskimagesh)
- [gstreamer-imx](#gstreamer-imx)
- [markov-pwgen](#markov-pwgen)
- [memalloc](#memalloc)
- [mp-build-diskimage.sh](#mp-build-diskimagesh)
- [mp-cloud-init.yaml](#mp-cloud-inityaml)

## chrootfs.sh

After populating _rootfs_
via [debootstrap](https://wiki.debian.org/Debootstrap), it's sometimes
desirable to leverage it inside an Arm virtual machine. For instance,
the public key infrastructure provided by
[Smallstep](https://smallstep.com/) is not distributed in binary
format for 32-bit systems. Furthermore, the Golang build environment
consumes more disk space than is available on the Roadrunner platform.
So to build and package the Smallstep PKI for Roadrunner, an Arm VM
comes in handy.

The script
[chrootfs.sh](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/contrib/chrootfs.sh)
is intended from the run the top-level *roadrunner_debian* build
directory
(see
[Debian GNU/Linux build suite for REVO boards](https://github.com/revolution-robotics/roadrunner-debian)).

It mounts _/dev_, _/proc_ and _/sys_ to the corresponding directories
under _./rootfs_ and then `chroot`s there, invoking Bash (a 32-bit Arm
binary) via [QEMU](https://www.qemu.org/). Once inside the Arm VM,
32-bit Arm binaries can be built natively - no cross-compilation
necessary.

## firewalld
The `firewalld` package provides Red Hat's firewall.
The script `build-firewalld-deb.sh` builds a Debian
package for firewalld from upstream sources. It is intended to be
run while chroot'ed to a REVO Roadrunner _rootfs_.

## flash-diskimage.sh
The script
[flash-diskimage.sh](https://github.com/revolution-robotics/roadrunner-debian/tree/debian_buster_rr01/contrib#flash-diskimagesh)
writes disk images to removable media and verifies the media against
the original image. It does essentially the same job
as [balenaEtcher](https://www.balena.io/etcher/), just faster, more
conveniently and with greater flexibility. To run it, open the
Terminal and run:

```
./flash-diskimage.sh
```

By default, it looks for image files to flash in the directory _${HOME}/output_.

The script leverages features of GNU Bash version 5, so no attempt has
been made to port it, e.g., to MacOS.

## gstreamer-imx
The `gstreamer-imx` package provides GStreamer plugins for i.MX
platform. The script `build-gstreamer-imx-deb.sh` builds a Debian
package for gstreamer-imx from upstream sources. It is intended to be
run while chroot'ed to a REVO Roadrunner _rootfs_.

## markov-pwgen
`markov-pwgen` is a JavaScript command-line utility that leverages
the [Foswig.js](https://github.com/mrsharpoblunto/foswig.js/) library
to generate memorable passwords.

## memalloc
`memalloc` is a C program that allocates memory in units of 25 MB per
second up to 925 MB to test zramswap. Without zramswap enabled (and
using 25% of available RAM), at most 725 MB can be allocated.

## mp-build-diskimage.sh
The Roadrunner disk images can be built on either Linux or MacOS
(10.12 or later) with a single command pipeline. The script installs
Canonical's cross-platform VM
manager, [multipass](https://multipass.run/), as necessary. The build
is done inside a Ubuntu virtual machine and the build products appear
by default in the host machine directory _${HOME}/output_. This
and other defaults can be updated by editing the top-level variables
of the build script [mp-build-diskimage.sh](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/contrib/mp-build-diskimage.sh). To
initiate a build on either Linux or MacOS, open the Terminal and run:

```
export TTY=$(tty); curl -L https://raw.githubusercontent.com/revolution-robotics/roadrunner-debian/debian_buster_rr01/contrib/mp-build-diskimage.sh | bash -s
```

To uninstall `multipass`:
- On MacOS, delete _/Applications/multipass.app_,
  _/Library/Application Support/com.canonical.multipass_ and
  _/usr/bin/multipass_. Then run:

```
sudo kill $(pgrep -f multipassd)
sudo pkgutil --forget com.canonical.multipass.multipass
sudo pkgutil --forget com.canonical.multipass.multipass_gui
sudo pkgutil --forget com.canonical.multipass.multipassd
```

- On Linux, run: `snap remove --purge multipass`.

## mp-cloud-init.yaml
The [multipass](https://multipass.run/) command
accepts [cloud-init](https://cloud-init.io/) configuration files, and
[mp-cloud-init.yaml](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/contrib/mp-cloud-inityaml),
like [mp-build-diskimage.sh](#mp-build-diskimagesh),
builds the Roadrunner disk images. If `multipass` is already
installed, it can be invoked with _mp-cloud-init.yaml_ in the Terminal, e.g., as:

```
multipass launch --cpus 2 --disk 15G --mem 2G --name roadrunner --cloud-init - focal <cloud-init.yaml
```
