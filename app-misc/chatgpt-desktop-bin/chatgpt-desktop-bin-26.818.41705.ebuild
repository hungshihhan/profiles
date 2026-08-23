# Copyright 2026 Local overlay contributors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop optfeature pax-utils unpacker xdg

DESCRIPTION="Official ChatGPT desktop application for Linux"
HOMEPAGE="https://chatgpt.com/download/ https://learn.chatgpt.com/docs/linux/linux-app"
SRC_URI="
	amd64? (
		https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${PV}_amd64.deb
			-> ${P}-amd64.deb
	)
	arm64? (
		https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${PV}_arm64.deb
			-> ${P}-arm64.deb
	)
"
S=${WORKDIR}

LICENSE="all-rights-reserved"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
IUSE="apparmor qt6 wayland"
RESTRICT="bindist mirror strip test"

RDEPEND="
	>=app-accessibility/at-spi2-core-2.46.0:2
	app-misc/ca-certificates
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	media-libs/alsa-lib
	media-libs/libglvnd
	media-libs/mesa[gbm(+)]
	net-print/cups
	sys-apps/dbus
	sys-libs/glibc
	virtual/libudev
	virtual/libusb:1
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3
	x11-libs/libdrm
	x11-libs/libnotify
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libxkbcommon
	x11-libs/libXrandr
	x11-libs/pango
	x11-misc/xdg-utils
	apparmor? (
		>=sec-policy/apparmor-profiles-4
		>=sys-apps/apparmor-4
	)
	qt6? ( dev-qt/qtbase:6[gui,widgets] )
"

QA_PREBUILT="opt/${PN}/*"

src_unpack() {
	unpack_deb "${A}"
}

src_prepare() {
	default

	local arch=x64
	use arm64 && arch=arm64

	# Upstream ships native Node modules for every platform it targets.
	# Keep only the modules for the selected Gentoo architecture.
	local candidate
	while IFS= read -r -d '' candidate; do
		[[ ${candidate} == *linux-${arch} ]] || rm -r "${candidate}" || die
	done < <(
		find usr/lib/chatgpt -type d -name prebuilds \
			-exec find {} -mindepth 1 -maxdepth 1 -print0 \;
	)

	find usr/lib/chatgpt -name '*.musl.node' -delete || die

	# The Qt shims are optional desktop-integration helpers.
	rm usr/lib/chatgpt/libqt5_shim.so || die
	use qt6 || rm usr/lib/chatgpt/libqt6_shim.so || die

	# Match the actual Electron window class and optionally make native
	# Wayland the default for launches from the desktop menu.
	local exec="chatgpt"
	use wayland && exec+=" --ozone-platform=wayland --enable-wayland-ime"
	sed -i \
		-e "s|^Exec=chatgpt|Exec=${exec}|" \
		-e '/^Icon=/aStartupWMClass=Chatgpt' \
		usr/share/applications/chatgpt.desktop || die

	if use apparmor; then
		# The ebuild relocates the bundled application from /usr/lib to /opt.
		sed -i "s|/usr/lib/chatgpt/ChatGPT|/opt/${PN}/ChatGPT|" \
			etc/apparmor.d/chatgpt || die
	fi
}

src_install() {
	dodir /opt
	mv usr/lib/chatgpt "${ED}/opt/${PN}" || die

	pax-mark m "${ED}/opt/${PN}/ChatGPT"

	# Use OpenAI's launcher rather than invoking the Electron binary directly.
	dosym -r "/opt/${PN}/codex-launcher" /usr/bin/chatgpt

	domenu usr/share/applications/chatgpt.desktop
	doicon usr/share/pixmaps/chatgpt.png
	dodoc usr/share/doc/chatgpt/copyright

	if use apparmor; then
		insinto /etc/apparmor.d
		doins etc/apparmor.d/chatgpt
	fi
}

pkg_postinst() {
	xdg_pkg_postinst

	ewarn "Gentoo is not an upstream-supported distribution for this preview."
	elog "The desktop app and dev-util/codex share ~/.codex; signing in may update"
	elog "the login state and configuration seen by both programs."
	optfeature "Git repository support" dev-vcs/git
	optfeature "secret/keyring storage" virtual/secret-service
}
