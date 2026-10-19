# aur-claude-guard

LLM-based pre-install security review of AUR build scripts, packaged for pacman. It defends against the AUR supply-chain attacks that hide malware in `PKGBUILD` and `*.install` files — code that runs as your user during `makepkg` and as **root** during the pacman step. Before `yay` builds anything, the build files are sent to the `claude` CLI, which returns a strict `VERDICT: PASS` / `VERDICT: FAIL`; a FAIL aborts the install.

## What's in the package

| Installed path | Purpose |
| --- | --- |
| `/usr/bin/aur-claude-review` | The analyzer. Downloads an AUR package's build files with `yay -G` (no building), feeds `PKGBUILD` + `*.install` + other repo files to `claude -p`, parses the verdict. Recurses into AUR dependencies (static `.SRCINFO` parse — never sources the PKGBUILD). Caches verdicts by content hash. Fails closed. Hardened against prompt injection. |
| `/usr/share/aur-claude-guard/shell-hook.bash` | The `yay` wrapper. Source it from `~/.bashrc`; it gates every install/upgrade that pulls AUR packages on the review. |
| `/usr/share/doc/aur-claude-guard/README.md` | This file. |

## Install

```
./install.sh
```

It builds the package, installs it (pacman asks for sudo), and reminds you to add the shell guard to your `~/.bashrc`:

```
source /usr/share/aur-claude-guard/shell-hook.bash
```

Add that line, then open a new terminal (or `source ~/.bashrc`) so the `yay` guard loads.

The `claude` CLI must be on your PATH. **Install and upgrade AUR packages only with `yay`.** Pamac can keep AUR support on so that it notifies you about AUR updates, but apply those updates with `yay -Syu`, not with Pamac's Apply button: Pamac builds AUR packages with its own engine, so the review does not run (see Limitations).

## How it decides what to review

For each candidate package it skips anything in the official signed repos (`pacman -Si`), confirms the rest are genuinely in the AUR (AUR RPC), and only then downloads and reviews them. Official-repo and virtual/`provides` dependencies are skipped. A download that fails for a package that *does* exist in the AUR is treated as a review error (fail-closed), never a silent skip.

## Usage

Automatic once the hook is sourced:

```
yay -S some-aur-pkg      # reviewed before build; aborts if FAIL
yay -Syu                 # pending AUR updates reviewed before build
```

The password prompt comes **first**, before the review: the guard runs `sudo -v` up front and refreshes the timestamp while the review runs, so you can start `yay -Syu` and walk away instead of coming back to find it waiting on a password. If pre-authentication fails (not in sudoers, wrong password) the guard just warns and carries on — `yay` prompts on its own schedule as before. Note that `yay` itself may still ask its own questions later (diffs to show, "Proceed with installation?"), and a review that *can't complete* falls back to an interactive override prompt.

Manual:

```
aur-claude-review some-aur-pkg              # exit 0 = PASS, 1 = FAIL, 2 = error
aur-claude-review --dir ~/build/some-pkg    # review an already-downloaded build dir
```

## Knobs (environment variables)

- `AURGUARD=off yay …` — bypass the guard for one command.
- `AURGUARD_SUDO_PRIME=0` — don't pre-authenticate; let `yay` ask for the password whenever it wants.
- `AURGUARD_SUDO` — privilege-escalation binary to pre-authenticate with (default: `sudo`, falling back to `doas`).
- `AUR_REVIEW_MODEL` — model for `claude --model` (default `claude-opus-5-5`).
- `AUR_REVIEW_NO_CACHE=1` — ignore the verdict cache.
- `AUR_REVIEW_RECURSE=0` — review only the named package, not its AUR deps.
- `AUR_REVIEW_CACHE` — cache dir (default `~/.cache/aur-claude-review`).
- `AUR_REVIEW_MAX_BYTES` — per-file content cap sent to the model (default 65536).

The verdict cache is keyed by the exact content of the build files, so an updated PKGBUILD is always re-reviewed and a previously-approved one is instant and free.

## Editing / iterating

The repo is the single source of truth. After changing a script, rebuild and reinstall: `./install.sh`. Verify the installed files match the package with `pacman -Qkk aur-claude-guard`, and see what the package owns with `pacman -Ql aur-claude-guard`. Bump `pkgrel` (or `pkgver`) in the PKGBUILD when you want pacman to treat it as a new version.

## Limitations

- **Not a sandbox.** A static LLM review catches the obvious-to-medium supply-chain patterns (curl|bash, exfiltration, reverse shells, obfuscation, suspicious hosts, prompt-injection bait) but a subtle attacker can evade any static review. One layer, not a guarantee — still skim PKGBUILDs you don't trust and prefer building in a container/VM.
- **A clean PKGBUILD can still fetch a malicious source.** If the payload lives in a remote tarball/repo downloaded at build time, the review sees only the URL, not the payload.
- **`pamac` and the GUI are not gated.** Only the `yay` CLI is wrapped; pamac builds AUR packages via its own engine, independent of the shell. With AUR support on, Pamac is safe for update notifications only: install and upgrade AUR packages with `yay`. To close this gap completely, turn AUR support off in Pamac.
- **Fail-closed costs.** If `claude` is down or the AUR is unreachable, an install is blocked (with an interactive override prompt). Use `AURGUARD=off` to bypass deliberately.

## Uninstall

```
./uninstall.sh         # disables the timer and runs `pacman -R`
```

Then remove the `source …/shell-hook.bash` line from `~/.bashrc`.
