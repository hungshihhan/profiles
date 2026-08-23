# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit font

DESCRIPTION="The iconic font"
HOMEPAGE="https://fontawesome.com/"
SRC_URI="https://github.com/FortAwesome/Font-Awesome/archive/${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/Font-Awesome-${PV}"

LICENSE="CC-BY-4.0 OFL-1.1"
SLOT="0/7"
KEYWORDS="~amd64 ~arm ~arm64 ~loong ~ppc64 ~riscv ~x86"
IUSE="+otf woff2"

REQUIRED_USE="|| ( otf woff2 )"

src_install() {
	if use otf; then
		FONT_S="${S}/otfs" FONT_SUFFIX="otf" font_src_install
	fi

	if use woff2; then
		FONT_S="${S}/webfonts" FONT_SUFFIX="woff2" font_src_install
	fi
}
