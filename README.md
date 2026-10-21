# aur-claude-guard

LLM-based pre-build security review of AUR build scripts, packaged for pacman. It defends against the AUR supply-chain attacks that hide malware in `PKGBUILD` and `*.install` files — code that runs as your user during `makepkg` and as **root** during the pacman step. Before `makepkg` reads a PKGBUILD, the build files are sent to the `claude` CLI, which returns a strict `VERDICT: PASS` / `VERDICT: FAIL`; anything but a PASS stops the build.

The gate sits in `makepkg` itself, so it does not matter which tool starts the build: `yay`, `paru`, Pamac (Add/Remove Software, GUI or `pamac-cli`), or a manual `makepkg` all go through it, in any shell.

## What's in the package

| Installed path | Purpose |
| --- | --- |
| `/etc/makepkg.conf.d/aur-claude-guard.conf` | Drop-in that makepkg loads with its configuration. It sources the gate. |
| `/usr/share/aur-claude-guard/makepkg-gate.sh` | The gate. Runs `aur-claude-review --dir` on the build directory before makepkg reads the PKGBUILD, and stops makepkg unless the verdict is PASS. |
| `/usr/bin/aur-claude-review` | The analyzer. Feeds `PKGBUILD` + `*.install` + the other package files to `claude -p` and parses the verdict. Caches verdicts by content hash. Fails closed. Hardened against prompt injection. |
| `/usr/share/doc/aur-claude-guard/README.md` | This file. |

## Install

```
./install.sh
```

It builds the package, installs it with `run0 pacman -U` (run0 asks for authentication), and removes the leftovers of earlier versions. There is no per-user activation step: the next `makepkg` run is gated. The `claude` CLI must be installed and logged in for the user who builds packages.

## How it works

makepkg loads `/etc/makepkg.conf.d/*.conf` after it parses its arguments and before it reads the PKGBUILD, so the gate runs before any code from the package. For example, when you click Apply on an AUR update in Pamac:

1. Pamac clones the package from `https://aur.archlinux.org/<pkg>.git` into its build directory. Cloning runs no package code.
2. Pamac runs `makepkg --printsrcinfo` there. makepkg loads the gate, and the gate sends the build files to `claude`.
3. On a PASS, makepkg continues. Pamac's next makepkg calls for the same build find the verdict in the cache and do not call `claude` again. On a FAIL, makepkg exits, and Pamac reports that the package failed to build. Its details pane shows the reason.

What the gate reviews:

- **Reviewed:** a directory that is a git clone from `aur.archlinux.org`, or a directory that is not the top of a git clone at all (an AUR snapshot tarball, a loose PKGBUILD).
- **Skipped:** the clone of any other git repository, such as an official package from `gitlab.archlinux.org` or this project; the fakeroot re-run that makepkg does for `package()`; and a makepkg run as root, which makepkg refuses anyway.

In a git clone, only the tracked files are reviewed: what the AUR maintainer published. Downloaded sources and the extracted `src/` tree are not sent. A symlink is shown to the model as a link; its target is never read.

Each package is reviewed when its own build starts, so a `yay -Syu` that builds three AUR packages makes three reviews, one before each build. A FAIL stops that build; packages built earlier in the same run stay upgraded.

## Usage

Automatic:

```
yay -S some-aur-pkg      # reviewed when makepkg starts; stops if FAIL
yay -Syu                 # each AUR update reviewed before its build
pamac build some-aur-pkg # same gate
```

A review takes from a few seconds to a minute. If it can outlast your sudo timeout during a long `yay -Syu`, let yay keep the credentials alive with `yay --save --sudoloop`.

If the review cannot complete (claude down, no verdict) and makepkg runs in a terminal, the gate asks whether to build without a clean review. Pamac gives makepkg no terminal, so there the build stops. When the build stops, the gate prints the ways out: `claude auth login` for an expired session, and terminal commands that build with `AURGUARD=off`. The Pamac window and tray started before you could set the variable, so the bypass works only from a terminal.

Manual:

```
aur-claude-review some-aur-pkg              # clone from the AUR and review; exit 0 = PASS, 1 = FAIL, 2 = error
aur-claude-review --dir ~/build/some-pkg    # review an already-downloaded build dir
```

By name, it skips anything in the official signed repos (`pacman -Si`), confirms the rest are genuinely in the AUR (AUR RPC), and recurses into AUR dependencies (static `.SRCINFO` parse — never sources the PKGBUILD). A download that fails for a package that *does* exist in the AUR is treated as a review error (fail-closed), never a silent skip.

## Knobs (environment variables)

- `AURGUARD=off` — bypass the gate for one command, for example `AURGUARD=off yay -S some-pkg`. makepkg inherits it from yay, paru, or a shell.
- `AUR_REVIEW_MODEL` — model for `claude --model` (default `claude-opus-5-5`).
- `AUR_REVIEW_NO_CACHE=1` — ignore the verdict cache.
- `AUR_REVIEW_RECURSE=0` — by name, review only the named package, not its AUR deps.
- `AUR_REVIEW_CACHE` — cache dir (default `~/.cache/aur-claude-review`).
- `AUR_REVIEW_MAX_BYTES` — per-file content cap sent to the model (default 65536).

The verdict cache is keyed by the exact content of the build files, so an updated PKGBUILD is always re-reviewed and a previously-approved one is instant and free. A VCS package (`-git`, `-svn`, …) is usually reviewed twice per build, because makepkg writes the new `pkgver` into the PKGBUILD after the first review.

## Editing / iterating

The repo is the single source of truth. After changing a script, rebuild and reinstall: `./install.sh`. Verify the installed files match the package with `pacman -Qkk aur-claude-guard`, and see what the package owns with `pacman -Ql aur-claude-guard`. Bump `pkgrel` (or `pkgver`) in the PKGBUILD when you want pacman to treat it as a new version.

## Limitations

- **Not a sandbox.** A static LLM review catches the obvious-to-medium supply-chain patterns (curl|bash, exfiltration, reverse shells, obfuscation, suspicious hosts, prompt-injection bait) but a subtle attacker can evade any static review. One layer, not a guarantee — still skim PKGBUILDs you don't trust and prefer building in a container/VM.
- **A clean PKGBUILD can still fetch a malicious source.** If the payload lives in a remote tarball/repo downloaded at build time, the review sees only the URL, not the payload.
- **Only makepkg is gated.** A tool that builds AUR packages without makepkg, or a build in a chroot (`makechrootpkg`, `pkgctl build`), does not load the gate.
- **`claude` must be usable by the building user.** The gate also looks in `~/.local/bin` and `~/.claude/local` for a GUI app's shorter PATH. A build that runs as another user finds no logged-in `claude` and fails closed. Run `pamac build` as your user, not with sudo.
- **Fail-closed costs.** If `claude` is down or the AUR is unreachable, a build is blocked (with an interactive override prompt in a terminal). Use `AURGUARD=off` to bypass deliberately.

## Uninstall

```
./uninstall.sh         # runs `run0 pacman -R aur-claude-guard`
```
