# Copyright 2021 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

PYTHON_COMPAT=( python3_{8..10} )
DISTUTILS_USE_SETUPTOOLS=bdepend
inherit distutils-r1

DESCRIPTION="Nose plugin to facilitate randomized unit testing"
HOMEPAGE="https://github.com/fzumstein/nose-random"
SRC_URI="https://github.com/fzumstein/${PN}/archive/${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="MIT"
SLOT="0"
KEYWORDS="amd64 ~arm ~arm64 ~riscv x86"

RDEPEND="dev-python/nose[${PYTHON_USEDEP}]"

# no tests
