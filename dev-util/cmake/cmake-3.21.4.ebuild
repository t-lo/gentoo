# Copyright 1999-2021 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

CMAKE_MAKEFILE_GENERATOR="emake" # TODO RunCMake.LinkWhatYouUse fails consistently w/ ninja
CMAKE_REMOVE_MODULES_LIST=( none )
inherit bash-completion-r1 cmake elisp-common flag-o-matic multiprocessing \
	toolchain-funcs virtualx xdg-utils

MY_P="${P/_/-}"

DESCRIPTION="Cross platform Make"
HOMEPAGE="https://cmake.org/"
SRC_URI="https://cmake.org/files/v$(ver_cut 1-2)/${MY_P}.tar.gz"

LICENSE="CMake"
SLOT="0"
[[ "${PV}" = *_rc* ]] || \
KEYWORDS="~alpha amd64 ~arm ~arm64 ~hppa ~ia64 ~m68k ~mips ~ppc ~ppc64 ~riscv ~s390 ~sparc ~x86 ~amd64-linux ~x86-linux ~ppc-macos ~x64-macos ~sparc-solaris ~sparc64-solaris ~x64-solaris ~x86-solaris"
IUSE="doc emacs ncurses qt5 test"
RESTRICT="!test? ( test )"

RDEPEND="
	>=app-arch/libarchive-3.3.3:=
	app-crypt/rhash
	>=dev-libs/expat-2.0.1
	>=dev-libs/jsoncpp-1.9.2-r2:0=
	>=dev-libs/libuv-1.10.0:=
	>=net-misc/curl-7.21.5[ssl]
	sys-libs/zlib
	virtual/pkgconfig
	emacs? ( >=app-editors/emacs-23.1:* )
	ncurses? ( sys-libs/ncurses:0= )
	qt5? (
		dev-qt/qtcore:5
		dev-qt/qtgui:5
		dev-qt/qtwidgets:5
	)
"
DEPEND="${RDEPEND}"
BDEPEND="
	doc? (
		dev-python/requests
		dev-python/sphinx
	)
	test? ( app-arch/libarchive[zstd] )
"

S="${WORKDIR}/${MY_P}"

SITEFILE="50${PN}-gentoo.el"

PATCHES=(
	# prefix
	"${FILESDIR}"/${PN}-3.16.0_rc4-darwin-bundle.patch
	"${FILESDIR}"/${PN}-3.14.0_rc3-prefix-dirs.patch
	"${FILESDIR}"/${PN}-3.19.1-darwin-gcc.patch

	# handle gentoo packaging in find modules
	"${FILESDIR}"/${PN}-3.17.0_rc1-FindBLAS.patch
	# Next patch needs to be reworked
	#"${FILESDIR}"/${PN}-3.17.0_rc1-FindLAPACK.patch
	"${FILESDIR}"/${PN}-3.5.2-FindQt4.patch

	# respect python eclasses
	"${FILESDIR}"/${PN}-2.8.10.2-FindPythonLibs.patch
	"${FILESDIR}"/${PN}-3.9.0_rc2-FindPythonInterp.patch

	"${FILESDIR}"/${PN}-3.18.0-filter_distcc_warning.patch # bug 691544

	# upstream fixes (can usually be removed with a version bump)
)

cmake_src_bootstrap() {
	# disable running of cmake in bootstrap command
	sed -i \
		-e '/"${cmake_bootstrap_dir}\/cmake"/s/^/#DONOTRUN /' \
		bootstrap || die "sed failed"

	# execinfo.h on Solaris isn't quite what it is on Darwin
	if [[ ${CHOST} == *-solaris* ]] ; then
		sed -i -e 's/execinfo\.h/blablabla.h/' \
			Source/kwsys/CMakeLists.txt || die
	fi

	# bootstrap script isn't exactly /bin/sh compatible
	tc-env_build ${CONFIG_SHELL:-sh} ./bootstrap \
		--prefix="${T}/cmakestrap/" \
		--parallel=$(makeopts_jobs "${MAKEOPTS}" "$(get_nproc)") \
		|| die "Bootstrap failed"
}

cmake_src_test() {
	# fix OutDir and SelectLibraryConfigurations tests
	# these are altered thanks to our eclass
	sed -i -e 's:^#_cmake_modify_IGNORE ::g' \
		"${S}"/Tests/{OutDir,CMakeOnly/SelectLibraryConfigurations}/CMakeLists.txt \
		|| die

	pushd "${BUILD_DIR}" > /dev/null

	local ctestargs
	[[ -n ${TEST_VERBOSE} ]] && ctestargs="--extra-verbose --output-on-failure"

	# Excluded tests:
	#    BootstrapTest: we actually bootstrap it every time so why test it.
	#    BundleUtilities: bundle creation broken
	#    CMakeOnly.AllFindModules: pthread issues
	#    CTest.updatecvs: fails to commit as root
	#    Fortran: requires fortran
	#    RunCMake.CompilerLauncher: also requires fortran
	#    RunCMake.CPack_RPM: breaks if app-arch/rpm is installed because
	#        debugedit binary is not in the expected location
	#    RunCMake.CPack_DEB: breaks if app-arch/dpkg is installed because
	#        it can't find a deb package that owns libc
	#    RunCMake.{IncompatibleQt,ObsoleteQtMacros}: Require Qt4
	#    TestUpload: requires network access
	"${BUILD_DIR}"/bin/ctest \
		-j "$(makeopts_jobs)" \
		--test-load "$(makeopts_loadavg)" \
		${ctestargs} \
		-E "(BootstrapTest|BundleUtilities|ConfigSources|CMakeOnly.AllFindModules|CPackComponentsDEB-components-depend2|CompileOptions|CTest.UpdateCVS|DependencyGraph|Fortran|RunCMake.CompilerLauncher|RunCMake.IncompatibleQt|RunCMake.ObsoleteQtMacros|RunCMake.PrecompileHeaders|RunCMake.CPack_(DEB|RPM)|TestUpload)" \
		|| die "Tests failed"

	popd > /dev/null
}

