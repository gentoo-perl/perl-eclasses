# Copyright 1999-2015 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Id$

# @ECLASS: perl-functions.eclass
# @MAINTAINER:
# perl@gentoo.org
# @AUTHOR:
# Seemant Kulleen <seemant@gentoo.org>
# Andreas K. Huettel <dilfridge@gentoo.org>
# @BLURB: helper functions eclass for perl modules
# @DESCRIPTION:
# The perl-functions eclass is designed to allow easier installation of perl
# modules, and their incorporation into the Gentoo Linux system.
# It provides helper functions, no phases or variable manipulation in
# global scope.

[[ ${CATEGORY} == "perl-core" ]] && inherit alternatives

case "${EAPI:-0}" in
	5|6)
		;;
	*)
		die "EAPI=${EAPI} is not supported by perl-functions.eclass"
		;;
esac

perl_diagnostics() {
	local d
	d=${T}/perl-diagnostics.log
	[[ -e ${d} ]] && return
	: > $d

	{
		echo "perl: $(type -p perl)"
		echo
		echo "ENV values:"
		env | grep -E '^(PERL|HOME=|MANPATH|PATH|TEST|GENTOO_PERL)'
		echo
		echo "perl -V:"
		perl -V 2>&1
		echo
		if type -p perl-info 2>/dev/null ; then
			echo "perl-info output:"
			echo
			perl-info
			echo
		fi
		echo "Corelist Versions:"
		perl -MModule::CoreList -e 'for $mod ( Module::CoreList->find_modules(qr/^/) ) { eval "require $mod; print q[$mod : ] . \$${mod}::VERSION . qq[\n]; 1" or print qq{\e[31mNA: $mod\e[0m\n};}'
	} >> $d

	eerror
	eerror "-- Gentoo Perl Team specific bug reporting request --"
	eerror "Please attach the contents of the following file with your bug report:"
	eerror " $d"
	eerror
}

perl_check_module_version() {
	local REAL_PV
	local gpmv="$(type -p gentoo-perlmod-version.pl)"
	[[ -n ${MODULE_VERSION} && -n ${gpmv} && -x ${gpmv} ]] || return
	REAL_PV=$( ${gpmv} --oneshot "${MODULE_VERSION}" )
	if [[ -n ${REAL_PV} && ${REAL_PV} != ${PV} ]] ; then
		eqawarn "QA Notice: Based on MODULE_VERSION=${MODULE_VERSION} the ebuild version ${PV} is wrong!"
		eqawarn "           The ebuild version should be ${REAL_PV}"
		perl_qafatal "version" "${REAL_PV} != ${PV}"
	fi
}

perlinfo_done=false

# @FUNCTION: perl_set_version
# @USAGE: perl_set_version
# @DESCRIPTION:
# Extract version information and installation paths from the current Perl 
# interpreter. 
#
# This sets the following variables: PERL_VERSION, SITE_ARCH, SITE_LIB, 
# ARCH_LIB, VENDOR_LIB, VENDOR_ARCH
#
# This function used to be called perlinfo as well.
perl_set_version() {
	debug-print-function $FUNCNAME "$@"
	debug-print "$FUNCNAME: perlinfo_done=${perlinfo_done}"
	${perlinfo_done} && return 0
	perlinfo_done=true

	perl_check_module_version

	local f version install{{site,vendor}{arch,lib},archlib}
	eval "$(perl -V:{version,install{{site,vendor}{arch,lib},archlib}} )"
	PERL_VERSION=${version}
	SITE_ARCH=${installsitearch}
	SITE_LIB=${installsitelib}
	ARCH_LIB=${installarchlib}
	VENDOR_LIB=${installvendorlib}
	VENDOR_ARCH=${installvendorarch}
}

# @FUNCTION: perl_delete_localpod
# @USAGE: perl_delete_localpod
# @DESCRIPTION:
# Remove stray perllocal.pod files in the temporary install directory D.
#
# This function used to be called fixlocalpod as well.
perl_delete_localpod() {
	debug-print-function $FUNCNAME "$@"

	find "${D}" -type f -name perllocal.pod -delete
	find "${D}" -depth -mindepth 1 -type d -empty -delete
}

