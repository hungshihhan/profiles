# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Upstream apt index (bump target):
#   https://persistent.oaistatic.com/codex-app-prod/linux/deb/dists/stable/main/binary-amd64/Packages
#   https://persistent.oaistatic.com/codex-app-prod/linux/deb/dists/stable/main/binary-arm64/Packages

inherit linux-info optfeature unpacker xdg

MY_PN="${PN%-desktop-bin}"
POOL_URI="https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/${MY_PN}"

DESCRIPTION="Official ChatGPT desktop app for Linux (Chat, Work and Codex), repackaged from the .deb"
HOMEPAGE="https://chatgpt.com/download https://developers.openai.com/codex/app"
SRC_URI="
	amd64? ( ${POOL_URI}/${MY_PN}_${PV}_amd64.deb )
	arm64? ( ${POOL_URI}/${MY_PN}_${PV}_arm64.deb )
"
S="${WORKDIR}"

LICENSE="all-rights-reserved"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
IUSE="apparmor +wayland"
# Proprietary binary: no redistribution, nothing to strip or test.
RESTRICT="bindist mirror strip test"

# Mapped from the deb's Depends (see apt index above).
RDEPEND="
	>=app-accessibility/at-spi2-core-2.46.0:2
	app-arch/xz-utils
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	>=dev-libs/nss-3.30
	dev-libs/libusb:1
	media-libs/alsa-lib
	media-libs/fontconfig
	media-libs/libglvnd
	media-libs/mesa[gbm(+)]
	net-print/cups
	sys-apps/dbus
	virtual/libudev
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
	apparmor? ( sys-apps/apparmor )
	wayland? ( dev-libs/wayland )
"

# Upstream layout is /usr/lib/chatgpt (arch-independent Electron bundle);
# kept as-is so the shipped AppArmor profile and launcher stay valid.
APPDIR="/usr/lib/${MY_PN}"

QA_PREBUILT="${APPDIR#/}/*"
# Electron renderers use the SUID sandbox when user namespaces are off.
CONFIG_CHECK="~USER_NS ~SECCOMP_FILTER"

src_prepare() {
	default

	# Debian-only bits: apt repo registration, keyrings, cron, docs, lintian.
	rm -rf etc/apt etc/cron.daily usr/share/keyrings usr/share/lintian || die

	# Electron's optional Qt shims dlopen Qt for KDE dialogs; drop them so
	# they neither pull Qt into RDEPEND nor trip the NEEDED QA check.
	find "${S}${APPDIR}" -maxdepth 1 -name 'libqt*_shim.so' -delete || die

	# npm native modules (node-hid, serialport, classic-level, ...) ship
	# prebuilds for every platform. Keep only linux-<arch>/glibc; the rest
	# (android, other arches, musl) can never load here and only trigger
	# the unresolved-soname QA check.
	local node_arch
	case ${ARCH} in
		amd64) node_arch=x64 ;;
		arm64) node_arch=arm64 ;;
		*) die "unsupported ARCH=${ARCH}" ;;
	esac
	local dir
	while IFS= read -r -d '' dir; do
		case ${dir##*/} in
			linux-${node_arch}|*-linux-${node_arch}) ;;
			*) rm -r "${dir}" || die ;;
		esac
	done < <(find "${S}${APPDIR}" -type d -path '*/prebuilds/*' -prune -print0)
	find "${S}${APPDIR}" -path '*/prebuilds/*' -name '*musl*' -delete || die

	# Point every launcher at the wrapper in /usr/bin (see files/).
	local desktop
	while IFS= read -r -d '' desktop; do
		sed -i \
			-e "s|^Exec=\S*/${MY_PN}\b|Exec=${MY_PN}|" \
			-e "s|^Exec=\S*/codex-launcher\b|Exec=${MY_PN}|" \
			-e "s|^Exec=\S*/ChatGPT\b|Exec=${MY_PN}|" \
			"${desktop}" || die
	done < <(find usr/share/applications -name '*.desktop' -print0)
}

src_install() {
	# Copy the bundle verbatim, preserving upstream's exec bits.
	dodir "${APPDIR%/*}"
	cp -pPR "${S}${APPDIR}" "${ED}${APPDIR}" || die

	# Chromium SUID sandbox helper (only used when USER_NS is unavailable),
	# matching www-client/google-chrome.
	if [[ -f ${ED}${APPDIR}/chrome-sandbox ]]; then
		fowners root:root "${APPDIR}/chrome-sandbox"
		fperms 4711 "${APPDIR}/chrome-sandbox"
	fi

	# Wrapper: reads ~/.config/chatgpt-flags.conf, adds Wayland flags, then
	# hands over to upstream's own launcher so its behaviour is preserved.
	sed \
		-e "s|@APPDIR@|${EPREFIX}${APPDIR}|" \
		-e "s|@WAYLAND@|$(usex wayland true false)|" \
		"${FILESDIR}/${MY_PN}-launcher.sh" > "${T}/${MY_PN}" || die
	dobin "${T}/${MY_PN}"

	# Desktop integration (upstream's /usr/bin symlink is superseded above).
	local dir
	for dir in applications icons pixmaps metainfo mime; do
		if [[ -d usr/share/${dir} ]]; then
			insinto /usr/share
			doins -r "usr/share/${dir}"
		fi
	done

	if use apparmor && [[ -f etc/apparmor.d/${MY_PN} ]]; then
		insinto /etc/apparmor.d
		doins "etc/apparmor.d/${MY_PN}"
	fi

	if [[ -f usr/share/doc/${MY_PN}/copyright ]]; then
		dodoc "usr/share/doc/${MY_PN}/copyright"
	fi
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "Extra Chromium/Electron flags can be put one per line in"
	elog "  \${XDG_CONFIG_HOME:-~/.config}/${MY_PN}-flags.conf"
	if use wayland; then
		elog "USE=wayland launches with --ozone-platform-hint=auto and"
		elog "--enable-wayland-ime; export CHATGPT_NO_WAYLAND_FLAGS=1 to opt out."
	fi
	if use apparmor; then
		elog "The upstream AppArmor profile was installed to /etc/apparmor.d/${MY_PN};"
		elog "reload it with: apparmor_parser -r /etc/apparmor.d/${MY_PN}"
	fi

	optfeature_header "Install the following packages for additional support:"
	optfeature "audio output (Chromium prefers PulseAudio/PipeWire over ALSA)" \
		media-libs/libpulse media-video/pipewire
	optfeature "screen sharing under Wayland" media-video/pipewire
	optfeature "storing the login token via the Secret Service API" \
		gnome-base/gnome-keyring kde-plasma/kwallet app-admin/keepassxc
	optfeature "GPU Vulkan backend instead of the bundled SwiftShader" \
		media-libs/vulkan-loader media-libs/mesa[vulkan]
	optfeature "Git integration in Codex" dev-vcs/git
}
