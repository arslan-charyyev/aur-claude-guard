# Maintainer: Arslan Charyyev <88978221+arslan-charyyev@users.noreply.github.com>
pkgname=aur-claude-guard
pkgver=2.0.0
pkgrel=2
pkgdesc="Review AUR build scripts with the claude CLI before makepkg runs them (PASS/FAIL gate for yay, paru, and Pamac)"
arch=('any')
url="https://github.com/arslan-charyyev/aur-claude-guard"
license=('MIT')
# pacman 7 brought the makepkg.conf.d drop-in directory that loads the gate.
depends=('bash' 'curl' 'git' 'pacman>=7')
optdepends=('claude: the LLM CLI used to perform the review (install separately; must be on PATH)')
backup=('etc/makepkg.conf.d/aur-claude-guard.conf')
install="$pkgname.install"
# Local, git-tracked sources: integrity is provided by git, so checksums are SKIP.
source=('aur-claude-review'
        'makepkg-gate.sh'
        'aur-claude-guard.conf'
        'README.md')
sha256sums=('SKIP' 'SKIP' 'SKIP' 'SKIP')

package() {
  install -Dm755 "$srcdir/aur-claude-review"     "$pkgdir/usr/bin/aur-claude-review"
  install -Dm644 "$srcdir/makepkg-gate.sh"       "$pkgdir/usr/share/$pkgname/makepkg-gate.sh"
  install -Dm644 "$srcdir/aur-claude-guard.conf" "$pkgdir/etc/makepkg.conf.d/aur-claude-guard.conf"
  install -Dm644 "$srcdir/README.md" "$pkgdir/usr/share/doc/$pkgname/README.md"
}
