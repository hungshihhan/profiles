# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# Rename this file to claude-desktop-bin-<version>.ebuild, where <version>
# is the current Version: field from the apt index below. Before committing
# a bump, run claude-desktop-deb-diff.sh <old> <new>; see also
# claude-desktop-bin-notes.md for the 4.23118.0 payload audit.

EAPI=8

# Upstream apt index (bump target):
#   https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages
#   https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-arm64/Packages

inherit linux-info optfeature unpacker xdg

MY_PN="${PN%-bin}"
POOL_URI="https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/${MY_PN}"

DESCRIPTION="Official Claude desktop app (Chat, Cowork, Claude Code)"
HOMEPAGE="https://claude.com/ https://code.claude.com/docs/en/desktop-linux"
SRC_URI="
	amd64? ( ${POOL_URI}/${MY_PN}_${PV}_amd64.deb )
	arm64? ( ${POOL_URI}/${MY_PN}_${PV}_arm64.deb )
"
S="${WORKDIR}"

LICENSE="all-rights-reserved"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
# Proprietary binary: no redistribution, nothing to strip or test.
RESTRICT="bindist mirror strip test"

# Upstream layout since the 4.x debs (1.x used /opt).
APPDIR="/usr/lib/${MY_PN}"

# Link-time closure, verified against the 4.23118.0 amd64 deb:
#   scanelf -qn /usr/lib/claude-desktop/* | awk '{print $1}' | tr ',' '\n' | sort -u
RDEPEND="
	app-accessibility/at-spi2-core:2
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	media-libs/alsa-lib
	media-libs/mesa[gbm(+)]
	media-video/pipewire
	net-print/cups
	sys-apps/dbus
	sys-libs/libcap-ng
	sys-libs/libseccomp
	virtual/libudev
	x11-libs/cairo
	x11-libs/gtk+:3
	x11-libs/libX11
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXrandr
	x11-libs/libxcb
	x11-libs/libxkbcommon
	x11-libs/pango
"
# dlopen()ed or exec()ed at runtime: in the deb's Depends but absent from
# NEEDED, so scanelf will not show these. The deb's trash-handling
# alternative (gvfs | trash-cli | libglib2.0-bin) is satisfied by glib's gio.
RDEPEND+="
	app-crypt/libsecret
	dev-libs/wayland
	sys-apps/util-linux
	sys-apps/xdg-desktop-portal
	x11-libs/libXtst
	x11-libs/libdrm
	x11-libs/libnotify
	x11-misc/xdg-utils
"

BDEPEND="$(unpacker_src_uri_depends)"

QA_PREBUILT="${APPDIR#/}/*"

# USER_NS/SECCOMP: Chromium sandbox without the SUID helper.
# KVM/VHOST_VSOCK: Cowork's QEMU guest VM (optional feature, so warn-only).
CONFIG_CHECK="~USER_NS ~SECCOMP_FILTER ~KVM ~VHOST_VSOCK"

src_prepare() {
	default

	# 1.x debs shipped apt plumbing as payload (etc/apt, keyrings, the
	# /etc/default toggle); the 4.x debs generate all of it from postinst
	# instead, which Gentoo never runs. Keep the strip as a cheap guard
	# against reintroduction.
	rm -rf etc/apt etc/default usr/share/keyrings usr/share/lintian || die
}

