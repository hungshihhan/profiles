# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# Rename this file to claude-desktop-bin-<version>.ebuild, where <version>
# is the current Version: field from
# https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages

EAPI=8

inherit unpacker xdg

MY_PN="${PN%-bin}"

DESCRIPTION="Official Claude desktop app (Chat, Cowork, Claude Code)"
HOMEPAGE="https://claude.com/ https://code.claude.com/docs/en/desktop-linux"
SRC_URI="
	amd64? ( https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/${MY_PN}/${MY_PN}_${PV}_amd64.deb )
	arm64? ( https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/${MY_PN}/${MY_PN}_${PV}_arm64.deb )
"
S="${WORKDIR}"

LICENSE="all-rights-reserved"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
RESTRICT="bindist mirror strip"

# Standard Electron runtime closure. Verify against the actual binary after
# the first install with:
#   scanelf -qn /opt/claude-desktop/* | awk '{print $1}' | tr ',' '\n' | sort -u
# (adjust the path if the deb installs under /usr/lib instead of /opt)
RDEPEND="
	app-accessibility/at-spi2-core:2
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	dev-libs/wayland
	media-libs/alsa-lib
	media-libs/mesa[gbm(+)]
	net-print/cups
	sys-apps/dbus
	x11-libs/cairo
	x11-libs/gtk+:3
	x11-libs/libdrm
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

BDEPEND="$(unpacker_src_uri_depends)"

QA_PREBUILT="*"

src_prepare() {
	default

	# Strip Debian packaging plumbing that makes no sense on Gentoo:
	# apt repository registration, the archive keyring, and the
	# /etc/default toggle that controls repo registration in postinst.
	rm -rf etc/apt usr/share/keyrings etc/default

	# Some upstream debs ship lintian/doc cruft; harmless, but tidy it.
	rm -rf usr/share/lintian
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

	# The deb payload mirrors the final filesystem layout (opt/ and/or usr/).
	dodir /
	cp -a --no-preserve=ownership . "${ED}"/ || die "installing deb payload failed"

	# Electron's SUID sandbox helper. Needed only if the kernel lacks
	# unprivileged user namespaces (CONFIG_USER_NS + kernel.unprivileged_userns_clone).
	local sandbox
	sandbox="$(find "${ED}" -type f -name chrome-sandbox 2>/dev/null | head -n1)"
	if [[ -n ${sandbox} ]]; then
		fperms 4755 "${sandbox#"${ED}"}"
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
	elog "Cowork's sandboxed execution uses KVM; ensure your user is in the"
	elog "'kvm' group and /dev/kvm exists if you plan to use it."
	elog
	elog "Updates are NOT automatic: bump the ebuild version when upstream"
	elog "publishes a new deb (check the Packages index in the apt repo)."
}
