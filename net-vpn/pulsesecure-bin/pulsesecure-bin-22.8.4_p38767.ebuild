# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Ivanti's own download portal needs a login; NTU mirrors the .deb publicly:
#   https://ccnet.ntu.edu.tw/vpn/for-ubuntu.html
# Note that the pulsesvc / PulseClient_x86_64.sh instructions on that page
# describe the old /usr/local/pulse layout. 22.8R4 only ships /opt/pulsesecure:
# a root daemon (pulsesecure, systemd unit), a gtkmm UI (pulseUI), a CLI
# client (pulselauncher) and a CEF-based browser for SAML sign-in.

inherit desktop linux-info optfeature systemd unpacker xdg

# 22.8.4_p38767 -> 22.8r4-b38767 (deb Version: 22.8.R4, build 38767)
MY_PV="$(ver_cut 1-2)r$(ver_cut 3)-b$(ver_cut 5)"
# CEF build pinned by upstream's bin/setup_cef.sh (which also carries the
# SHA-256 of the tarball and of libcef.so).
CEF_P="cef_binary_132.3.1+g144febe+chromium-132.0.6834.83_linux64_minimal"

DESCRIPTION="Ivanti Secure Access (Pulse Secure) SSL VPN client, repackaged from the .deb"
HOMEPAGE="https://www.ivanti.com/products/secure-unified-client https://ccnet.ntu.edu.tw/vpn/"
SRC_URI="
	https://ccnet.ntu.edu.tw/vpn/Download/ps-pulse-linux-${MY_PV}-64bit-installer.deb
	cef? ( https://pcstp.pulsesecure.net/cef/linux/cef64.132.tar.bz2 -> ${CEF_P}.tar.bz2 )
"
S="${WORKDIR}"

LICENSE="all-rights-reserved"
SLOT="0"
KEYWORDS="-* ~amd64"
IUSE="cef"
# Proprietary binary: no redistribution, nothing to strip or test.
RESTRICT="bindist mirror strip test"

# Mapped from the deb's Pre-Depends plus the DT_NEEDED entries of every ELF
# file and the tools the binaries and helper scripts call by absolute path.
RDEPEND="
	app-accessibility/at-spi2-core:2
	app-misc/ca-certificates
	dev-cpp/atkmm:0
	dev-cpp/cairomm:0
	dev-cpp/glibmm:2
	dev-cpp/gtkmm:3.0
	dev-cpp/pangomm:1.4
	dev-libs/glib:2
	dev-libs/libbsd
	dev-libs/libsigc++:2
	dev-libs/nss[utils]
	media-libs/harfbuzz
	net-libs/webkit-gtk:4.1
	net-misc/curl
	sys-apps/acl
	sys-apps/dbus
	sys-apps/systemd
	sys-apps/util-linux
	virtual/zlib
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3
	x11-libs/libX11
	x11-libs/pango
	cef? (
		dev-libs/expat
		dev-libs/nspr
		media-libs/alsa-lib
		media-libs/fontconfig
		media-libs/mesa[gbm(+)]
		net-print/cups
		virtual/libudev
		x11-libs/libdrm
		x11-libs/libxcb
		x11-libs/libXcomposite
		x11-libs/libXdamage
		x11-libs/libXext
		x11-libs/libXfixes
		x11-libs/libxkbcommon
		x11-libs/libXrandr
	)
"
# The deb's data.tar is zstd-compressed; unpacker.eclass only derives this
# dependency from the SRC_URI suffix.
BDEPEND="
	app-arch/zstd
	dev-util/patchelf
"

APPDIR="/opt/pulsesecure"

QA_PREBUILT="${APPDIR#/}/*"
# The tunnel manager opens /dev/net/tun; CEF prefers user namespaces for
# its renderer sandbox.
CONFIG_CHECK="~TUN"

pkg_setup() {
	use cef && CONFIG_CHECK+=" ~USER_NS"
	linux-info_pkg_setup
}

src_unpack() {
	unpacker "${DISTDIR}"/ps-pulse-linux-${MY_PV}-64bit-installer.deb

	if use cef; then
		# setup_cef.sh only extracts Release/ and Resources/; the rest of the
		# tarball is the C++ SDK (headers, libcef_dll wrapper, cmake files).
		mkdir cef || die
		tar -xjf "${DISTDIR}/${CEF_P}.tar.bz2" -C cef --strip-components=1 \
			"${CEF_P}"/Release "${CEF_P}"/Resources || die
	fi
}

src_prepare() {
	default

	# Ubuntu-only: downloads bionic-era webkit2gtk debs on Ubuntu 24.04.
	rm "${S}${APPDIR}"/bin/package_installer.sh || die

	# pulseUI is linked against the libsoup2-based WebKitGTK 4.0 ABI, which is
	# gone from ::gentoo. It only imports webkit_web_view_new(),
	# webkit_web_view_load_html() and webkit_web_view_get_type() (to render
	# the Host Checker remediation pages), all unchanged in the 4.1 API, and
	# nothing at all from libsoup or JavaScriptCore. Retarget it to 4.1 and
	# drop the stale DT_NEEDED entries: libsoup3 aborts the process if
	# libsoup2 gets loaded next to it.
	patchelf \
		--replace-needed libwebkit2gtk-4.0.so.37 libwebkit2gtk-4.1.so.0 \
		--remove-needed libjavascriptcoregtk-4.0.so.18 \
		--remove-needed libsoup-2.4.so.1 \
		"${S}${APPDIR}"/bin/pulseUI || die

	# libdispatch.so carries its builder's home directory plus an empty
	# (insecure) entry as RUNPATH. Its only private dependency,
	# libBlocksRuntime.so, sits next to it.
	patchelf --set-rpath '$ORIGIN' "${S}${APPDIR}"/lib/dispatch/libdispatch.so || die

	# doman wants the uncompressed page.
	gunzip usr/share/man/man1/pulse.1.gz || die
}

src_install() {
	# Copy the tree verbatim: the layout is hardcoded in the binaries,
	# lib/JUNS/access.ini and the helper scripts.
	dodir "${APPDIR%/*}"
	cp -pPR "${S}${APPDIR}" "${ED}${APPDIR}" || die

	if use cef; then
		# Mirror setup_cef.sh: Release/ and Resources/ side by side, with the
		# resources duplicated into Release/ where libcef.so looks for them.
		local cefdir=${APPDIR}/lib/cefRuntime
		dodir "${cefdir}"
		cp -pPR "${WORKDIR}"/cef/{Release,Resources} "${ED}${cefdir}"/ || die
		cp -pPR "${WORKDIR}"/cef/Resources/. "${ED}${cefdir}"/Release/ || die

		# Chromium SUID sandbox helper (only used when USER_NS is unavailable),
		# matching www-client/google-chrome.
		if [[ -f ${ED}${cefdir}/Release/chrome-sandbox ]]; then
			fowners root:root "${cefdir}"/Release/chrome-sandbox
			fperms 4711 "${cefdir}"/Release/chrome-sandbox
		fi
	fi

	# D-Bus system bus policy for the root daemon (upstream symlinks it into
	# place; install a proper copy instead).
	insinto /usr/share/dbus-1/system.d
	doins "${S}${APPDIR}"/lib/JUNS/net.psecure.pulse.conf

	systemd_dounit lib/systemd/system/pulsesecure.service

	domenu usr/share/applications/pulse.desktop
	doman usr/share/man/man1/pulse.1

	# Connection store and device id written by the daemon.
	keepdir /var/lib/pulsesecure/pulse

	# /opt/bin is in the default PATH.
	local bin
	for bin in pulseUI pulselauncher jamCommand; do
		dosym -r "${APPDIR}/bin/${bin}" "/opt/bin/${bin}"
	done
}

pkg_postinst() {
	xdg_pkg_postinst

	# From the deb's postinst: default ACLs so the per-user UI can read the
	# connection store the root daemon writes.
	local statedir=${EROOT}/var/lib/pulsesecure/pulse
	if ! setfacl -d -m g::r,o::r "${statedir}"; then
		ewarn "Could not set default ACLs on ${statedir} (no setfacl, or a"
		ewarn "filesystem without ACL support); run as root once sys-apps/acl is in:"
		ewarn "  setfacl -d -m g::r,o::r ${statedir}"
	fi

	# The client's TLS verifyTrust() only reads /etc/ssl/certs/ca-certificates.crt
	# when it detects Debian/Ubuntu (via PRETTY_NAME in /etc/os-release); on every
	# other distro it hardcodes the Red Hat bundle path, which Gentoo never
	# creates. Without it X509_STORE_load_locations() fails ("Failed to load CA
	# certs. verifyTrust failed") and every gateway looks untrusted. Provide that
	# path as a symlink to the real bundle. Guarded so we never clobber a file
	# managed by anything else (e.g. a p11-kit-based setup).
	local rhbundle=${EROOT}/etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt
	if [[ ! -e ${rhbundle} && ! -L ${rhbundle} ]]; then
		if mkdir -p "${rhbundle%/*}" &&
			ln -s ../../../../ssl/certs/ca-certificates.crt "${rhbundle}"; then
			elog "Linked the CA bundle path the client expects on non-Debian systems:"
			elog "  ${rhbundle#${EROOT}} -> /etc/ssl/certs/ca-certificates.crt"
			elog "Without it the client rejects every gateway as untrusted."
		else
			ewarn "Could not create ${rhbundle#${EROOT}}."
			ewarn "The client will reject gateways as untrusted until it exists;"
			ewarn "create it by hand as a symlink to /etc/ssl/certs/ca-certificates.crt."
		fi
	fi

	elog "Enable and start the daemon before launching the client:"
	elog "  systemctl enable --now pulsesecure.service"
	elog
	elog "GUI: pulseUI (also in the application menu). Command line:"
	elog "  pulselauncher -U https://<server> -r <realm> -u <user>"
	elog "e.g. for NTU:"
	elog "  pulselauncher -U https://sslvpn.ntu.edu.tw -r 'NTU EMail Account' -u <account>"
	elog "Ctrl-C disconnects. Logs: /var/log/pulsesecure/logging/PulseClient.log"
	elog
	elog "While connected, the tunnel manager configures DNS through"
	elog "systemd-resolved when it is running and falls back to editing"
	elog "/etc/resolv.conf directly otherwise."
	elog
	if use cef; then
		elog "The Chromium Embedded Framework for browser-based (SAML/SSO) sign-in"
		elog "is installed in ${APPDIR}/lib/cefRuntime. Its window is X11-only."
	else
		elog "Browser-based (SAML/SSO) sign-in needs the Chromium Embedded"
		elog "Framework (~1 GiB), which USE=cef installs through Portage. Without"
		elog "it the client offers to download CEF itself, into"
		elog "${APPDIR}/lib/cefRuntime and outside Portage's control."
	fi

	optfeature_header "Install the following packages for additional support:"
	if use cef; then
		optfeature "the (X11-only) CEF sign-in window on Wayland" x11-base/xwayland
	fi
	optfeature "importing connection bundles with jamCommand /importFile" \
		app-arch/unzip
	optfeature "NetworkManager-aware network change detection (nmcli)" \
		net-misc/networkmanager
	optfeature "Host Checker hardware inventory" sys-apps/dmidecode
	optfeature "collecting support bundles with LogsAndDiagnostics.sh" \
		app-arch/zip sys-apps/net-tools
}

pkg_postrm() {
	xdg_pkg_postrm

	if [[ -z ${REPLACED_BY_VERSION} ]]; then
		# Drop the CA-bundle symlink from pkg_postinst, but only if it is still
		# the symlink we created (never a real bundle the admin put there).
		local rhbundle=${EROOT}/etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt
		if [[ -L ${rhbundle} &&
			$(readlink "${rhbundle}") == */ssl/certs/ca-certificates.crt ]]; then
			rm -f "${rhbundle}"
			rmdir -p --ignore-fail-on-non-empty "${rhbundle%/*}" 2>/dev/null
		fi

		elog "Connection settings in /var/lib/pulsesecure and any CEF runtime"
		elog "the client downloaded itself into ${APPDIR}/lib/cefRuntime"
		elog "were left in place."
	fi
}
