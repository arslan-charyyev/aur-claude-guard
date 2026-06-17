# aur-claude-guard — review AUR build scripts with claude before yay builds them.
# Sourced from ~/.bashrc. Wraps `yay` so any install/upgrade that pulls AUR
# packages is gated on `aur-claude-review`. Fails CLOSED.
#
# Bypass once:   AURGUARD=off yay -S somepkg
# Disable cache: AUR_REVIEW_NO_CACHE=1 yay -S somepkg

_aurguard_should_gate() {
  # 0 (gate) only for sync operations that actually build/install.
  local a op=0 readonly=0
  for a in "$@"; do
    case "$a" in
      --) break ;;
      --sync) op=1 ;;
      --search|--info|--list|--clean*|--print*|--groups|--sysupgrade=*) readonly=1 ;;
      -Q*|-R*|-F*|-U*|-D*|-T*|-V|--version|-h|--help) readonly=1 ;;
      -*S*)
        case "$a" in
          *s*|*i*|*p*|*c*|*g*|*l*) readonly=1 ;;  # -Ss -Si -Sp -Sc -Sg -Sl: no build
          *) op=1 ;;
        esac ;;
    esac
  done
  [ "$op" = 1 ] && [ "$readonly" = 0 ]
}

_aurguard_candidates() {
  # Print candidate AUR target names: bare (non-flag) args, plus pending AUR
  # updates when this is an upgrade. aur-claude-review ignores non-AUR names.
  local a upgrade=0
  for a in "$@"; do
    case "$a" in
      --) break ;;
      -*S*u*|--sysupgrade) upgrade=1 ;;
    esac
  done
  for a in "$@"; do
    case "$a" in
      --) break ;;
      -*) ;;                       # flag
      *) printf '%s\n' "$a" ;;     # bare target
    esac
  done
  if [ "$upgrade" = 1 ]; then
    command yay -Qua 2>/dev/null | awk '{print $1}'
  fi
}

yay() {
  if [ "${AURGUARD:-on}" = "off" ] || ! _aurguard_should_gate "$@"; then
    command yay "$@"; return $?
  fi

  local cands
  cands="$(_aurguard_candidates "$@" | awk 'NF && !seen[$0]++')"
  if [ -z "$cands" ]; then
    command yay "$@"; return $?   # nothing AUR to review (e.g. plain -Sy)
  fi

  printf '\033[36m🛡  aur-guard: reviewing AUR build scripts with claude before build...\033[0m\n' >&2
  # shellcheck disable=SC2086
  aur-claude-review $cands >/dev/null
  local rc=$?

  if [ "$rc" = 0 ]; then
    printf '\033[32m🛡  aur-guard: review PASSED — proceeding.\033[0m\n' >&2
    command yay "$@"; return $?
  fi

  if [ "$rc" = 1 ]; then
    printf '\033[31m🛑 aur-guard: review FAILED — a package was flagged as suspicious. Aborting.\033[0m\n' >&2
    printf '\033[2m   Inspect manually, then override with:  AURGUARD=off yay %s\033[0m\n' "$*" >&2
    return 1
  fi

  # rc=2: review could not complete (claude down, parse error, etc.). Fail closed,
  # but let an interactive user make the call.
  printf '\033[33m⚠  aur-guard: review could NOT complete (fail-closed).\033[0m\n' >&2
  if [ -t 0 ]; then
    local ans
    read -r -p "   Proceed with install WITHOUT a clean review? [y/N] " ans
    case "$ans" in
      [yY]|[yY][eE][sS]) command yay "$@"; return $? ;;
    esac
  fi
  printf '\033[31m🛑 aur-guard: aborting (override with AURGUARD=off).\033[0m\n' >&2
  return 1
}
