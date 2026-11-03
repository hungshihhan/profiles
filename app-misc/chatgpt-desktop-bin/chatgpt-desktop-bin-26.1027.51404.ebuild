# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop optfeature pax-utils unpacker xdg

DESCRIPTION="Official ChatGPT desktop application for Linux"
HOMEPAGE="https://chatgpt.com/download/"
SRC_URI="
	amd64? (
		https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${PV}_amd64.deb
			-> ${P}-amd64.deb
	)
"

S="${WORKDIR}"

LICENSE="all-rights-reserved"
SLOT="0"
KEYWORDS="-* ~amd64"

# Native Wayland is the default for this ebuild because it is intended for
# wlroots compositors such as Sway.  Disable it with USE=-wayland to use
# upstream's X11/XWayland behavior instead.
IUSE="apparmor qt6 +wayland"

RESTRICT="bindist mirror strip"

RDEPEND="
	!app-misc/chatgpt-desktop
	!dev-util/codex-desktop-bin
	>=app-accessibility/at-spi2-core-2.46.0:2
	app-arch/xz-utils
	app-crypt/tpm2-tss:=[abi_x86_64]
	app-misc/ca-certificates
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	dev-libs/openssl:=
	media-libs/alsa-lib
	media-libs/libglvnd
	media-libs/mesa[gbm(+),vulkan]
	media-libs/vulkan-loader
	net-print/cups
	sys-apps/dbus
	sys-apps/xdg-desktop-portal
	sys-libs/glibc
	virtual/libudev
	virtual/libusb:1
	virtual/secret-service
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
	|| (
		dev-util/glib-utils
		kde-plasma/kde-cli-tools
		app-misc/trash-cli
		gnome-base/gvfs
	)
	wayland? (
		gui-libs/xdg-desktop-portal-wlr
		media-video/pipewire
		sys-apps/xdg-desktop-portal-gtk
	)
	!wayland? (
		|| (
			sys-apps/xdg-desktop-portal-gtk
			sys-apps/xdg-desktop-portal-gnome
			kde-plasma/xdg-desktop-portal-kde
		)
	)
	apparmor? (
		>=sec-policy/apparmor-profiles-4
		>=sys-apps/apparmor-4
	)
	qt6? ( dev-qt/qtbase:6[gui,widgets] )
"

# OpenAI ships a prelinked 64-bit native module,
# resources/native/remote-control-device-key.node, which has DT_NEEDED
# entries for libtss2-esys.so.0, libtss2-mu.so.0 and
# libtss2-tcti-device.so.0.  Portage checks those SONAMEs during install QA,
# therefore the target-ABI provider must also be available at build time.
DEPEND="
	app-crypt/tpm2-tss:=[abi_x86_64]
"

QA_PREBUILT="opt/${PN}/*"

src_prepare() {
	default

	# Upstream ships native Node modules for several platforms and libc
	# variants. Keep only Linux x64/glibc payloads on amd64.
	local candidate
	while IFS= read -r -d '' candidate; do
		[[ ${candidate} == *linux-x64 ]] || rm -r "${candidate}" || die
	done < <(
		find usr/lib/chatgpt -type d -name prebuilds \
			-exec find {} -mindepth 1 -maxdepth 1 -print0 \;
	)

	find usr/lib/chatgpt -name '*.musl.node' -delete || die

	# The proprietary package includes optional Qt integration shims.
	rm -f usr/lib/chatgpt/libqt5_shim.so || die
	use qt6 || rm -f usr/lib/chatgpt/libqt6_shim.so || die

	# Help Sway/task switchers associate the Electron window with the desktop
	# entry.  Launch flags are handled in our wrapper below, so desktop and
	# terminal launches behave identically.
	if [[ -f usr/share/applications/chatgpt.desktop ]]; then
		grep -q '^StartupWMClass=' usr/share/applications/chatgpt.desktop ||
			sed -i '/^Icon=/aStartupWMClass=Chatgpt' \
				usr/share/applications/chatgpt.desktop || die
	fi

	if use apparmor && [[ -f etc/apparmor.d/chatgpt ]]; then
		sed -i \
			"s|/usr/lib/chatgpt/ChatGPT|/opt/${PN}/ChatGPT|g" \
			etc/apparmor.d/chatgpt || die
	fi
}

src_install() {
	dodir /opt
	mv usr/lib/chatgpt "${ED}/opt/${PN}" || die

	# Prebuilt Electron binaries can require MPROTECT relaxation on hardened
	# PaX-style systems.
	pax-mark m "${ED}/opt/${PN}/ChatGPT"

	# Use a small wrapper instead of upstream's launcher so native Wayland is
	# selected consistently under Sway while explicit user overrides continue
	# to win.  gnome-libsecret means Chromium's Secret Service backend; KeePassXC
	# can provide org.freedesktop.secrets.
	cat > "${T}/chatgpt-gentoo-launcher" <<-EOF || die
		#!/bin/sh

		has_ozone=false
		has_password_store=false

		for arg do
			case \${arg} in
				--ozone-platform=*) has_ozone=true ;;
				--password-store=*) has_password_store=true ;;
			esac
		done

		if ! \${has_password_store}; then
			set -- --password-store=gnome-libsecret "\$@"
		fi

		if $(usex wayland true false) &&
			[ -n "\${WAYLAND_DISPLAY:-}" ] &&
			! \${has_ozone}; then
			set -- --ozone-platform=wayland --enable-wayland-ime "\$@"
		fi

		exec /opt/${PN}/ChatGPT "\$@"
	EOF

	exeinto /opt/${PN}
	doexe "${T}/chatgpt-gentoo-launcher"
	dosym -r "/opt/${PN}/chatgpt-gentoo-launcher" /usr/bin/chatgpt

	domenu usr/share/applications/chatgpt.desktop
	doicon usr/share/pixmaps/chatgpt.png

	if [[ -f usr/share/doc/chatgpt/copyright ]]; then
		dodoc usr/share/doc/chatgpt/copyright
	fi

	if use apparmor && [[ -f etc/apparmor.d/chatgpt ]]; then
		insinto /etc/apparmor.d
		doins etc/apparmor.d/chatgpt
	fi
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "ChatGPT Desktop ${PV} installed."
	elog "Chromium password storage is forced to the Secret Service backend."
	elog "KeePassXC works when its Freedesktop.org Secret Service integration is enabled."
	elog "~/.codex is shared with Codex CLI and may contain shared login/config state."

	if use wayland; then
		elog "Native Wayland is enabled automatically when WAYLAND_DISPLAY is set."
		elog "Override per launch with: chatgpt --ozone-platform=x11"
		elog "For Sway, xdg-desktop-portal-wlr + xdg-desktop-portal-gtk + PipeWire are installed."
	fi

	optfeature "Git repository integration" dev-vcs/git
	optfeature "Qt 6 desktop integration shim" dev-qt/qtbase
}