# @FUNCTION: perl_fix_osx_extra
# @USAGE: perl_fix_osx_extra
# @DESCRIPTION:
# Look through ${S} for AppleDouble encoded files and get rid of them.
perl_fix_osx_extra() {
	debug-print-function $FUNCNAME "$@"

	# Remove "AppleDouble encoded Macintosh file"
	local f
	find "${S}" -type f -name "._*" -print0 | while read -rd '' f ; do
		einfo "Removing AppleDouble encoded Macintosh file: ${f#${S}/}"
		rm -f "${f}"
		f=${f#${S}/}
	#	f=${f//\//\/}
	#	f=${f//\./\.}
	#	sed -i "/${f}/d" "${S}"/MANIFEST || die
		grep -q "${f}" "${S}"/MANIFEST && \
			elog "AppleDouble encoded Macintosh file in MANIFEST: ${f#${S}/}"
	done
}

# @FUNCTION: perl_delete_module_manpages
# @USAGE: perl_delete_module_manpages
# @DESCRIPTION:
# Bump off manpages installed by the current module such as *.3pm files as well
# as empty directories.
perl_delete_module_manpages() {
	debug-print-function $FUNCNAME "$@"

	if [[ -d "${ED}"/usr/share/man ]] ; then
#		einfo "Cleaning out stray man files"
		find "${ED}"/usr/share/man -type f -name "*.3pm" -delete
		find "${ED}"/usr/share/man -depth -type d -empty -delete
	fi
}

# @FUNCTION: perl_delete_packlist
# @USAGE: perl_delete_packlist
# @DESCRIPTION:
# Look through ${D} for .packlist files, empty .bs files and empty directories,
# and get rid of items found.
perl_delete_packlist() {
	debug-print-function $FUNCNAME "$@"
	perl_set_version
	if [[ -d ${D}/${VENDOR_ARCH} ]] ; then
		find "${D}/${VENDOR_ARCH}" -type f -a -name .packlist -delete
		perl_delete_emptybsdir
	fi
}

# @FUNCTION: perl_delete_emptybsdir
# @USAGE: perl_delete_emptybsdir
# @DESCRIPTION:
# Look through ${D} for empty .bs files and empty directories,
# and get rid of items found.
perl_delete_emptybsdir() {
	debug-print-function $FUNCNAME "$@"
	perl_set_version
	if [[ -d ${D}/${VENDOR_ARCH} ]] ; then
		find "${D}/${VENDOR_ARCH}" -type f \
			-a -name '*.bs' -a -empty -delete
		find "${D}" -depth -mindepth 1 -type d -empty -delete
	fi
}

# @FUNCTION: perl_fix_packlist
# @USAGE: perl_fix_packlist
# @DESCRIPTION:
# Look through ${D} for .packlist text files containing the temporary installation
# folder (i.e. ${D}). If the pattern is found, silently replace it with `/'.
# Remove duplicate entries; then validate all entries in the packlist against ${D}
# and prune entries that do not correspond to installed files.
perl_fix_packlist() {
	debug-print-function $FUNCNAME "$@"

	local packlist_temp="${T}/.gentoo_packlist_temp"
	find "${D}" -type f -name '.packlist' -print0 | while read -rd '' f ; do
		if file "${f}" | grep -q -i " text" ; then
                        einfo "Fixing packlist file /${f#${D}}"

			# remove the temporary build dir path
			sed -i -e "s:${D}:/:g" "${f}"

			# remove duplicate entries
			sort -u "${f}" > "${packlist_temp}"
			mv "${packlist_temp}" "${f}"

			# remove files that dont exist
			cat "${f}" | while read -r entry; do
				if [ ! -e "${D}/${entry}" ]; then
					einfo "Pruning surplus packlist entry ${entry}"
					grep -v -x -F "${entry}" "${f}" > "${packlist_temp}"
					mv "${packlist_temp}" "${f}"
				fi
			done
		fi
	done
}

# @FUNCTION: perl_remove_temppath
# @USAGE: perl_remove_temppath
# @DESCRIPTION:
# Look through ${D} for text files containing the temporary installation
# folder (i.e. ${D}). If the pattern is found, replace it with `/' and warn.
perl_remove_temppath() {
	debug-print-function $FUNCNAME "$@"

	find "${D}" -type f -not -name '*.so' -print0 | while read -rd '' f ; do
		if file "${f}" | grep -q -i " text" ; then
			grep -q "${D}" "${f}" && ewarn "QA: File contains a temporary path ${f}"
			sed -i -e "s:${D}:/:g" "${f}"
		fi
	done
}

# @FUNCTION: perl_rm_files
# @USAGE: perl_rm_files "file_1" "file_2"
# @DESCRIPTION:
# Remove certain files from a Perl release and remove them from the MANIFEST
# while we're there.
#
# Most useful in src_prepare for nuking bad tests, and is highly recommended
# for any tests like 'pod.t', 'pod-coverage.t' or 'kwalitee.t', as what they
# test is completely irrelevant to end users, and frequently fail simply
# because the authors of Test::Pod... changed their recommendations, and thus
# failures are only useful feedback to Authors, not users.
#
# Removing from MANIFEST also avoids needless log messages warning
# users about files "missing from their kit".
perl_rm_files() {
	debug-print-function $FUNCNAME "$@"
	local skipfile="${T}/.gentoo_makefile_skip"
	local manifile="${S}/MANIFEST"
	local manitemp="${T}/.gentoo_manifest_temp"
	oldifs="$IFS"
	IFS="\n"
	for filename in "$@"; do
		einfo "Removing un-needed ${filename}";
		# Remove the file
		rm -f "${S}/${filename}"
		[[ -e "${manifile}" ]] && echo "${filename}" >> "${skipfile}"
	done
	if [[ -e "${manifile}" && -e "${skipfile}" ]]; then
		einfo "Fixing Manifest"
		grep -v -F -f "${skipfile}" "${manifile}" > "${manitemp}"
		mv -f -- "${manitemp}" "${manifile}"
		rm -- "${skipfile}";
	fi
	IFS="$oldifs"
}

# @FUNCTION: perl_link_duallife_scripts
# @USAGE: perl_link_duallife_scripts
# @DESCRIPTION:
# Moves files and generates symlinks so dual-life packages installing scripts do not
# lead to file collisions. Mainly for use in pkg_postinst and pkg_postrm, and makes 
# only sense for perl-core packages.
perl_link_duallife_scripts() {
	debug-print-function $FUNCNAME "$@"
	if [[ ${CATEGORY} != perl-core ]] || ! has_version ">=dev-lang/perl-5.8.8-r8" ; then
		return 0
	fi

	local i ff execdir mandir

	execdir="usr/share/perl-${P}/bin"
	mandir="usr/share/perl-${P}/man/man1"

	if has "${EBUILD_PHASE:-none}" "postinst" "postrm" ; then
		for i in "${DUALLIFESCRIPTS[@]}" ; do
			alternatives_auto_makesym "/${i}-${PV}"	"${EROOT}${execdir}/${i##*/}"
			alternatives_auto_makesym "/${i}" "/${i}-[0-9]*"
		done
		for i in "${DUALLIFEMAN[@]}" ; do
			# Expand $i to a full path as it was installed,
			# which may add .gz or whatever to the end during compress.
			# then boil it till you just get ".gz"
			ff="${EROOT}${mandir}/${i##*/}";
			ff=$( echo ${ff%.1}.1* );
			ff=${ff##*.1}
			alternatives_auto_makesym "/${i%.1}-${PV}.1${ff}" "${EROOT}${mandir}/${i##*/}${ff}"
			alternatives_auto_makesym "/${i}${ff}" "/${i%.1}-[0-9]*.1${ff}"
		done
	else
		pushd "${ED}" > /dev/null
		for i in $(find usr/bin -maxdepth 1 -type f 2>/dev/null) ; do
			mkdir -p "${D}/${execdir}" || die
			mv ${i} "${D}/${execdir}/${i##*/}" || die
			#DUALLIFESCRIPTS[${#DUALLIFESCRIPTS[*]}]=${i##*/}
			DUALLIFESCRIPTS[${#DUALLIFESCRIPTS[*]}]=${i}
		done
		for i in $(find usr/share/man/man1 -maxdepth 1 -type f 2>/dev/null) ; do
			mkdir -p "${D}/${mandir}" || die
			mv ${i} "${D}/${mandir}/${i##*/}" || die
			DUALLIFEMAN[${#DUALLIFEMAN[*]}]=${i}
		done

		einfo "Cleaning empty directories"
		perl_trim_empty_dirs "${EROOT}/usr/bin"

		popd > /dev/null
	fi
}

# @FUNCTION: perl_qafatal
# @USAGE: perl_qafatal TYPE "Die reason"
# @DESCRIPTION:
# Invoking this method after eqawarn's allows an entry point for the eclass to trigger
# a fatal exit if the user has PERL_QAFATAL set.
#
# The value TYPE will be used to optionally allow the user to filter certain QA Types.
# TYPE = eapi 		 	 : Legacy EAPI warnings
# TYPE = modulebuild 	 : Failure to include Module-Build as a dependency.
# TYPE = modulebuildtiny : Failure to include Module-Build-Tiny as a dependency
# TYPE = function    	 : Use of a deprecated function
# TYPE = version     	 : version and expected version missmatch
#
# PERL_QAFATAL:
#  == "1" 		- Fatal for all types
#  has "all" 	- Fatal for all types
#  has "$type" 	- Fatal for "$type"
perl_qafatal() {
	local failtype=$1
	local failreason=$2
	if [[ "${PERLQAFATAL:-0}" == 1 ]]; then
		eerror "Bailing out due to PERLQAFATAL including $failtype (==1)";
		die "$failtype: $failreason"
	fi
	if has 'all' ${PERLQAFATAL}; then
		eerror "Bailing out due to PERLQAFATAL including $failtype (all)";
		die "$failtype: $failreason"
	fi
	if has $failtype ${PERLQAFATAL}; then
		eerror "Bailing out due to PERLQAFATAL including $1";
		die "$failtype: $failreason"
	fi
}

# @FUNCTION: perl_check_env
# @USAGE: perl_check_env
# @DESCRIPTION:
# Checks a blacklist of known-suspect ENV values that can be accidentally set by users
# doing personal perl work, which may accidentally leak into portage and break the
# system perl installaton.
# Dies if any of the suspect fields are found, and tell the user what needs to be unset.
# There's a workaround, but you'll have to read the code for it.
perl_check_env() {
	local errored value;

	for i in PERL_MM_OPT PERL5LIB PERL5OPT PERL_MB_OPT PERL_CORE PERLPREFIX; do
		# Next unless match
		[ -v $i ] || continue;

		# Warn only once, and warn only when one of the bad values are set.
		# record failure here.
		if [ ${errored:-0} == 0 ]; then
			if [ -n "${I_KNOW_WHAT_I_AM_DOING}" ]; then
				elog "perl-module.eclass: Suspicious environment values found.";
			else
				eerror "perl-module.eclass: Suspicious environment values found.";
			fi
		fi
		errored=1

		# Read ENV Value
		eval "value=\$$i";

		# Print ENV name/value pair
		if [ -n "${I_KNOW_WHAT_I_AM_DOING}" ]; then
			elog "    $i=\"$value\"";
		else
			eerror "    $i=\"$value\"";
		fi
	done

	# Return if there were no failures
	[ ${errored:-0} == 0 ] && return;

	# Return if user knows what they're doing
	if [ -n "${I_KNOW_WHAT_I_AM_DOING}" ]; then
		elog "Continuing anyway, seems you know what you're doing."
		return
	fi

	eerror "Your environment settings may lead to undefined behavior and/or build failures."
	die "Please fix your environment ( ~/.bashrc, package.env, ... ), see above for details."
}

# @FUNCTION: perl_doexamples
# @USAGE: perl_doexamples "file_1" "file_2"
# @DESCRIPTION:
# Install example files ready-to-run.
# Is called under certain circumstances in perl-module.eclass src_install
# (see the documentation there).
#
perl_doexamples() {
	debug-print-function $FUNCNAME "$@"

	einfo "Installing examples into /usr/share/doc/${PF}/examples"

	# no compression since we want ready-to-run scripts
	docompress -x /usr/share/doc/${PF}/examples

	docinto examples/
	dodoc -r $@

	# is there a way to undo "docinto" ?
}

# @FUNCTION: perl_check_eapi
# @USAGE: perl_check_eapi
# @DESCRIPTION:
# Checks a blacklist of known-suspect eclass variables which can be accidentally set
# by maintainers, or may be accidentally left residual after an EAPI change.
#
# Dies if any of the suspect fields are found, and tell the user that the ebuild in question
# is broken and needs a fix.
#
# There's a workaround, but you'll have to read the code for it.
perl_check_eapi() {
	local errored value;
	local suspect_vars=();

	# Secret sauce to inhibit this check
	[ -n "${_EAPI_PERL_MODULE_PERMISSIVE}" ] && return;

	if [[ ${EAPI:-0} == 5 ]]; then
		suspect_vars=( DIST_TEST DIST_VERSION DIST_NAME DIST_AUTHOR DIST_A_EXT DIST_A );
	else
		suspect_vars=( MY_PN MY_PV MODULE_VERSION MY_P MODULE_A MODULE_A_EXT MODULE_AUTHOR MODULE_NAME SRC_TEST );
	fi
	for i in "${suspect_vars[@]}"; do
		[ -v $i ] || continue;

		# Add heading once and only once
		if [ ${errored:-0} == 0 ]; then
			if [ -n "${I_KNOW_WHAT_I_AM_DOING}" ]; then
				elog "perl-module.eclass: Suspicious EAPI${EAPI:-0} eclass variables found.";
			else
				eerror "perl-module.eclass: Suspicious EAPI${EAPI:-0} eclass variables found.";
			fi
		fi

		errored=1

		eval "value=\$$i";
		# Print ENV name/value pair
		if [ -n "${I_KNOW_WHAT_I_AM_DOING}" ]; then
			elog "    $i=\"$value\"";
		else
			eerror "    $i=\"$value\"";
		fi
	done
	# Return if there were no failures
	[ ${errored:-0} == 0 ] && return;

	# Return if user knows what they're doing
	if [ -n "${I_KNOW_WHAT_I_AM_DOING}" ]; then
		elog "Continuing anyway, seems you know what you're doing."
		return
	fi

	eerror "Your ebuild/env contains eclass variables that are known invalid/legacy and indicate author oversight."
	die "Please file a bug for this ebuild as per above details."
}

pm_warned_override=0;
perl_dist_override() {
	[[ "${EAPI:-0}" == 5 ]] && return 1; # false => No overides possible
	if [[ -n "${DIST_TEST_OVERRIDE}" ]]; then
		[[ "${pm_warned_override}" != 1 ]] && ewarn "DIST_TEST_OVERRIDE is set to ${DIST_TEST_OVERRIDE}"
		pm_warned_override=1
		return 0; # true, overridden
	fi
	return 1;
}

pmqa_warned_notests=0;
perl_test_disabled() {
	local my_test_control;
	debug-print-function $FUNCNAME "$@"

	# RESTRICT=test == tests disabled
	has 'test' ${RESTRICT} && return 0; # true

	if [[ ${EAPI:-0} == 5 ]]; then
		# No SRC_TEST == tests run, this is the overlay
		# Tests should run by default like they do in EAPI6
		[ -v SRC_TEST ] || return 1; # false

		has 'do' 		${SRC_TEST} || return 1; # false
		has 'parallel' 	${SRC_TEST} || return 1; # false

		if [[ "${pmqa_warned_notests:-0}" != 1 ]]; then
			eqawarn "Tests disabled using empty SRC_TEST";
			eqawarn "Please use RESTRICT=test or nuke problem tests"
		fi
		pmqa_warned_notests=1
		return 0; # true
	fi

	# This is mostly so perl_test_disabled()
	# still returns the right result outside src_test()
	if in_iuse test && ! use test ; then
		return 0; # true
	fi
	# Both of these being unset == tests are enabled
	if [ ! -v DIST_TEST ] && [ ! -v DIST_TEST_OVERRIDE ]; then
		return 1; # false
	fi
	# The ability for users to disable all tests using DIST_TEST_OVERRIDE is clearly
	# a design defect.
	if perl_dist_override; then
		has 'do' 		${DIST_TEST_OVERRIDE} || return 1; # false ( tests enabled )
		has 'parallel' 	${DIST_TEST_OVERRIDE} || return 1; # false
		return 0; # true ( tests disabled )
	fi
	has 'do' 		${DIST_TEST} || return 1; # false ( tests enabled )
	has 'parallel' 	${DIST_TEST} || return 1; # false
	if [[ "${pmqa_warned_notests:-0}" != 1 ]]; then
		eqawarn "Tests disabled using empty DIST_TEST";
		eqawarn "Please use RESTRICT=test or nuke problem tests"
	fi
	pmqa_warned_notests=1
	return 1;
}

pm_warned_verbose=0
perl_test_verbose() {
	debug-print-function $FUNCNAME "$@"

	if [[ "${EAPI:-0}" == 5 ]]; then
		if ! has 0 "${TEST_VERBOSE:-0}"; then
			[[ "${pm_warned_verbose:-0}" != 1 ]] && "Enabled verbose testing due to TEST_VERBOSE=${TEST_VERBOSE}"
			pm_warned_verbose=1
			return 0; # true
		fi
		return 1; #false
	fi
	if perl_dist_override; then
		if has 'verbose' ${DIST_TEST_OVERRIDE}; then
			[[ "${pm_warned_verbose:-0}" != 1 ]] && "Enabled verbose testing due to DIST_TEST_OVERRIDE=verbose"
			pm_warned_verbose=1
			return 0; # true
		fi
		return 1; # false
	fi
	if has 'verbose' ${DIST_TEST}; then
		[[ "${pm_warned_verbose:-0}" != 1 ]] && "Enabled verbose testing due to DIST_TEST=verbose"
		pm_warned_verbose=1
		return 0; # true
	fi
	return 1; # false
}