src_install() {
	# Debian policy puts docs at /usr/share/doc/${MY_PN}; Gentoo wants
	# /usr/share/doc/${PF}. Relocate via dodoc, then drop the original
	# so the bulk copy below doesn't reinstall it.
	local docdir="usr/share/doc/${MY_PN}"
	if [[ -d ${docdir} ]]; then
		local docs=( "${docdir}"/* )
		[[ -e ${docs[0]} ]] && dodoc -r "${docs[@]}"
		rm -r usr/share/doc || die
	fi

	# The deb payload mirrors the final filesystem layout.
	dodir /
	cp -a --no-preserve=ownership . "${ED}"/ || die "installing deb payload failed"

	# Debian postinst equivalents (Gentoo never runs maintainer scripts).
	# Shared-mime registration for .mcpb/.dxt/.skill; the xdg eclass
	# refreshes the mime database in pkg_postinst.
	local res="${APPDIR#/}/resources"
	if [[ -f ${res}/linux-mime/com.anthropic.Claude.xml ]]; then
		insinto /usr/share/mime/packages
		doins "${res}/linux-mime/com.anthropic.Claude.xml"
	fi
	# GNOME Shell search provider registration; inert outside GNOME.
	if [[ -d ${res}/gnome-search-provider ]]; then
		insinto /usr/share/gnome-shell/search-providers
		doins "${res}/gnome-search-provider/com.anthropic.Claude.search-provider.ini"
		insinto /usr/share/dbus-1/services
		doins "${res}/gnome-search-provider/com.anthropic.Claude.SearchProvider.service"
	fi
	# /usr/bin/ccd terminal launcher: postinst links it when a build ships
	# one. 4.23118.0 does not; guard for when it appears.
	if [[ -x ${res}/bin/ccd ]]; then
		dosym -r "${APPDIR}/resources/bin/ccd" /usr/bin/ccd
	fi
	# Skipped on purpose: postinst's unconfined AppArmor profile (an
	# Ubuntu 24.04 userns workaround) and the apt repo/keyring/
	# unattended-upgrades registration.

	# Electron's SUID sandbox helper, only used if the kernel lacks
	# unprivileged user namespaces. Perms match www-client/google-chrome.
	local sandbox
	sandbox="$(find "${ED}" -type f -name chrome-sandbox 2>/dev/null | head -n1)"
	if [[ -n ${sandbox} ]]; then
		fowners root:root "${sandbox#"${ED}"}"
		fperms 4711 "${sandbox#"${ED}"}"
	fi
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "Claude Desktop for Linux is upstream beta, officially tested only on"
	elog "Ubuntu 22.04+/Debian 12+. It is a self-contained Electron app and"
	elog "generally runs fine elsewhere, but you are off the support map."
	elog
	elog "On Sway/Wayland, run with native Wayland instead of XWayland:"
	elog "  claude-desktop --ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations"
	elog "or export ELECTRON_OZONE_PLATFORM_HINT=auto. The Quick Entry global"
	elog "hotkey on Wayland requires the GlobalShortcuts portal"
	elog "(xdg-desktop-portal-wlr does not implement it; hyprland/kde portals do)."
	elog
	elog "Cowork's sandboxed execution runs a QEMU/KVM guest. It needs /dev/kvm"
	elog "and /dev/vhost-vsock, so load the vhost_vsock module (autoload with:"
	elog "  echo vhost_vsock > /etc/modules-load.d/vhost_vsock.conf )"
	elog "and add your user to the 'kvm' group. The group is required for"
	elog "/dev/vhost-vsock even where /dev/kvm is already accessible."
	elog
	elog "Updates are NOT automatic: bump the ebuild version when upstream"
	elog "publishes a new deb (check the Packages index in the apt repo)."

	local qemu_target
	qemu_target=$(usex amd64 x86_64 aarch64)
	optfeature_header "Install the following packages for additional support:"
	# A bundled virtiofsd ships at ${APPDIR}/resources/virtiofsd as fallback.
	optfeature "Cowork sandboxed execution (QEMU/KVM guest VM)" \
		"app-emulation/qemu[qemu_softmmu_targets_${qemu_target}] app-emulation/virtiofsd"
	optfeature "UEFI firmware for the Cowork VM" \
		sys-firmware/edk2-ovmf sys-firmware/edk2
	optfeature "system tray icon (StatusNotifierItem via appindicator)" \
		dev-libs/libayatana-appindicator dev-libs/libappindicator:3
	optfeature "sandboxed shell commands in local Claude Code sessions" \
		"sys-apps/bubblewrap net-misc/socat"
	optfeature "file dialogs under Wayland (portal backend)" \
		sys-apps/xdg-desktop-portal-gtk sys-apps/xdg-desktop-portal-gnome \
		kde-plasma/xdg-desktop-portal-kde
	optfeature "audio through PulseAudio/PipeWire instead of raw ALSA" \
		media-libs/libpulse
	optfeature "SSH sessions using the system OpenSSH client" net-misc/openssh
	optfeature "storing the login token via the Secret Service API" \
		gnome-base/gnome-keyring kde-plasma/kwallet app-admin/keepassxc
}
