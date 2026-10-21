# aur-claude-guard — the makepkg gate.
#
# makepkg sources this file through /etc/makepkg.conf.d/aur-claude-guard.conf
# while it loads its configuration, which is before it reads the PKGBUILD. So
# the build files are reviewed before any of their code runs, whichever tool
# starts makepkg: yay, paru, Pamac, or a manual run. A build without a PASS
# verdict stops here. Fails closed.
#
# Bypass once:  AURGUARD=off yay -S somepkg
#
# Writes only to stderr: Pamac and yay parse the stdout of --printsrcinfo and
# --packagelist. Runs inside makepkg's shell, which has an ERR trap that aborts
# makepkg: every command that can fail must sit in a condition or an || list.

_aurguard_gate() {
	# Only a top-level makepkg run by a normal user. makepkg re-runs itself
	# under fakeroot for package(), and that re-run belongs to a build that was
	# already gated. makepkg refuses root right after it loads this file.
	[[ ${0##*/} == makepkg ]] || return 0
	(( ! ${INFAKEROOT:-0} )) || return 0
	(( EUID != 0 )) || return 0

	# makepkg requires the PKGBUILD in the working directory.
	local dir=${startdir:-$PWD} top url rc=0 ans qdir

	# Skip the clone of a non-AUR repository, such as an official package from
	# gitlab.archlinux.org or this project. Review everything else: AUR clones
	# (yay, paru, Pamac), AUR snapshot tarballs, and loose PKGBUILDs.
	if top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) && [[ $top -ef $dir ]]; then
		url=$(git -C "$dir" remote get-url origin 2>/dev/null) || url=
		if [[ -n $url && $url != *[@/]aur.archlinux.org[/:]* ]]; then
			return 0
		fi
	fi

	if [[ ${AURGUARD:-on} == off ]]; then
		warning "aur-guard: review skipped (AURGUARD=off)"
		return 0
	fi

	msg "aur-guard: reviewing the build files with claude..." >&2
	aur-claude-review --dir "$dir" >/dev/null || rc=$?
	case $rc in
		0)
			msg2 "aur-guard: review passed" >&2
			return 0 ;;
		1)
			error "aur-guard: review FAILED, the build files were flagged as suspicious."
			plainerr "    Inspect them, then bypass once with: AURGUARD=off <command>"
			exit 1 ;;
	esac

	# The review could not complete (claude down, no verdict, ...). A user at a
	# terminal can make the call. Pamac gives makepkg no terminal, so it stops.
	error "aur-guard: the review could not complete (fail-closed)."
	if [[ -t 0 && -t 2 && " ${ARGLIST[*]} " != *" --noconfirm "* ]]; then
		read -r -p "    Build WITHOUT a clean review? [y/N] " ans || ans=
		if [[ $ans == [yY] || $ans == [yY][eE][sS] ]]; then
			return 0
		fi
	fi
	# Pamac shows only this text, and AURGUARD=off cannot reach its window or
	# tray: they started before the variable was set. So list each way out.
	printf -v qdir %q "$dir"
	plainerr "    The claude output above gives the reason. If claude is logged out, run:"
	plainerr "        claude auth login"
	plainerr "    Then retry the update."
	plainerr "    To build without the review this time, run one of these in a terminal:"
	plainerr "        AURGUARD=off pamac update -a"
	plainerr "        AURGUARD=off yay -Syu"
	plainerr "        cd $qdir && AURGUARD=off makepkg -si"
	exit 1
}

_aurguard_gate
unset -f _aurguard_gate
