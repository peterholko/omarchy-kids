pkgbase=omarchy-kids-modules
pkgname=(omarchy-kids-core omarchy-kids-dns omarchy-kids-browsing omarchy-kids-time omarchy-kids-school omarchy-kids-grove omarchy-kids-typing)
pkgver=0.1.0
pkgrel=${KIDS_PKGREL:-1}
arch=(any)
url='https://github.com/peterholko/omarchy-kids'
license=(MIT)
makedepends=(python)
source=()
sha256sums=()
: "${OMARCHY_SRC:?Build with packaging/build from the omarchy-kids checkout}"

_stage_module() {
  provides=()
  conflicts=()
  replaces=()
  case $1 in
    core|dns|browsing|time|school)
      provides=("omarchy-parent-$1=$pkgver-$pkgrel")
      conflicts=("omarchy-parent-$1")
      replaces=("omarchy-parent-$1")
      ;;
  esac
  python "$OMARCHY_SRC/packaging/stage.py" stage "$OMARCHY_SRC" "$pkgdir" "$1"
}

package_omarchy-kids-core() {
  pkgdesc='Kids profile, parent password, and module management for Omarchy'
  depends=("omarchy-kids-base=4.0.0.alpha.kids0.1.0-$pkgrel" python sudo polkit jq gum)
  _stage_module core
}
package_omarchy-kids-dns() {
  pkgdesc='Optional Omarchy parent DNS filtering'
  depends=("omarchy-kids-core=$pkgver-$pkgrel" dnsmasq ufw networkmanager)
  _stage_module dns
}
package_omarchy-kids-browsing() {
  pkgdesc='Optional Omarchy parent browsing history'
  depends=("omarchy-kids-core=$pkgver-$pkgrel" util-linux)
  _stage_module browsing
}
package_omarchy-kids-time() {
  pkgdesc='Optional Omarchy screen-time limits and arithmetic practice'
  depends=("omarchy-kids-core=$pkgver-$pkgrel")
  _stage_module time
}
package_omarchy-kids-school() {
  pkgdesc='Optional Omarchy school and free-time modes'
  depends=("omarchy-kids-core=$pkgver-$pkgrel")
  _stage_module school
}
package_omarchy-kids-grove() {
  pkgdesc='Number Grove: an original arithmetic garden game for Omarchy Kids'
  depends=("omarchy-kids-core=$pkgver-$pkgrel")
  optdepends=('omarchy-kids-time: parent-controlled screen-time rewards')
  _stage_module grove
}

package_omarchy-kids-typing() {
  pkgdesc='Paw Post: a cozy typing adventure with animal friends'
  optdepends=()
  depends=("omarchy-kids-core=$pkgver-$pkgrel")
  _stage_module typing
}
