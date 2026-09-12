# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit font

MY_PN="Fork-Awesome"

DESCRIPTION="Icon font forked from Font Awesome 4.7 (drop-in replacement with extra icons)"
HOMEPAGE="https://forkaweso.me/Fork-Awesome/ https://github.com/ForkAwesome/Fork-Awesome"
SRC_URI="https://github.com/ForkAwesome/${MY_PN}/archive/refs/tags/${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/${MY_PN}-${PV}"

# Font: OFL-1.1.  README/CHANGELOG (installed as docs): CC-BY-3.0.
# The MIT-licensed CSS/LESS/SCSS web toolkit is not installed.
LICENSE="OFL-1.1 CC-BY-3.0"
SLOT="0"
KEYWORDS="~amd64 ~arm ~arm64 ~loong ~ppc64 ~riscv ~x86"

# Upstream declared the project deprecated (see README); 1.2.0 (2021-08) is
# the final release.  It is still the Font Awesome 4.7-compatible icon set
# (same Private Use Area code points, family name "forkawesome") that many
# Waybar/i3bar configs written against Font Awesome 4 expect.

# fonts/ holds one face in five web formats (eot, svg, ttf, woff, woff2);
# only the TrueType file is useful to fontconfig.
FONT_S="${S}/fonts"
FONT_SUFFIX="ttf"

# Serve requests for "FontAwesome" (Font Awesome 4's family name, e.g. in
# Waybar's default style.css) with this font when Font Awesome 4 itself is
# not installed.  Goes to /etc/fonts/conf.avail and stays inactive until
# enabled with `eselect fontconfig`.
FONT_CONF=( "${FILESDIR}"/31-fork-awesome-fontawesome-alias.conf )

DOCS=( CHANGELOG.md README.md )
