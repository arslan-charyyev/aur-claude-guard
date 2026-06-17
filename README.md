# aur-claude-guard

LLM-based pre-install security review of AUR build scripts, packaged for pacman. It defends against the AUR supply-chain attacks that hide malware in `PKGBUILD` and `*.install` files — code that runs as your user during `makepkg` and as **root** during the pacman step. Before `yay` builds anything, the build files are sent to the `claude` CLI, which returns a strict `VERDICT: PASS` / `VERDICT: FAIL`; a FAIL aborts the install.

## What's in the package

| Installed path | Purpose |
| --- | --- |
| `/usr/bin/aur-claude-review` | The analyzer. Downloads an AUR package's build files with `yay -G` (no building), feeds `PKGBUILD` + `*.install` + other repo files to `claude -p`, parses the verdict. Recurses into AUR dependencies (static `.SRCINFO` parse — never sources the PKGBUILD). Caches verdicts by content hash. Fails closed. Hardened against prompt injection. |
| `/usr/bin/aur-update-check` | Runs `yay -Qua` and desktop-notifies when AUR updates exist. Read-only. |
| `/usr/share/aur-claude-guard/shell-hook.bash` | The `yay` wrapper. Source it from `~/.bashrc`; it gates every install/upgrade that pulls AUR packages on the review. |
| `/usr/lib/systemd/user/aur-update-check.{service,timer}` | User timer that runs the update check ~5 min after login and once a day. |
| `/usr/share/doc/aur-claude-guard/README.md` | This file. |

## Install

```
./install.sh           # builds, installs (sudo), and does the per-user activation below
```

Or manually: `makepkg -si`, then the two per-user steps:

```
echo 'source /usr/share/aur-claude-guard/shell-hook.bash' >> ~/.bashrc
systemctl --user enable --now aur-update-check.timer
```

The `claude` CLI must be on your PATH, and **AUR support should be disabled in pamac** so the only path to the AUR is the guarded `yay` (pamac builds AUR packages with its own engine and is not gated — see Limitations).

## How it decides what to review

For each candidate package it skips anything in the official signed repos (`pacman -Si`), confirms the rest are genuinely in the AUR (AUR RPC), and only then downloads and reviews them. Official-repo and virtual/`provides` dependencies are skipped. A download that fails for a package that *does* exist in the AUR is treated as a review error (fail-closed), never a silent skip.

## Usage

Automatic once the hook is sourced:

```
yay -S some-aur-pkg      # reviewed before build; aborts if FAIL
yay -Syu                 # pending AUR updates reviewed before build
```

Manual:

```
aur-claude-review some-aur-pkg              # exit 0 = PASS, 1 = FAIL, 2 = error
aur-claude-review --dir ~/build/some-pkg    # review an already-downloaded build dir
```

## Knobs (environment variables)

- `AURGUARD=off yay …` — bypass the guard for one command.
- `AUR_REVIEW_MODEL` — model for `claude --model` (default `claude-sonnet-4-6`).
- `AUR_REVIEW_NO_CACHE=1` — ignore the verdict cache.
- `AUR_REVIEW_RECURSE=0` — review only the named package, not its AUR deps.
- `AUR_REVIEW_CACHE` — cache dir (default `~/.cache/aur-claude-review`).
- `AUR_REVIEW_MAX_BYTES` — per-file content cap sent to the model (default 65536).

The verdict cache is keyed by the exact content of the build files, so an updated PKGBUILD is always re-reviewed and a previously-approved one is instant and free.

## Update notifications

Manage the notifier with:

```
systemctl --user start  aur-update-check.service     # check right now
systemctl --user list-timers aur-update-check.timer  # next run
systemctl --user disable --now aur-update-check.timer # turn it off
```

Apply updates with `yay -Syu`, which goes through the guard.

## Editing / iterating

The repo is the single source of truth. After changing a script, rebuild and reinstall: `./install.sh` (or `makepkg -si`). Verify the installed files match the package with `pacman -Qkk aur-claude-guard`, and see what the package owns with `pacman -Ql aur-claude-guard`. Bump `pkgrel` (or `pkgver`) in the PKGBUILD when you want pacman to treat it as a new version.

## Limitations

- **Not a sandbox.** A static LLM review catches the obvious-to-medium supply-chain patterns (curl|bash, exfiltration, reverse shells, obfuscation, suspicious hosts, prompt-injection bait) but a subtle attacker can evade any static review. One layer, not a guarantee — still skim PKGBUILDs you don't trust and prefer building in a container/VM.
- **A clean PKGBUILD can still fetch a malicious source.** If the payload lives in a remote tarball/repo downloaded at build time, the review sees only the URL, not the payload.
- **`pamac` and the GUI are not gated.** Only the `yay` CLI is wrapped; pamac builds AUR packages via its own engine, independent of the shell. Disable AUR in pamac and use `yay` for the AUR.
- **Fail-closed costs.** If `claude` is down or the AUR is unreachable, an install is blocked (with an interactive override prompt). Use `AURGUARD=off` to bypass deliberately.

## Uninstall

```
./uninstall.sh         # disables the timer and runs `pacman -R`
```

Then remove the `source …/shell-hook.bash` line from `~/.bashrc`.
