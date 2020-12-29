#!/usr/bin/env bash
#
# @(#) build-firewalld-deb.sh
#
# To build firewalld.deb, run this script while chrooted in
# rootfs.
#
# The commented-out patch at the end of this script is used to
# populate the Debian subdirectory, which is subsequently read by the
# command `dpkg-buildpackage'.
#
# The Debian subdirectory itself is adapted from the firewalld-0.8.2
# Debian source package.
#
get-latest-tag ()
{
    local git_repo=$1
    local max_version=$2

    git ls-remote --tags "$git_repo" |
        awk -F/ '{ print $NF }' |
        egrep -v 'alpha|beta|gamma|delta' |
        sed -n -e "/$max_version/p" |
        sort -V |
        tail -1
}

fetch-and-extract-archive ()
{
    local github_url=$1
    local package=$2
    local max_version=$3

    local tag=$(get-latest-tag "${github_url}/${package}" "$max_version")

    curl -C - -LO "${github_url}/${package}/releases/download/${tag}/${package}-${tag#v}.tar.gz"
    tar -zxf "${package}-${tag#v}.tar.gz"
    echo "${tag#v}"
}

prepare-debian-infrastructure ()
{
    local package=$1
    local version=$2

    local debian_archive=${package}-${version}
    local original_archive=${package}_${version}.orig

    ln -s "${debian_archive}.tar.gz" "${original_archive}.tar.gz"

    # Extract and apply patch at the end of this script to create
    # Debian subdirectory.
    sed -n '/BEGIN debian patch/,$s/^#//p' "${script_dir}/${script_name}" | patch -p0 -d "$debian_archive"

    # Update first version number in `src/debian/changelog'.
    sed -i -e "0,/^${package}/{s;^\(${package} \)(.*);\1(${version}-1);}" "${debian_archive}/debian/changelog"

    chmod +x "${debian_archive}/debian/rules"
}

install-build-dependencies ()
{
    apt update
    apt -y install build-essential fakeroot devscripts pkgconf

    apt -y install autoconf docbook docbook-xsl gettext intltool \
        ipset libglib2.0-dev{,-bin} libxml2-utils xsltproc

    apt -y install gir1.2-nm-1.0 python3-all python3-dbus python3-slip-dbus \
        python3-decorator python3-gi python3-firewall python3-nftables
}

