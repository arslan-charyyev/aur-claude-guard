# aur-claude-guard — review AUR build scripts with claude before yay builds them.
# Sourced from ~/.bashrc. Wraps `yay` so any install/upgrade that pulls AUR
# packages is gated on `aur-claude-review`. Fails CLOSED.
#
# Bypass once:   AURGUARD=off yay -S somepkg
# Disable cache: AUR_REVIEW_NO_CACHE=1 yay -S somepkg
# Skip sudo pre-auth: AURGUARD_SUDO_PRIME=0 yay -S somepkg

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

_aurguard_sudo_bin() {
  if [ -n "${AURGUARD_SUDO:-}" ]; then printf '%s\n' "$AURGUARD_SUDO"; return 0; fi
  command -v sudo >/dev/null 2>&1 && { printf 'sudo\n'; return 0; }
  command -v doas >/dev/null 2>&1 && { printf 'doas\n'; return 0; }
  return 1
}

_aurguard_sudo_prime() {
  # Ask for the root password BEFORE the (slow) review, so `yay -Syu` can be
  # started and walked away from: the review runs while the credentials are
  # already cached, and yay's own sudo call later finds a live timestamp.
  # Never fatal — if this fails, yay just prompts on its own schedule.
  _AURGUARD_SUDO_BIN=
  [ "${AURGUARD_SUDO_PRIME:-1}" = 1 ] || return 0
  [ "$(id -u)" != 0 ] || return 0
  local sudo_bin
  sudo_bin="$(_aurguard_sudo_bin)" || return 0

  printf '\033[36m🛡  aur-guard: authenticating first, so the review can run unattended...\033[0m\n' >&2
  case "${sudo_bin##*/}" in
    doas) "$sudo_bin" true >/dev/null 2>&1 ;;   # doas has no `-v`
    *)    "$sudo_bin" -v ;;
  esac || {
    printf '\033[33m⚠  aur-guard: could not pre-authenticate; yay may prompt for a password later.\033[0m\n' >&2
    return 0
  }
  _AURGUARD_SUDO_BIN="$sudo_bin"
}

_aurguard_keepalive_start() {
  # Refresh the sudo timestamp while the review runs, so a review longer than
  # timestamp_timeout doesn't hand yay an expired credential. Bounded (~50 min)
  # so an interrupted review can never leave a loop running forever.
  _AURGUARD_KEEPALIVE_PID=
  [ -n "${_AURGUARD_SUDO_BIN:-}" ] || return 0
  case "${_AURGUARD_SUDO_BIN##*/}" in doas) return 0 ;; esac  # no non-interactive refresh
  local bin="$_AURGUARD_SUDO_BIN"
  (
    # `sleep` runs as a child, so trap TERM and take it down with us — otherwise
    # a stray sleep lingers for a full interval after the review finishes.
    sp=; trap 'kill "$sp" 2>/dev/null; exit 0' TERM
    i=0
    while [ "$i" -lt 60 ]; do
      sleep 50 & sp=$!; wait "$sp"
      "$bin" -n -v >/dev/null 2>&1 || exit 0
      i=$((i+1))
    done
  ) &
  _AURGUARD_KEEPALIVE_PID=$!
  disown "$_AURGUARD_KEEPALIVE_PID" 2>/dev/null
}

_aurguard_keepalive_stop() {
  [ -n "${_AURGUARD_KEEPALIVE_PID:-}" ] || return 0
  kill "$_AURGUARD_KEEPALIVE_PID" 2>/dev/null
  _AURGUARD_KEEPALIVE_PID=
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

  _aurguard_sudo_prime

  printf '\033[36m🛡  aur-guard: reviewing AUR build scripts with claude before build...\033[0m\n' >&2
  _aurguard_keepalive_start
  # shellcheck disable=SC2086
  aur-claude-review $cands >/dev/null
  local rc=$?
  _aurguard_keepalive_stop

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
