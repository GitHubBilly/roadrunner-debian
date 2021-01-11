#!/bin/bash
#
# @(#) mp-build-diskimage
#
# Copyright © 2020 Revolution Robotics, Inc.
#
# This script builds a REVO i.MX7D SD disk image in a multipass VM.
# The resulting image is written to $DEST_DIR on the local host.
#
# NB: Inside the VM, be careful not to overwrite user ubuntu's
#     authorized_keys (i.e., ~ubuntu/.ssh/authorized_keys). Multipass
#     is unable to accesses the VM without it.
#
#     In the event authorized_keys is lost, if SSH access is available
#     (see `multipass list` for IP address), authorized_keys can be
#     restored from the host machine via the command:
#
#         sudo ssh-keygen -y -f \
#              /var/snap/multipass/common/data/multipassd/ssh-keys/id_rsa |
#             ssh ubuntu@${vm_ipv4} 'cat >>.ssh/authorized_keys'
#
#     See the function `mpip' below for a way of defining of `vm_ipv4'.
#
declare script_name=${0##*/}
declare build_suite_commit=$1

# Exit immediately on errors
set -eE -o pipefail
shopt -s extglob

# Edit these ...
: ${VMNAME:='roadrunner'}
: ${NPROC:='2'}
: ${DISK_SIZE:='30G'}
: ${MEMORY_SIZE:='2G'}
: ${SSH_PUBKEY:="${HOME}/.ssh/id_rsa.pub"}
: ${BUILD_SUITE_BRANCH_DEFAULT:='debian_buster_rr01'}
: ${BUILD_DIR:='roadrunner_debian'}
: ${OUTPUT_DIR:="${BUILD_DIR}/output"}
: ${DEST_DIR:="${HOME}/output"}
: ${ACNG_PROXY_URL:="http://${HOSTNAME}:3142/deb.debian.org/debian/"}

# Command paths
: ${APT:='/usr/bin/apt'}
: ${APT_KEY:='/usr/bin/apt-key'}
: ${AWK:='/usr/bin/awk'}
: ${BASH:='/bin/bash'}
: ${CAT:='/bin/cat'}
: ${CURL:='/usr/bin/curl'}
: ${EGREP:='/usr/bin/egrep'}
: ${FLOCK:='/usr/bin/flock'}
: ${GIT:='/usr/bin/git'}
: ${GPG:='/usr/bin/gpg'}
: ${GREP:='/usr/bin/grep'}
: ${HEAD:='/usr/bin/head'}
: ${LN:='/bin/ln'}
: ${LS:='/bin/ls'}
: ${LSOF:='/usr/bin/lsof'}
: ${MKDIR:='/bin/mkdir'}
: ${MKTEMP:='/usr/bin/mktemp'}
: ${PGREP:='/usr/bin/pgrep'}
: ${RM:='/bin/rm'}
: ${SED:='/bin/sed'}
: ${SSH_KEYGEN:='/usr/bin/ssh-keygen'}
: ${SORT:='/usr/bin/sort'}
: ${SUDO:='/usr/bin/sudo'}
: ${TAIL:='/usr/bin/tail'}
: ${TEE:='/usr/bin/tee'}
: ${UNAME:='/usr/bin/uname'}

: ${TTY:="$(tty)"}
: ${LOCKED:=''}

# Script not piped to bash ...
if test -t 0; then

    # And `flock' available ...
    if test -x "$FLOCK" -a ."$0" != ."$LOCKED"; then

        #  Avoid running multiple instances of this script.
        exec env LOCKED=$0 $FLOCK -en "$0" "$0" "$@" || true
    fi
else

    # TTY not exported ...
    if [[ ! ."$TTY" =~ \./dev/ ]]; then
        echo "$script_name: TTY must be exported before running this script:"
        echo "export TTY=\$(tty);"
        exit 1
    fi
fi

# Return latest GIT repository tag of the form vX.Y.Z.
get-current-tag ()
{
    local uri=$1

    # GIT output format:
    # 5fe6c967a5ccea411eb1cf109e6af7ef6cdee311	refs/tags/v1.2.1
    # c80b31f6dbd956562ee723cd45ad593e9171b0e9	refs/tags/v1.2.1^{}
    # 482c2489abbd021c7a23e7c5c44bd01d5c31dd0c	refs/tags/v1.3.0
    # 6be5d9c067ecbd256af506e4d98d7454d9ea68e8	refs/tags/v1.3.0^{}
    # f1d51cd8f8918178292795bbd3235184e7bca09d	refs/tags/v1.3.0-dev
    # 99276d6140b97ef6b3bbcda07f0fb444f20430da	refs/tags/v1.3.0-rc
    #
    # After filtering and sorting:
    #     v1.2.1
    #     v1.3.0
    $GIT ls-remote --tags "$uri" |
        $EGREP -v -- '-|\{\}|/[0-9]'  |
        $SED -e 's;.*refs/tags/;;' |
        $SORT --version-sort -k1.2 |
        $TAIL -1
}

declare acng_proxy=''
declare prompt
declare system=$($UNAME -s)

case "$system" in
    Linux)
        : ${MULTIPASS:='/snap/bin/multipass'}
        : ${NMCLI:='/usr/bin/nmcli'}
        : ${SNAP:='/usr/bin/snap'}

        if test ! -x "$MULTIPASS"; then
            if test -x "$SNAP"; then
                echo "Installing multipass ..."
                $SUDO $SNAP install multipass --classic
            else
                echo "$script_name: multipass: Command not available" >&2
                exit 1
            fi
        fi
        ;;
    Darwin)

        : ${MULTIPASS:='/Library/Application Support/com.canonical.multipass/bin/multipass'}
        : ${OPEN:='/usr/bin/open'}
        : ${SCUTIL:='/usr/sbin/scutil'}

        if test ! -x "$MULTIPASS"; then

            declare uri='https://github.com/canonical/multipass'
            declare tag=$(get-current-tag "$uri")
            declare release="releases/download/${tag}/multipass-${tag#v}+mac-Darwin.pkg"
            declare tmpdir=$($MKTEMP -d "/tmp/${script_name}.XXXXX")

            trap 'rm -rf "$tmpdir"; exit' 0 1 2 15

            echo "Initiating Multipass install ..."
            cd "$tmpdir"

            $CURL -sS -C - -LO "${uri}/${release}"
            $OPEN "${release##*/}"

            prompt="After completing install, please return here, and then press any key to
