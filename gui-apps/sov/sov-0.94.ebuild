# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit meson systemd

DESCRIPTION="An overlay that shows schemas for all workspaces to make navigation in sway easier"
HOMEPAGE="https://github.com/milgra/sov"
SRC_URI="https://github.com/milgra/sov/archive/${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="systemd"

DEPEND="
	dev-libs/wayland
	dev-libs/wayland-protocols
	media-libs/freetype:2
	media-libs/glew:0=
	media-libs/libpng:0=
	media-libs/mesa[egl(+),gles2(+)]
	x11-libs/libxkbcommon
"
RDEPEND="${DEPEND}"
BDEPEND="
	virtual/pkgconfig
"

src_install() {
	meson_src_install
	
	if use systemd; then
		systemd_douserunit contrib/systemd/sov.service
		systemd_douserunit contrib/systemd/sov.socket
	fi
}