src_prepare() {
	cmake_src_prepare

	if [[ ${CHOST} == *-darwin* ]] ; then
		# disable Xcode hooks, bug #652134
		sed -i -e 's/cm\(\|Global\|Local\)XCode[^.]\+\.\(cxx\|h\)//' \
			Source/CMakeLists.txt || die
		sed -i -e '/define CMAKE_USE_XCODE/s/XCODE/NO_XCODE/' \
			-e '/cmGlobalXCodeGenerator.h/d' \
			Source/cmake.cxx || die
		# disable isysroot usage with GCC, we've properly instructed
		# where things are via GCC configuration and ldwrapper
		sed -i -e '/cmake_gnu_set_sysroot_flag/d' \
			Modules/Platform/Apple-GNU-*.cmake || die
		# disable isysroot usage with clang as well
		sed -i -e '/_SYSROOT_FLAG/d' \
			Modules/Platform/Apple-Clang.cmake || die
		# don't set a POSIX standard, system headers don't like that, #757426
		sed -i -e 's/^#if !defined(_WIN32) && !defined(__sun)/& \&\& !defined(__APPLE__)/' \
			Source/cmLoadCommandCommand.cxx \
			Source/cmStandardLexer.h \
			Source/cmSystemTools.cxx \
			Source/cmTimestamp.cxx
		sed -i -e 's/^#if !defined(_POSIX_C_SOURCE) && !defined(_WIN32) && !defined(__sun)/& \&\& !defined(__APPLE__)/' \
			Source/cmStandardLexer.h
	fi

	# Add gcc libs to the default link paths
	sed -i \
		-e "s|@GENTOO_PORTAGE_GCCLIBDIR@|${EPREFIX}/usr/${CHOST}/lib/|g" \
		-e "$(usex prefix-guest "s|@GENTOO_HOST@||" "/@GENTOO_HOST@/d")" \
		-e "s|@GENTOO_PORTAGE_EPREFIX@|${EPREFIX}/|g" \
		Modules/Platform/{UnixPaths,Darwin}.cmake || die "sed failed"
	if ! has_version -b \>=${CATEGORY}/${PN}-3.4.0_rc1 || ! cmake --version &>/dev/null ; then
		CMAKE_BINARY="${S}/Bootstrap.cmk/cmake"
		cmake_src_bootstrap
	fi
}

src_configure() {
	# Fix linking on Solaris
	[[ ${CHOST} == *-solaris* ]] && append-ldflags -lsocket -lnsl

	local mycmakeargs=(
		-DCMAKE_USE_SYSTEM_LIBRARIES=ON
		-DCMAKE_DOC_DIR=/share/doc/${PF}
		-DCMAKE_MAN_DIR=/share/man
		-DCMAKE_DATA_DIR=/share/${PN}
		-DSPHINX_MAN=$(usex doc)
		-DSPHINX_HTML=$(usex doc)
		-DBUILD_CursesDialog="$(usex ncurses)"
		-DBUILD_TESTING=$(usex test)
	)
	use qt5 && mycmakeargs+=( -DBUILD_QtDialog=ON )

	cmake_src_configure
}

src_compile() {
	cmake_src_compile
	use emacs && elisp-compile Auxiliary/cmake-mode.el
}

src_test() {
	virtx cmake_src_test
}

src_install() {
	cmake_src_install

	if use emacs; then
		elisp-install ${PN} Auxiliary/cmake-mode.el Auxiliary/cmake-mode.elc
		elisp-site-file-install "${FILESDIR}/${SITEFILE}"
	fi

	insinto /usr/share/vim/vimfiles/syntax
	doins Auxiliary/vim/syntax/cmake.vim

	insinto /usr/share/vim/vimfiles/indent
	doins Auxiliary/vim/indent/cmake.vim

	insinto /usr/share/vim/vimfiles/ftdetect
	doins "${FILESDIR}/${PN}.vim"

	dobashcomp Auxiliary/bash-completion/{${PN},ctest,cpack}
}

pkg_postinst() {
	use emacs && elisp-site-regen
	if use qt5; then
		xdg_icon_cache_update
		xdg_desktop_database_update
		xdg_mimeinfo_database_update
	fi
}

pkg_postrm() {
	use emacs && elisp-site-regen
	if use qt5; then
		xdg_icon_cache_update
		xdg_desktop_database_update
		xdg_mimeinfo_database_update
	fi
}