continue or CTRL + C to cancel ..."

            read -p "$prompt" -n 1 <$TTY
            cd "$OLDPWD"
            $RM -r "$tmpdir"

            trap - 0 1 2 15

            if test ! -x "$MULTIPASS"; then
                echo "$script_name: multipass: Command not available" >&2
                exit 1
            fi

            # Add `multipass' to command-line PATH.
            $SUDO $LN -sf "$MULTIPASS" /usr/bin
        fi
        ;;
    *)
        echo "$script_name: $system: Unsupported system" >&2
        exit 1
        ;;
esac

# If both `pgrep' and `lsof' are available ...
if test -x "$PGREP" -a -x "$LSOF"; then

    # If `apt-cacher-ng' is listening on localhost:3142
    if  $PGREP apt-cacher-ng >/dev/null && $SUDO $LSOF -ti :3142 >/dev/null; then
        acng_proxy="-p $ACNG_PROXY_URL"
    fi
fi

: ${DEBIAN_PROXY:="$acng_proxy"}

# If a $VMNAME instance exists ...
if "$MULTIPASS" list  | $AWK 'NR > 1 { print $1 }' | $GREP -q "$VMNAME"; then

    # Prompt whether to overwrite.
    prompt="$VMNAME: Virtual machine instance already exists. Overwrite [y/N]? "
    if read -t 10 -n 1 -p "$prompt" <"$TTY" || [[ ! ."$REPLY" =~ \.[yY] ]]; then
        "$MULTIPASS" umount "$VMNAME"
        "$MULTIPASS" stop "$VMNAME"
        "$MULTIPASS" delete --purge "$VMNAME"
        "$MULTIPASS" launch --cpus "$NPROC" --disk "$DISK_SIZE" \
                     --mem "$MEMORY_SIZE" --name "$VMNAME" focal
    fi

# Launch VM and mount local $DEST_DIR on VM's $OUTPUT_DIR via SSHFS.
else
    "$MULTIPASS" launch --cpus "$NPROC" --disk "$DISK_SIZE" \
                 --mem "$MEMORY_SIZE" --name "$VMNAME" focal
fi

# Multipass evidently consumes/flushes stdin here, so redirect $TTY as
# a work-around when piping this script to bash.
$MKDIR -p "$DEST_DIR" &&
    "$MULTIPASS" exec "$VMNAME" -- $MKDIR -p "$OUTPUT_DIR" <"$TTY" &&
    {
        "$MULTIPASS" mount "$DEST_DIR" "${VMNAME}:${OUTPUT_DIR}" <"$TTY" ||
            true
    }

# Enable SSH access, e.g.:
#
#   mpip() {
#       vmname=${1:-'roadrunner'}
#       "$MULTIPASS" list | awk 'NR > 1 && $1 == "'$vmname'" { print $3 }'
#   }
#
#   ssh ubuntu@$(mpip $VMNAME)
#
if test ! -f "$SSH_PUBKEY"; then
    echo "Generating SSH certificate"
    $SSH_KEYGEN -t rsa -b 4096 -C "${USER}@${HOSTNAME}" -P '' \
        -f "${SSH_PUBKEY%.pub}"
fi

if test -f "$SSH_PUBKEY"; then
    $CAT "$SSH_PUBKEY" |
        "$MULTIPASS" exec "$VMNAME" -- $BASH -c "$CAT >>.ssh/authorized_keys"
fi

# Add host to guest's /etc/hosts
case "$system" in
    Linux)
        declare host_gw_if=$(
            $NMCLI |
                $AWK -F':' '/^[^[:blank:]/]+:/ { iface=$1 }
                   /ip4 default/ { exit }
                   END { print iface }'
                  )
        declare host_gw_ipv4=$($NMCLI --get-values 'ip4.address' device show "$host_gw_if")
        ;;
    Darwin)
        declare host_gw_ipv4=$(
            $SCUTIL --nwi |
                $AWK '/address/ { print $3 }' |
                $HEAD -1
                  )
        ;;