if test ."$0" = ."${BASH_SOURCE[0]}"; then
    declare script_name=${0##*/}
    declare script_dir=$(readlink -e "${0%/*}")

    declare github_url=https://github.com/firewalld
    declare package=firewalld
    declare max_version=0.8

    mkdir "./${package##*/}"
    cd "./${package##*/}"

    declare version=$(fetch-and-extract-archive "$github_url" "$package" "$max_version")

    prepare-debian-infrastructure "$package" "$version"
    install-build-dependencies
    cd "${package}-${version}"
    dpkg-buildpackage -uc -us
    cd "$script_dir"
fi

## **** BEGIN debian patch ****
#diff -Nru debian~/changelog debian/changelog
#--- debian~/changelog	1969-12-31 19:00:00.000000000 -0500
#+++ debian/changelog	2020-12-29 02:08:49.530680627 -0500
#@@ -0,0 +1,502 @@
#+firewalld (0.8.4-1) unstable; urgency=medium
#+
#+  * New upstream version 0.8.4
#+  * Don't switch firewall backend from nftables
#+
#+ -- Andrew L. Moore <andy@revolution-robotics.com>  Mon, 28 Dec 2020 23:11:45 -0500
#+
#+firewalld (0.8.2-1~bpo10+1) buster-backports; urgency=medium
#+
#+  * Rebuild for buster-backports
#+
#+ -- Michael Biebl <biebl@debian.org>  Wed, 24 Jun 2020 10:53:06 +0200
#+
#+firewalld (0.8.2-1) unstable; urgency=medium
#+
#+  * New upstream version 0.8.2
#+  * Rebase patches
#+  * Bump Standards-Version to 4.5.0
#+  * Install logrotate config file for firewalld
#+
#+ -- Michael Biebl <biebl@debian.org>  Sat, 04 Apr 2020 07:50:39 +0200
#+
#+firewalld (0.8.1-1~bpo10+1) buster-backports; urgency=medium
#+
#+  * Rebuild for buster-backports (Closes: #940646)
#+
#+ -- Michael Biebl <biebl@debian.org>  Sun, 12 Jan 2020 17:10:20 +0100
#+
#+firewalld (0.8.1-1) unstable; urgency=medium
#+
#+  * New upstream version 0.8.1
#+  * Rebase patches
#+
#+ -- Michael Biebl <biebl@debian.org>  Sun, 12 Jan 2020 00:20:30 +0100
#+
#+firewalld (0.8.0-2) unstable; urgency=medium
#+
#+  * Split Python3 bindings into a separate package python3-firewall
#+    (Closes: #939094)
#+
#+ -- Michael Biebl <biebl@debian.org>  Wed, 18 Dec 2019 17:55:02 +0100
#+
#+firewalld (0.8.0-1) unstable; urgency=medium
#+
#+  * New upstream version 0.8.0
#+    - Make failures to load kernel modules non-fatal. (Closes: #945459)
#+  * Use DEP-14 branch naming
#+  * Drop obsolete Breaks/Replaces
#+  * Bump Standards-Version to 4.4.1
#+  * Drop obsolete configure flags
#+  * Add dependency on python3-nftables.
#+    The nftables backend is now using the JSON interface of libnftables
#+    instead of calling the nft binary.
#+
#+ -- Michael Biebl <biebl@debian.org>  Wed, 18 Dec 2019 17:43:19 +0100
#+
#+firewalld (0.7.2-1) unstable; urgency=medium
#+
#+  * New upstream version 0.7.2
#+  * Add intltools to root-unittests autopkgtest dependencies.
#+    In some environments "automake --refresh" is triggered before tests are
#+    executed and fails if intltool is missing. (Closes: #936047)
#+
#+ -- Michael Biebl <biebl@debian.org>  Thu, 10 Oct 2019 13:06:21 +0200
#+
#+firewalld (0.7.1-1) unstable; urgency=medium
#+
#+  * New upstream version 0.7.1
#+
#+ -- Michael Biebl <biebl@debian.org>  Tue, 23 Jul 2019 00:18:50 +0200
#+
#+firewalld (0.7.0-1) unstable; urgency=medium
#+
#+  * New upstream version 0.7.0
#+  * Use debhelper-compat (= 12) Build-Depends and drop debian/compat
#+  * Rebase patches
#+  * Install zsh completion file
#+  * Add Build-Depends on libxml2-utils.
#+    Required for /usr/bin/xmlcatalog.
#+  * Bump Standards-Version to 4.4.0
#+
#+ -- Michael Biebl <biebl@debian.org>  Wed, 10 Jul 2019 21:43:28 +0200
#+
#+firewalld (0.6.3-5) unstable; urgency=medium
#+
#+  * Team upload.
#+  * Drop Recommends against ebtables and bump iptables version to 1.8.1-1 to
#+    be certain the ebtables executables are present (Closes: #918470)
#+  * Cherry-pick "ipXtables/nftables: Fix "object has no attribute
#+    '_log_denied'"" (Closes: #916791)
#+  * debian/control: Bump build-dependency against debhelper to 12, compat
#+    version was already set to 12
#+  * debian/rules: Use the iptables binaries that are now installed in
#+    /usr/sbin and avoid the compatibility symlinks installed in /sbin
#+  * debian/control: Bump Standards-Version to 4.3.0 (no further changes)
#+
#+ -- Laurent Bigonville <bigon@debian.org>  Fri, 01 Feb 2019 13:41:47 +0100
#+
#+firewalld (0.6.3-4) unstable; urgency=medium
#+
#+  * Move D-Bus policy file to /usr/share/dbus-1/system.d/
#+  * Remove obsolete conffile /etc/dbus-1/system.d/FirewallD.conf on upgrades
#+
#+ -- Michael Biebl <biebl@debian.org>  Tue, 27 Nov 2018 15:10:52 +0100
#+
#+firewalld (0.6.3-3) unstable; urgency=medium
#+
#+  * Specify canonical paths for modinfo, modprobe, rmmod and sysctl during
#+    configure.
#+    This ensures that if the package is built in a merged-/usr environment it
#+    continues to work on non-merged-/usr systems. (Closes: #913729)
#+
#+ -- Michael Biebl <biebl@debian.org>  Wed, 14 Nov 2018 16:57:55 +0100
#+
#+firewalld (0.6.3-2) unstable; urgency=medium
#+
#+  * Switch firewall backend from nftables back to iptables (again)
#+    When both firewalld and libvirt are installed, libvirt guests using NAT do
#+    not have internet access. The problem is that libvirt is not compatible
#+    (yet) with firewalld's new nftables backend. (Closes: #909574)
#+  * Switch to compat level 12 and dh_installsystemd
#+
#+ -- Michael Biebl <biebl@debian.org>  Tue, 13 Nov 2018 20:20:40 +0100
#+
#+firewalld (0.6.3-1) unstable; urgency=medium
#+
#+  * New upstream version 0.6.3
#+  * Bump Standards-Version to 4.2.1
#+  * Rebase patches
#+
#+ -- Michael Biebl <biebl@debian.org>  Sun, 14 Oct 2018 22:32:32 +0200
#+
#+firewalld (0.6.2-1) unstable; urgency=medium
#+
#+  * New upstream version 0.6.2
#+  * Rebase patches
#+  * Revert "Switch firewall backend from nftables back to iptables"
#+    Follow upstream and use nftables as default backend. This requires a
#+    kernel >= 4.18 to work properly.
#+    This also requires the corresponding userspace utility nft, so add
#+    Depends on the nftables package.
#+    If for some reason you need to revert to the old iptables backend, you
#+    can easily do so by setting FirewallBackend in
#+    /etc/firewalld/firewalld.conf to iptables, then restart firewalld.
#+  * tests/functions: fix macro to dump ipset
#+  * Run upstream unit tests using autopkgtest.
#+  * Test successful start of firewalld via autopkgtests.
#+    Add two basic autopkgtests which simply check if the firewalld daemon
#+    starts without errors (and warnings) if all Depends (and Recommends) are
#+    installed.
#+
#+ -- Michael Biebl <biebl@debian.org>  Thu, 20 Sep 2018 11:35:33 +0200
#+
#+firewalld (0.6.1-2) unstable; urgency=medium
#+
#+  * firewall/core/fw_nm: nm_get_zone_of_connection should return None or empty
#+    string instead of False
#+
#+ -- Michael Biebl <biebl@debian.org>  Thu, 23 Aug 2018 17:26:58 +0200
#+
#+firewalld (0.6.1-1) unstable; urgency=medium
#+
#+  * New upstream version 0.6.1 (Closes: #904244)
#+  * Rebase patches
#+  * Drop ancient X-Python3-Version
#+  * Stop installing firewallctl.
#+    This tool has been deprecated since 0.5.0 and removed completely in 0.6.0.
#+  * Take over cockpit.xml service definition file from cockpit-ws.
#+    Add Breaks/Replaces accordingly.
#+  * Don't run test-suite during build.
#+    It requires root privileges to run successfully so we will eventually
#+    use autopkgtest instead.
#+  * Drop our workaround to move AppData files to /usr/share/metainfo/.
#+    This has been fixed upstream.
#+  * Specificy path to nft (nftables) executable via configure switch
#+  * Switch firewall backend from nftables back to iptables.
#+    The nftables backend requires Linux >= 4.18 which is not yet available
#+    in the Debian archive. Once the new kernel is more widely used, the
#+    backend will be switched back to nftables as default.
#+  * Bump Standards-Version to 4.2.0
#+
#+ -- Michael Biebl <biebl@debian.org>  Wed, 22 Aug 2018 22:08:51 +0200
#+
#+firewalld (0.4.4.6-2) unstable; urgency=medium
#+
#+  * Team upload
#+  * Use preferred https URL for d/copyright Format
#+  * Update Vcs-* for move to salsa.debian.org
#+  * Move AppStream metadata from /usr/share/appdata to /usr/share/metainfo
#+  * Bump Standards-Version to 4.1.4 (no further changes required)
#+
#+ -- Simon McVittie <smcv@debian.org>  Mon, 30 Apr 2018 00:04:26 +0100
#+
#+firewalld (0.4.4.6-1) unstable; urgency=medium
#+
#+  [ Laurent Bigonville ]
#+  * Handle /usr/share/polkit-1/actions/org.fedoraproject.FirewallD1.policy
#+    symlink using alternatives (Closes: #802283)
#+
#+  [ Michael Biebl ]
#+  * New upstream version 0.4.4.6
#+  * Use upstream provided autogen.sh for dh_autoreconf
#+  * Bump Standards-Version to 4.1.1
#+  * Switch to dh_missing to list uninstalled files
#+
#+ -- Michael Biebl <biebl@debian.org>  Wed, 15 Nov 2017 16:12:22 +0100
#+
#+firewalld (0.4.4.5-2) unstable; urgency=medium
#+
#+  * Upload to unstable
#+
#+ -- Michael Biebl <biebl@debian.org>  Sun, 18 Jun 2017 16:27:36 +0200
#+
#+firewalld (0.4.4.5-1) experimental; urgency=medium
#+
#+  * New upstream version 0.4.4.5
#+
#+ -- Michael Biebl <biebl@debian.org>  Fri, 16 Jun 2017 22:23:19 +0200
#+
#+firewalld (0.4.4.4-1) experimental; urgency=medium
#+
#+  * New upstream version 0.4.4.4
#+  * Update watch file for new location at github.
#+    fedorahosted.org has been shut down.
#+  * Override dh_autoreconf so we can run intltoolize
#+  * Switch to gir1.2-nm-1.0.
#+    The introspection data for libnm has been split out of
#+    gir1.2-networkmanager-1.0 into gir1.2-nm-1.0.
#+
#+ -- Michael Biebl <biebl@debian.org>  Fri, 12 May 2017 14:19:06 +0200
#+
#+firewalld (0.4.4.3-1) unstable; urgency=medium
#+
#+  * New upstream release.
#+  * Update Vcs-* URLs following the latest recommendation
#+
#+ -- Michael Biebl <biebl@debian.org>  Sun, 12 Feb 2017 05:20:32 +0100
#+
#+firewalld (0.4.4.2-1) unstable; urgency=medium
#+
#+  * New upstream release.
#+  * Drop patches which have been merged upstream.
#+
#+ -- Michael Biebl <biebl@debian.org>  Thu, 01 Dec 2016 22:58:52 +0100
#+
#+firewalld (0.4.4.1-2) unstable; urgency=medium
#+
#+  * Do not hard-code paths for modinfo, modprobe and rmmod.
#+    Use autofoo to detect them. Patches cherry-picked from upstream Git.
#+    Add Build-Depends on kmod accordingly. (Closes: #844270)
#+
#+ -- Michael Biebl <biebl@debian.org>  Thu, 24 Nov 2016 18:08:46 +0100
#+
#+firewalld (0.4.4.1-1) unstable; urgency=medium
#+
#+  * New upstream release.
#+
#+ -- Michael Biebl <biebl@debian.org>  Thu, 10 Nov 2016 14:59:09 +0100
#+
#+firewalld (0.4.4-2) unstable; urgency=medium
#+
#+  * Update Homepage URL, use http://www.firewalld.org/. (Closes: #843236)
#+  * Fix dependencies of firewall-applet. Change Depends on
#+    python3-dbus.mainloop.qt to python3-dbus.mainloop.pyqt5. (Closes: #843564)
#+
#+ -- Michael Biebl <biebl@debian.org>  Tue, 08 Nov 2016 23:43:25 +0100
#+
#+firewalld (0.4.4-1) unstable; urgency=medium
#+
#+  * New upstream release.
#+  * Switch from PyQt4 to PyQt5.
#+  * Bump debhelper compat level to 10.
#+
#+ -- Michael Biebl <biebl@debian.org>  Thu, 03 Nov 2016 20:14:25 +0100
#+
#+firewalld (0.4.3.3-1) unstable; urgency=medium
#+
#+  * New upstream release.
#+    - Fixes CVE-2016-5410: Firewall configuration can be modified by any
#+      logged in user. (Closes: #834529)
#+
#+ -- Michael Biebl <biebl@debian.org>  Sat, 27 Aug 2016 16:00:36 +0200
#+
#+firewalld (0.4.3.2-1) unstable; urgency=medium
#+
#+  * New upstream release.
#+
#+ -- Michael Biebl <biebl@debian.org>  Tue, 05 Jul 2016 22:44:13 +0200
#+
#+firewalld (0.4.3.1-1) unstable; urgency=medium
#+
#+  * New upstream release.
#+  * Drop 00git-doc-man1-Install-the-firewallctl-manpage.patch, merged
#+    upstream.
#+
#+ -- Michael Biebl <biebl@debian.org>  Tue, 28 Jun 2016 23:21:22 +0200
#+
#+firewalld (0.4.3-1) unstable; urgency=medium
#+
#+  * New upstream release.
#+  * Drop 00git-firewall-core-fw_ifcfg-Quickly-return-if-ifcfg-direc.patch,
#+    merged upstream.
#+  * Install new firewallctl utility.
#+  * Make sure the new firewallctl.1 man page is installed. Use dh-autoreconf
#+    to update the build system.
#+
#+ -- Michael Biebl <biebl@debian.org>  Fri, 24 Jun 2016 03:01:32 +0200
#+
#+firewalld (0.4.2-2) unstable; urgency=medium
#+
#+  * Do not fail if /etc/sysconfig/network-scripts directory does not exist.
#+    Patch cherry-picked from upstream Git. (Closes: #826961)
#+
#+ -- Michael Biebl <biebl@debian.org>  Sat, 18 Jun 2016 05:58:20 +0200
#+
#+firewalld (0.4.2-1) unstable; urgency=medium
#+
#+  * New upstream release.
#+  * Refresh patches.
#+  * firewall-config: Install gtk3_niceexpander.py.
#+
#+ -- Michael Biebl <biebl@debian.org>  Tue, 07 Jun 2016 21:21:05 +0200
#+
#+firewalld (0.4.1.2-1) unstable; urgency=medium
#+
#+  * New upstream release.
#+  * Bump Standards-Version to 3.9.8.
#+
#+ -- Michael Biebl <biebl@debian.org>  Wed, 27 Apr 2016 14:43:43 +0200
#+
#+firewalld (0.4.0-1) unstable; urgency=medium
#+
#+  * Team upload.
#+  [ Michael Biebl ]
#+  * Unbreak Vcs-Browser
#+
#+  [ Laurent Bigonville ]
#+  * Imported Upstream version 0.4.0
#+  * d/p/01-no-sysconfig.patch: Refreshed
#+  * d/p/02-fix-changing-zone.patch, d/p/03_avoid-PyGIWarning.patch: Dropped,
#+    applied upstream.
#+  * d/firewall-applet.install: Install /etc/firewall/applet.conf
#+  * debian/control: Add ipset to the Recommends
#+  * debian/rules: Hardcode the paths to all the *config utilities
#+  * debian/control: firewalld now needs ebtables-restore which is only
#+    available starting version 2.0.10.4-3.1~
#+
#+ -- Laurent Bigonville <bigon@debian.org>  Sun, 07 Feb 2016 22:41:33 +0100
#+
#+firewalld (0.3.14.2-2) unstable; urgency=medium
#+
#+  * Team upload.
#+  * Protect config files by making /etc/firewalld non-world readable
#+  * Switch to python3
#+
#+ -- Laurent Bigonville <bigon@debian.org>  Fri, 20 Nov 2015 01:49:18 +0100
#+
#+firewalld (0.3.14.2-1) unstable; urgency=medium
#+
#+  * Team upload.
#+  * Imported Upstream version 0.3.14.2
#+  * Add dh-python to the build-dependencies
#+  * Split firewall-config out of the firewall-applet package
#+  * Update the Vcs-* URL's to please lintian
#+  * Fix PermissionDenied when trying to change the zone of a connection
#+    (Closes: #767888)
#+  * d/p/03_avoid-PyGIWarning.patch: avoid PyGIWarning seen with Gtk-3.17
#+
#+ -- Laurent Bigonville <bigon@debian.org>  Sat, 17 Oct 2015 00:16:17 +0200
#+
#+firewalld (0.3.13-1) unstable; urgency=medium
#+
#+  * New upstream release.
#+
#+ -- Michael Biebl <biebl@debian.org>  Thu, 07 May 2015 00:20:34 +0200
#+
#+firewalld (0.3.12-1) unstable; urgency=medium
#+
#+  * New upstream release.
#+  * Bump Standards-Version to 3.9.6. No further changes.
#+
#+ -- Michael Biebl <biebl@debian.org>  Thu, 16 Oct 2014 06:22:54 +0200
#+
#+firewalld (0.3.11-1) unstable; urgency=medium
#+
#+  * New upstream release.
#+
#+ -- Michael Biebl <biebl@debian.org>  Thu, 21 Aug 2014 15:25:36 +0200
#+
#+firewalld (0.3.10-1) unstable; urgency=medium
#+
#+  * New upstream release.
#+  * Add Depends on policykit-1, access to the firewalld D-Bus interface is
#+    protected by PolicyKit.
#+  * Install AppData file.
#+
#+ -- Michael Biebl <biebl@debian.org>  Sat, 31 May 2014 00:27:02 +0200
#+
#+firewalld (0.3.9.3-1) unstable; urgency=medium
#+
#+  * New upstream release.
#+  * Bump Standards-Version to 3.9.5. No further changes.
#+  * Update copyright years.
#+
#+ -- Michael Biebl <biebl@debian.org>  Sat, 15 Feb 2014 17:08:17 +0100
#+
#+firewalld (0.3.7-1) unstable; urgency=low
#+
#+  * New upstream release.
#+
#+ -- Michael Biebl <biebl@debian.org>  Thu, 17 Oct 2013 18:01:20 +0200
#+
#+firewalld (0.3.6.2-1) unstable; urgency=low
#+
#+  * New upstream release.
#+
#+ -- Michael Biebl <biebl@debian.org>  Fri, 04 Oct 2013 19:39:44 +0200
#+
#+firewalld (0.3.6-1) unstable; urgency=low
#+
#+  * New upstream release.
#+  * Remove debian/patches/02-IPv6-NAT-check.patch, merged upstream.
#+
#+ -- Michael Biebl <biebl@debian.org>  Thu, 03 Oct 2013 00:58:11 +0200
#+
#+firewalld (0.3.5-1) unstable; urgency=low
#+
#+  * New upstream release.
#+  * Use dh-systemd to properly register the systemd service file.
#+    (Closes: #715250)
#+  * debian/patches/02-IPv6-NAT-check.patch: Don't use uname and a simple
#+    kernel version check to determine whether the kernel supports IPv6 NAT.
#+    This fails with the  Debian kernel versioning scheme and isn't a
#+    sufficient check anyway. Instead execute "ip6tables -t nat -L" and check
#+    the return code.
#+  * Install autostart file for firewall-applet.
#+
#+ -- Michael Biebl <biebl@debian.org>  Tue, 01 Oct 2013 02:08:54 +0200
#+
#+firewalld (0.3.4-1) unstable; urgency=low
#+
#+  * New upstream release.
#+  * Add Build-Depends on xsltproc, docbook-xsl and docbook-xml for the man
#+    pages which are created from docbook sources now.
#+
#+ -- Michael Biebl <biebl@debian.org>  Tue, 30 Jul 2013 21:50:44 +0200
#+
#+firewalld (0.3.3-1) unstable; urgency=low
#+
#+  * New upstream release.
#+
#+ -- Michael Biebl <biebl@debian.org>  Sat, 08 Jun 2013 01:41:11 +0200
#+
#+firewalld (0.3.2-1) unstable; urgency=low
#+
#+  * New upstream release.
#+
#+ -- Michael Biebl <biebl@debian.org>  Fri, 10 May 2013 20:42:49 +0200
#+
#+firewalld (0.3.1-1) unstable; urgency=low
#+
#+  * New upstream release.
#+  * Refresh 01-no-sysconfig.patch.
#+  * Install bash-completion for firewall-cmd.
#+
#+ -- Michael Biebl <biebl@debian.org>  Thu, 28 Mar 2013 22:27:22 +0100
#+
#+firewalld (0.3.0-1) unstable; urgency=low
#+
#+  * New upstream release.
#+  * Update patches:
#+    - Refresh 01-no-sysconfig.patch.
#+    - Drop 02-don-t-keep-file-descriptors-open-when-forking.patch, merged
#+      upstream.
#+
#+ -- Michael Biebl <biebl@debian.org>  Wed, 20 Mar 2013 19:39:29 +0100
#+
#+firewalld (0.2.12-4) unstable; urgency=low
#+
#+  * Add Depends on dbus. It's a required dependency and insserv will bail out
#+    if dbus is not installed. (Closes: #702047)
#+
#+ -- Michael Biebl <biebl@debian.org>  Thu, 14 Mar 2013 18:53:03 +0100
#+
#+firewalld (0.2.12-3) unstable; urgency=low
#+
#+  * Add Depends on iptables.
#+
#+ -- Michael Biebl <biebl@debian.org>  Sat, 09 Feb 2013 21:48:48 +0100
#+
#+firewalld (0.2.12-2) unstable; urgency=low
#+
#+  * Add SysV init script.
#+  * Don't keep file descriptors open when forking.
#+
#+ -- Michael Biebl <biebl@debian.org>  Sat, 09 Feb 2013 15:33:08 +0100
#+
#+firewalld (0.2.12-1) unstable; urgency=low
#+
#+  * Initial release. (Closes: #700154)
#+
#+ -- Michael Biebl <biebl@debian.org>  Sat, 09 Feb 2013 07:28:08 +0100
#diff -Nru debian~/compat debian/compat
#--- debian~/compat	1969-12-31 19:00:00.000000000 -0500
#+++ debian/compat	2020-12-29 02:08:49.526680719 -0500
#@@ -0,0 +1 @@
#+12
#diff -Nru debian~/control debian/control
#--- debian~/control	1969-12-31 19:00:00.000000000 -0500
#+++ debian/control	2020-12-29 02:08:49.546680256 -0500
#@@ -0,0 +1,121 @@
#+Source: firewalld
#+Section: net
#+Priority: optional
#+Maintainer: Utopia Maintenance Team <pkg-utopia-maintainers@lists.alioth.debian.org>
#+Uploaders: Michael Biebl <biebl@debian.org>
#+Build-Depends: autoconf,
#+               dh-autoreconf,
#+               docbook,
#+               docbook-xsl,
#+               gettext,
#+               intltool,
#+               kmod,
#+               libglib2.0-dev,
#+               libglib2.0-dev-bin,
#+               libxml2-utils,
#+               pkgconf,
#+               python3-all (>= 3.2),
#+               xsltproc
#+Standards-Version: 4.5.0
#+Vcs-Git: https://github.com/firewalld/firewalld
#+Vcs-Browser: https://github.com/firewalld/firewalld
#+Homepage: http://www.firewalld.org/
#+
#+Package: firewalld
#+Architecture: armhf
#+Pre-Depends: ${misc:Pre-Depends}
#+Depends: dbus,
#+         gir1.2-glib-2.0,
#+         gir1.2-nm-1.0,
#+         iptables (>= 1.8.5-3~),
#+         policykit-1,
#+         python3-dbus,
#+         python3-gi,
#+         python3-nftables (>= 0.9.6-1~),
#+         python3-firewall (= ${source:Version}),
#+         ${misc:Depends},
#+         ${python3:Depends}
#+Recommends: ipset
#+Description: dynamically managed firewall with support for network zones
#+ firewalld is a dynamically managed firewall daemon with support for
#+ network/firewall zones to define the trust level of network connections
#+ or interfaces. It has support for IPv4, IPv6 firewall settings and for
#+ ethernet bridges and has a separation of runtime and persistent
#+ configuration options.
#+ It also provides a D-Bus interface for services or applications to add
#+ and apply firewall rules on-the-fly.
#+
#+Package: firewall-applet
#+Architecture: armhf
#+Pre-Depends: ${misc:Pre-Depends}
#+Depends: firewall-config (= ${source:Version}),
#+         firewalld (= ${source:Version}),
#+         gir1.2-nm-1.0,
#+         gir1.2-notify-0.7,
#+         python3-dbus,
#+         python3-gi,
#+         python3-pyqt5,
#+         python3-dbus.mainloop.pyqt5,
#+         python3-slip-dbus,
#+         python3-firewall (= ${source:Version}),
#+         ${misc:Depends},
#+         ${python3:Depends}
#+Description: panel applet providing status information of firewalld
#+ firewalld is a dynamically managed firewall daemon with support for
#+ network/firewall zones to define the trust level of network connections
#+ or interfaces. It has support for IPv4, IPv6 firewall settings and for
#+ ethernet bridges and has a separation of runtime and persistent
#+ configuration options.
#+ It also provides a D-Bus interface for services or applications to add
#+ and apply firewall rules on-the-fly.
#+ .
#+ This package provides a panel applet which shows status information
#+ of firewalld.
#+
#+Package: firewall-config
#+Architecture: armhf
#+Pre-Depends: ${misc:Pre-Depends}
#+Depends: firewalld (= ${source:Version}),
#+         gir1.2-glib-2.0,
#+         gir1.2-gtk-3.0,
#+         gir1.2-nm-1.0,
#+         gir1.2-pango-1.0,
#+         python3-dbus,
#+         python3-gi,
#+         python3-firewall (= ${source:Version}),
#+         ${misc:Depends},
#+         ${python3:Depends}
#+Description: graphical configuration tool to change the firewall settings
#+ firewalld is a dynamically managed firewall daemon with support for
#+ network/firewall zones to define the trust level of network connections
#+ or interfaces. It has support for IPv4, IPv6 firewall settings and for
#+ ethernet bridges and has a separation of runtime and persistent
#+ configuration options.
#+ It also provides a D-Bus interface for services or applications to add
#+ and apply firewall rules on-the-fly.
#+ .
#+ This package provides a graphical configuration tool to change the
#+ firewall settings.
#+
#+Package: python3-firewall
#+Architecture: armhf
#+Section: python
#+Depends: gir1.2-glib-2.0,
#+         python3-gi,
#+         python3-dbus,
#+         python3-decorator,
#+         python3-slip-dbus,
#+         ${misc:Depends},
#+         ${python3:Depends}
#+Breaks: firewalld (<< 0.8.2-1~)
#+Replaces: firewalld (<< 0.8.2-1~)
#+Description: Python3 bindings for firewalld
#+ firewalld is a dynamically managed firewall daemon with support for
#+ network/firewall zones to define the trust level of network connections
#+ or interfaces. It has support for IPv4, IPv6 firewall settings and for
#+ ethernet bridges and has a separation of runtime and persistent
#+ configuration options.
#+ It also provides a D-Bus interface for services or applications to add
#+ and apply firewall rules on-the-fly.
#+ .
#+ This package provides Python3 bindings for firewalld.
#diff -Nru debian~/copyright debian/copyright
#--- debian~/copyright	1969-12-31 19:00:00.000000000 -0500
#+++ debian/copyright	2020-12-29 02:08:49.538680442 -0500
#@@ -0,0 +1,23 @@
#+Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
#+Upstream-Name: FirewallD
#+Upstream-Contact: Thomas Woerner <twoerner@redhat.com>
#+Source: http://www.firewalld.org/download/all.html
#+
#+Files: *
#+Copyright: 2009 - 2017 Red Hat, Inc.
#+License: GPL-2+
#+ This package is free software; you can redistribute it and/or modify
#+ it under the terms of the GNU General Public License as published by
#+ the Free Software Foundation; either version 2 of the License, or
#+ (at your option) any later version.
#+ .
#+ This package is distributed in the hope that it will be useful,
#+ but WITHOUT ANY WARRANTY; without even the implied warranty of
#+ MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#+ GNU General Public License for more details.
#+ .
#+ You should have received a copy of the GNU General Public License
#+ along with this program. If not, see <http://www.gnu.org/licenses/>
#+ .
#+ On Debian systems, the complete text of the GNU General Public
#+ License version 2 can be found in "/usr/share/common-licenses/GPL-2".
#diff -Nru debian~/firewall-applet.install debian/firewall-applet.install
#--- debian~/firewall-applet.install	1969-12-31 19:00:00.000000000 -0500
#+++ debian/firewall-applet.install	2020-12-29 02:08:49.558679978 -0500
#@@ -0,0 +1,6 @@
#+etc/firewall/applet.conf
#+etc/xdg/autostart/firewall-applet.desktop
#+usr/bin/firewall-applet
#+usr/share/icons/hicolor/*/apps/firewall-applet*.png
#+usr/share/icons/hicolor/*/apps/firewall-applet*.svg
#+usr/share/man/man1/firewall-applet.1
#diff -Nru debian~/firewall-config.install debian/firewall-config.install
#--- debian~/firewall-config.install	1969-12-31 19:00:00.000000000 -0500
#+++ debian/firewall-config.install	2020-12-29 02:08:49.522680812 -0500
#@@ -0,0 +1,10 @@
#+usr/bin/firewall-config
#+usr/share/applications/firewall-config.desktop
#+usr/share/firewalld/firewall-config.glade
#+usr/share/firewalld/gtk3_chooserbutton.py
#+usr/share/firewalld/gtk3_niceexpander.py
#+usr/share/glib-2.0/schemas/org.fedoraproject.FirewallConfig.gschema.xml
#+usr/share/icons/hicolor/*/apps/firewall-config.png
#+usr/share/icons/hicolor/*/apps/firewall-config.svg
#+usr/share/man/man1/firewall-config.1
#+usr/share/metainfo/firewall-config.appdata.xml
#diff -Nru debian~/firewalld.install debian/firewalld.install
#--- debian~/firewalld.install	1969-12-31 19:00:00.000000000 -0500
#+++ debian/firewalld.install	2020-12-29 02:08:49.534680534 -0500
#@@ -0,0 +1,17 @@
#+etc/firewalld/
#+etc/logrotate.d/firewalld
#+etc/modprobe.d
#+usr/bin/firewall-cmd
#+usr/bin/firewall-offline-cmd
#+usr/lib/firewalld/
#+lib/systemd/system/
#+usr/sbin/firewalld
#+usr/share/bash-completion/
#+usr/share/dbus-1/
#+usr/share/locale/
#+usr/share/man/man1/firewall-cmd.1
#+usr/share/man/man1/firewall-offline-cmd.1
#+usr/share/man/man1/firewalld.1
#+usr/share/man/man5/
#+usr/share/polkit-1/
#+usr/share/zsh/vendor-completions/
#diff -Nru debian~/firewalld.postinst debian/firewalld.postinst
#--- debian~/firewalld.postinst	1969-12-31 19:00:00.000000000 -0500
#+++ debian/firewalld.postinst	2020-12-29 02:08:49.506681182 -0500
#@@ -0,0 +1,37 @@
#+#!/bin/sh
#+# postinst script for firewalld
#+#
#+# see: dh_installdeb(1)
#+
#+set -e
#+
#+case "$1" in
#+    configure)
#+	if dpkg --compare-versions "$2" lt-nl "0.3.14.2-2~"; then
#+            if ! dpkg-statoverride --list /etc/firewalld >/dev/null 2>&1; then
#+                chmod 0750 /etc/firewalld
#+            fi
#+	fi
#+        update-alternatives --install /usr/share/polkit-1/actions/org.fedoraproject.FirewallD1.policy \
#+            org.fedoraproject.FirewallD1.policy \
#+            /usr/share/polkit-1/actions/org.fedoraproject.FirewallD1.server.policy.choice 20
#+        update-alternatives --install /usr/share/polkit-1/actions/org.fedoraproject.FirewallD1.policy \
#+	    org.fedoraproject.FirewallD1.policy \
#+            /usr/share/polkit-1/actions/org.fedoraproject.FirewallD1.desktop.policy.choice 10
#+    ;;
#+
#+    abort-upgrade|abort-remove|abort-deconfigure)
#+    ;;
#+
#+    *)
#+        echo "postinst called with unknown argument \`$1'" >&2
#+        exit 1
#+    ;;
#+esac
#+
#+# dh_installdeb will replace this with shell code automatically
#+# generated by other debhelper scripts.
#+
#+#DEBHELPER#
#+
#+exit 0
#diff -Nru debian~/firewalld.prerm debian/firewalld.prerm
#--- debian~/firewalld.prerm	1969-12-31 19:00:00.000000000 -0500
#+++ debian/firewalld.prerm	2020-12-29 02:08:49.510681090 -0500
#@@ -0,0 +1,25 @@
#+#!/bin/sh
#+set -e
#+
#+
#+case "$1" in
#+    # only remove in remove/deconfigure so we don't disrupt users' preferences
#+    remove|deconfigure)
#+        update-alternatives --remove org.fedoraproject.FirewallD1.policy \
#+	    /usr/share/polkit-1/actions/org.fedoraproject.FirewallD1.server.policy.choice
#+        update-alternatives --remove org.fedoraproject.FirewallD1.policy \
#+            /usr/share/polkit-1/actions/org.fedoraproject.FirewallD1.desktop.policy.choice
#+        ;;
#+
#+    upgrade|failed-upgrade)
#+        ;;
#+
#+    *)
#+        echo "prerm called with unknown argument \`$1'" >&2
#+        exit 1
#+        ;;
#+esac
#+
#+#DEBHELPER#
#+
#+exit 0
#diff -Nru debian~/gbp.conf debian/gbp.conf
#--- debian~/gbp.conf	1969-12-31 19:00:00.000000000 -0500
#+++ debian/gbp.conf	2020-12-29 02:08:49.534680534 -0500
#@@ -0,0 +1,5 @@
#+[DEFAULT]
#+pristine-tar = True
#+patch-numbers = False
#+debian-branch = debian/buster-backports
#+upstream-branch = upstream/latest
#diff -Nru debian~/patches/Remove-etc-sysconfig-firewalld-support.patch debian/patches/Remove-etc-sysconfig-firewalld-support.patch
#--- debian~/patches/Remove-etc-sysconfig-firewalld-support.patch	1969-12-31 19:00:00.000000000 -0500
#+++ debian/patches/Remove-etc-sysconfig-firewalld-support.patch	2020-12-29 02:08:49.550680164 -0500
#@@ -0,0 +1,24 @@
#+From: Michael Biebl <biebl@debian.org>
#+Date: Sat, 9 Feb 2013 07:28:08 +0100
#+Subject: Remove /etc/sysconfig/firewalld support
#+
#+This is a Redhatism. If users want to override how firewalld is started, they
#+can use the standard systemd mechanisms for that, like drop-ins.
#+---
#+ config/firewalld.service.in | 3 +--
#+ 1 file changed, 1 insertion(+), 2 deletions(-)
#+
#+diff --git a/config/firewalld.service.in b/config/firewalld.service.in
#+index b757a08..9404453 100644
#+--- a/config/firewalld.service.in
#++++ b/config/firewalld.service.in
#+@@ -8,8 +8,7 @@ Conflicts=iptables.service ip6tables.service ebtables.service ipset.service
#+ Documentation=man:firewalld(1)
#+
#+ [Service]
#+-EnvironmentFile=-/etc/sysconfig/firewalld
#+-ExecStart=@sbindir@/firewalld --nofork --nopid $FIREWALLD_ARGS
#++ExecStart=@sbindir@/firewalld --nofork --nopid
#+ ExecReload=/bin/kill -HUP $MAINPID
#+ # supress to log debug and error output also to /var/log/messages
#+ StandardOutput=null
#diff -Nru debian~/patches/series debian/patches/series
#--- debian~/patches/series	1969-12-31 19:00:00.000000000 -0500
#+++ debian/patches/series	2020-12-29 02:08:49.554680072 -0500
#@@ -0,0 +1,2 @@
#+Remove-etc-sysconfig-firewalld-support.patch
#+Switch-to-python3.patch
#diff -Nru debian~/patches/Switch-to-python3.patch debian/patches/Switch-to-python3.patch
#--- debian~/patches/Switch-to-python3.patch	1969-12-31 19:00:00.000000000 -0500
#+++ debian/patches/Switch-to-python3.patch	2020-12-29 02:08:49.554680072 -0500
#@@ -0,0 +1,29 @@
#+From: Laurent Bigonville <bigon@debian.org>
#+Date: Fri, 20 Nov 2015 01:18:04 +0100
#+Subject: Switch to python3
#+
#+---
#+ src/gtk3_chooserbutton.py | 2 +-
#+ src/gtk3_niceexpander.py  | 2 +-
#+ 2 files changed, 2 insertions(+), 2 deletions(-)
#+
#+diff --git a/src/gtk3_chooserbutton.py b/src/gtk3_chooserbutton.py
#+index 85cab68..74d973a 100755
#+--- a/src/gtk3_chooserbutton.py
#++++ b/src/gtk3_chooserbutton.py
#+@@ -1,4 +1,4 @@
#+-#!/usr/bin/python -Es
#++#!/usr/bin/python3 -Es
#+ # -*- coding: utf-8 -*-
#+ #
#+ # Copyright (C) 2008,2012 Red Hat, Inc.
#+diff --git a/src/gtk3_niceexpander.py b/src/gtk3_niceexpander.py
#+index 84e0dd3..f099e53 100644
#+--- a/src/gtk3_niceexpander.py
#++++ b/src/gtk3_niceexpander.py
#+@@ -1,4 +1,4 @@
#+-#!/usr/bin/python -Es
#++#!/usr/bin/python3 -Es
#+ # -*- coding: utf-8 -*-
#+ #
#+ # Copyright (C) 2016 Red Hat, Inc.
#diff -Nru debian~/python3-firewall.install debian/python3-firewall.install
#--- debian~/python3-firewall.install	1969-12-31 19:00:00.000000000 -0500
#+++ debian/python3-firewall.install	2020-12-29 02:08:49.550680164 -0500
#@@ -0,0 +1 @@
#+usr/lib/python*/
#diff -Nru debian~/README.Debian debian/README.Debian
#--- debian~/README.Debian	1969-12-31 19:00:00.000000000 -0500
#+++ debian/README.Debian	2020-12-29 02:08:49.514680997 -0500
#@@ -0,0 +1,9 @@
#+firewalld for Debian
#+
#+    Red Hat's sysconfig configuration interface has been removed.
#+    To configure firewalld service, use instead systemd's mechanism -
#+    i.e., from the command line, run:
#+
#+        systemctl edit firewalld.service
#+
#+ -- Andrew L. Moore <andy@revolution-robotics>  Fri, 28 Dec 2020 09:40:11 +0000
#diff -Nru debian~/rules debian/rules
#--- debian~/rules	1969-12-31 19:00:00.000000000 -0500
#+++ debian/rules	2020-12-29 02:08:49.546680256 -0500
#@@ -0,0 +1,31 @@
#+#!/usr/bin/make -f
#+export DH_VERBOSE = 1
#+export PYTHON=/usr/bin/python3
#+
#+%:
#+	dh $@ --with autoreconf,python3
#+
#+override_dh_autoreconf:
#+	NOCONFIGURE=true dh_autoreconf -- ./autogen.sh
#+
#+override_dh_auto_configure:
#+	dh_auto_configure -- \
#+		--with-systemd-unitdir=/lib/systemd/system \
#+		--with-zshcompletiondir=/usr/share/zsh/vendor-completions/ \
#+		MODPROBE=/sbin/modprobe \
#+		RMMOD=/sbin/rmmod \
#+		SYSCTL=/sbin/sysctl
#+
#+override_dh_install:
#+	# Delete the symlink and let update-alternatives handle it
#+	rm -f debian/tmp/usr/share/polkit-1/actions/org.fedoraproject.FirewallD1.policy
#+	dh_install
#+
#+override_dh_missing:
#+	dh_missing --list-missing
#+
#+override_dh_fixperms:
#+	dh_fixperms
#+	chmod 0750 debian/firewalld/etc/firewalld/
#+
#+override_dh_auto_test:
#diff -Nru debian~/source/format debian/source/format
#--- debian~/source/format	1969-12-31 19:00:00.000000000 -0500
#+++ debian/source/format	2020-12-29 02:08:49.542680349 -0500
#@@ -0,0 +1 @@
#+3.0 (quilt)
#diff -Nru debian~/watch debian/watch
#--- debian~/watch	1969-12-31 19:00:00.000000000 -0500
#+++ debian/watch	2020-12-29 02:08:49.562679886 -0500
#@@ -0,0 +1,2 @@
#+version=3
#+https://github.com/firewalld/firewalld/releases/ .*/firewalld-(\d\S*)\.tar\.gz
