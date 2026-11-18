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
# --packagelist. Pamac does not show that stderr in its window: it sends it to
# the journal and shows only "Failed to generate <pkg> information". So without
# a terminal, a stopped build also sends a desktop notification with the reason. Runs inside makepkg's shell, which has an ERR trap that aborts
# makepkg: every command that can fail must sit in a condition or an || list.

# _aurguard_notify <summary> <body>: a desktop notification, only when makepkg
# has no terminal (Pamac). Best effort: no notify-send or no session bus is fine.
_aurguard_notify() {
	[[ ! -t 2 ]] || return 0
	command -v notify-send >/dev/null 2>&1 || return 0
	timeout 5 notify-send --app-name=aur-guard --urgency=critical \
		--icon=dialog-error -- "$1" "$2" >/dev/null 2>&1 || :
}

_aurguard_gate() {
	# Only a top-level makepkg run by a normal user. makepkg re-runs itself
	# under fakeroot for package(), and that re-run belongs to a build that was
	# already gated. makepkg refuses root right after it loads this file.
	[[ ${0##*/} == makepkg ]] || return 0
	(( ! ${INFAKEROOT:-0} )) || return 0
	(( EUID != 0 )) || return 0

	# makepkg requires the PKGBUILD in the working directory.
	local dir=${startdir:-$PWD} top url rc=0 ans qdir log= reason pkg
	pkg=${dir##*/}

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
	if [[ -t 2 ]]; then
		# A terminal shows the review's progress as it happens.
		aur-claude-review --dir "$dir" >/dev/null || rc=$?
	else
		# Keep the review's messages: the notification quotes the reason.
		log=$(aur-claude-review --dir "$dir" 2>&1 >/dev/null) || rc=$?
		[[ -z $log ]] || printf '%s\n' "$log" >&2
	fi
	case $rc in
		0)
			msg2 "aur-guard: review passed" >&2
			return 0 ;;
		1)
			error "aur-guard: review FAILED, the build files were flagged as suspicious."
			plainerr "    Inspect them, then bypass once with: AURGUARD=off <command>"
			_aurguard_notify "aur-guard blocked $pkg" \
				"The build files were flagged as suspicious. Read the review with: journalctl -b -e"
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
	# AURGUARD=off cannot reach the Pamac window or tray: they started before
	# the variable was set. So list each way out.
	printf -v qdir %q "$dir"
	plainerr "    The claude output above gives the reason. If claude is logged out, run:"
	plainerr "        claude auth login"
	plainerr "    Then retry the update."
	plainerr "    To build without the review this time, run one of these in a terminal:"
	plainerr "        AURGUARD=off pamac update -a"
	plainerr "        AURGUARD=off yay -Syu"
	plainerr "        cd $qdir && AURGUARD=off makepkg -si"
	# The review prints its reason last, for example the error from claude.
	reason=$(printf '%s\n' "$log" | grep -v '^[[:space:]]*$' | tail -n 1) || reason=
	_aurguard_notify "aur-guard could not review $pkg" \
		"${reason:-The review could not complete.}

If claude is logged out, run: claude auth login
Then retry the update. To skip the review once, run in a terminal: AURGUARD=off pamac update -a"
	exit 1
}

_aurguard_gate
unset -f _aurguard_gate _aurguard_notify