esac
$CAT <<EOF | "$MULTIPASS" exec "$VMNAME" -- $SUDO $BASH -c "$CAT >>/etc/hosts"
# localhosts
${host_gw_ipv4%/*} $HOSTNAME
EOF

# If apt-cacher-ng proxy available, add it to the VM's apt configuration.
if [[ ."$DEBIAN_PROXY" =~ \..*3142 ]]; then
    $CAT <<EOF | "$MULTIPASS" exec "$VMNAME" -- $SUDO $BASH -c "$CAT >>/etc/apt/apt.conf.d/10acng-proxy"
Acquire::http::Proxy "http://${HOSTNAME}:3142";
EOF
fi

# Install build script.
$CAT <<EOF | "$MULTIPASS" exec "${VMNAME}" -- $BASH -c "$CAT >build_script"
#!/bin/bash
#
set -e
cd "./$BUILD_DIR"
echo "Installing toolchains and libraries..."
$SUDO $APT update |& $TEE "/home/ubuntu/${OUTPUT_DIR}/apt.log"
$SUDO $APT install -qy --no-install-recommends autoconf automake autopoint \\
    binfmt-support binutils bison build-essential chrpath cmake \\
    coreutils debootstrap device-tree-compiler diffstat docbook-utils \\
    flex g++ gcc gcc-multilib git-core golang gpart groff help2man \\
    lib32ncurses5-dev libarchive-dev libelf-dev libgl1-mesa-dev \\
    libglib2.0-dev libglu1-mesa-dev libsdl1.2-dev libssl-dev libtool lzop \\
    m4 make python3-git python3-m2crypto qemu qemu-user-static socat \\
    texi2html texinfo u-boot-tools unzip |& $TEE -a "/home/ubuntu/${OUTPUT_DIR}/apt.log"
$SUDO $APT install -qy binutils-arm-linux-gnueabihf |& $TEE -a "/home/ubuntu/${OUTPUT_DIR}/apt.log"
$SUDO $APT install -qy cpp-arm-linux-gnueabihf |& $TEE -a "/home/ubuntu/${OUTPUT_DIR}/apt.log"
$SUDO $APT install -qy gcc-arm-linux-gnueabihf |& $TEE -a "/home/ubuntu/${OUTPUT_DIR}/apt.log"
$SUDO $APT install -qy g++-arm-linux-gnueabihf |& $TEE -a "/home/ubuntu/${OUTPUT_DIR}/apt.log"
$CURL -sL https://ftp-master.debian.org/keys/release-10.asc | $SUDO $APT_KEY add
echo "Cloning build suite..."
$GIT init |& $TEE "/home/ubuntu/${OUTPUT_DIR}/git.log"
$GIT remote add origin https://github.com/revolution-robotics/roadrunner-debian.git |& $TEE -a "/home/ubuntu/${OUTPUT_DIR}/git.log"
$GIT fetch |& $TEE -a "/home/ubuntu/${OUTPUT_DIR}/git.log"
if test ."$build_suite_commit" != .''; then
    $GIT checkout -b "commit-${build_suite_commit:0:6}" "$build_suite_commit" |& $TEE -a "/home/ubuntu/${OUTPUT_DIR}/git.log"
else
    $GIT checkout "$BUILD_SUITE_BRANCH_DEFAULT" |& $TEE -a "/home/ubuntu/${OUTPUT_DIR}/git.log"
fi
echo "Deploying sources..."
MACHINE=revo-roadrunner-mx7 ./revo_make_debian.sh -c deploy |& $TEE "/home/ubuntu/${OUTPUT_DIR}/deploy.log"
echo "Building all..."
$SUDO MACHINE=revo-roadrunner-mx7 ./revo_make_debian.sh -j "$NPROC" $DEBIAN_PROXY -c all |& $TEE "/home/ubuntu/${OUTPUT_DIR}/all.log"
echo "Creating disk image..."
echo | $SUDO MACHINE=revo-roadrunner-mx7 ./revo_make_debian.sh -c diskimage |& $TEE "/home/ubuntu/${OUTPUT_DIR}/diskimage.log"
echo | $SUDO MACHINE=revo-roadrunner-mx7 ./revo_make_debian.sh -c usbimage |& $TEE "/home/ubuntu/${OUTPUT_DIR}/usbimage.log"
echo | $SUDO MACHINE=revo-roadrunner-mx7 ./revo_make_debian.sh -c provisionimage |& $TEE "/home/ubuntu/${OUTPUT_DIR}/provisionimage.log"
uptime >"/home/ubuntu/${OUTPUT_DIR}/runtime.log"
EOF

# Run build script.
"$MULTIPASS" exec "$VMNAME" -- $BASH -c 'chmod +x build_script; ./build_script'
echo "Build complete!"
echo "$LS -l $DEST_DIR"
$LS -l "$DEST_DIR"
