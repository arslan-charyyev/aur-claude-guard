# Maintainer: Arslan Charyyev <88978221+arslan-charyyev@users.noreply.github.com>
pkgname=aur-claude-guard
pkgver=1.0.0
pkgrel=1
pkgdesc="Review AUR build scripts with the claude CLI before yay builds them (PASS/FAIL gate), plus an AUR update notifier"
arch=('any')
url="https://github.com/arslan-charyyev/aur-claude-guard"
license=('MIT')
depends=('bash' 'yay' 'curl' 'libnotify' 'pacman' 'systemd')
optdepends=('claude: the LLM CLI used to perform the review (install separately; must be on PATH)')
install="$pkgname.install"
# Local, git-tracked sources: integrity is provided by git, so checksums are SKIP.
source=('aur-claude-review'
        'aur-update-check'
        'shell-hook.bash'
        'aur-update-check.service'
        'aur-update-check.timer'
        'README.md')
sha256sums=('SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP')

package() {
  install -Dm755 "$srcdir/aur-claude-review" "$pkgdir/usr/bin/aur-claude-review"
  install -Dm755 "$srcdir/aur-update-check"  "$pkgdir/usr/bin/aur-update-check"
  install -Dm644 "$srcdir/shell-hook.bash"   "$pkgdir/usr/share/$pkgname/shell-hook.bash"
  install -Dm644 "$srcdir/aur-update-check.service" "$pkgdir/usr/lib/systemd/user/aur-update-check.service"
  install -Dm644 "$srcdir/aur-update-check.timer"   "$pkgdir/usr/lib/systemd/user/aur-update-check.timer"
  install -Dm644 "$srcdir/README.md" "$pkgdir/usr/share/doc/$pkgname/README.md"
}
