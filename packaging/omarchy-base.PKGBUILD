# Adapted from omacom/omarchy-pkgs, commit 4ed5f14629843251b52a5217597b112fc485e2c0.
# Both base packages and all modules use one source snapshot and build revision.
pkgname='omarchy-kids-base'
# Built from the same source snapshot as every module in this release.
pkgver=4.0.0.alpha.kids0.1.0
pkgrel=${KIDS_PKGREL:-1}
pkgdesc='Beautiful, modern, and opinionated Arch Linux by DHH'
# The payload is architecture-independent, but the dependency set is not: the
# boot stack differs per architecture (see depends_x86_64 / depends_aarch64),
# and makepkg only honours arch-suffixed arrays on arch-specific packages.
arch=('x86_64' 'aarch64')
url='https://github.com/peterholko/omarchy-kids'
license=('MIT')
conflicts=('omarchy' 'omarchy-dev')
provides=("omarchy=$pkgver")
# Hard depends: only packages whose removal would brick the desktop. The ISO
# pacstraps the full default install set from install/omarchy-base.packages.
depends=(
  # Omarchy meta
  'omarchy-keyring'
  # Exact-version pin: omarchy-settings-dev `provides=omarchy-settings`
  # (unversioned), and an unversioned dependency here would let the dev
  # package satisfy it, leaving a mixed dev/stable install. A versioned
  # dependency can only be satisfied by the real omarchy-settings built
  # from the same _commit, and forces the pair to upgrade together.
  "omarchy-kids-settings=${pkgver}-${pkgrel}"

  # Wayland / Hyprland core
  'hyprland'
  'quickshell'
  'uwsm'
  'sddm'
  'xdg-desktop-portal-hyprland'

  # Audio / auth / portal essentials
  'wireplumber'
  'pipewire'
  'gnome-keyring'

  # Required by omarchy-* scripts and omarchy-shell
  'gum'
  'jq'
  'git'
  'perl' # /usr/bin/omarchy-shell invokes perl directly

  # Update availability checks (checkupdates from pacman-contrib uses fakeroot)
  'fakeroot'
  'pacman-contrib'

  # System font (UI assumes it)
  'ttf-jetbrains-mono-nerd-basic'
)

# Bootloader stack. Lives here rather than on omarchy-settings because
# omarchy-settings is also installed into the live ISO env (for plymouth
# / /etc/skel seeding), where the limine-mkinitcpio-hook would fail with
# 'Cannot detect an ESP path' inside the chroot. The omarchy-settings
# config drop-ins under /etc/mkinitcpio.conf.d/, /etc/limine-entry-tool.d/,
# and /etc/snapper/config-templates/ only do anything when these are
# installed alongside.
depends_x86_64=(
  'limine'
  'limine-mkinitcpio-hook'
  'limine-snapper-sync'
  'snapper'
)

# Apple Silicon boots through m1n1 + GRUB from the Asahi packages and keeps
# Arch Linux ARM's kernel and boot layout, so the Limine/Snapper stack does not
# apply. Wi-Fi on the Broadcom parts only scans reliably through the iwd
# backend, which install/hardware/network.sh selects on Apple Silicon.
depends_aarch64=(
  'iwd'
  'networkmanager'
)

makedepends=(
  'git'
  'python'
)

# packaging/build freezes one checkout for all seven packages.
source=()
sha256sums=()
: "${OMARCHY_SRC:?Build with packaging/build from the omarchy-kids checkout}"

prepare() {
  python "$OMARCHY_SRC/packaging/stage.py" snapshot "$OMARCHY_SRC" "$srcdir/omarchy"
}

package() {
  cd "$srcdir/omarchy"

  # Runtime binaries — ship everything in bin/ except the debug helpers
  # that ship from omarchy-settings (needed before omarchy is installed,
  # e.g. on the ISO live env).
  install -d "$pkgdir/usr/bin" "$pkgdir/usr/share/omarchy/bin"
  for bin in bin/*; do
    [[ -f $bin ]] || continue
    local base
    base=$(basename "$bin")
    case "$base" in
      omarchy-debug|omarchy-debug-idle|omarchy-upload-log)
        continue
        ;;
    esac
    install -Dm755 "$bin" "$pkgdir/usr/bin/$base"
    ln -s "/usr/bin/$base" "$pkgdir/usr/share/omarchy/bin/$base"
  done

  install -d "$pkgdir/usr/share/omarchy"

  # Guard direct pacman upgrades from bypassing the Omarchy update pipeline,
  # and pause Hyprland live config reloads while settings files are replaced.
  # Ship hooks with their Exec targets so package skew cannot leave a broken
  # hook pointing at a missing binary.
  install -Dm644 default/libalpm/hooks/00-omarchy-update-guard.hook "$pkgdir/usr/share/libalpm/hooks/00-omarchy-update-guard.hook"
  install -Dm644 default/libalpm/hooks/10-omarchy-hyprland-reload-pause.hook "$pkgdir/usr/share/libalpm/hooks/10-omarchy-hyprland-reload-pause.hook"
  install -Dm644 default/libalpm/hooks/90-omarchy-hyprland-reload-resume.hook "$pkgdir/usr/share/libalpm/hooks/90-omarchy-hyprland-reload-resume.hook"

  # Target-side setup scripts and package lists used by ISO finalization,
  # first login, future users, migrations, and reinstall/reset commands.
  cp -a install "$pkgdir/usr/share/omarchy/"

  # Theme bundles for theme switching.
  cp -a themes "$pkgdir/usr/share/omarchy/"

  # Versioned migrations runner reads from this tree.
  cp -a migrations "$pkgdir/usr/share/omarchy/"

  # Fresh users created after install are already on the package layout in this
  # build, so seed migration markers through /etc/skel. Existing users keep
  # their own state and still run pending migrations on update.
  if compgen -G 'migrations/*.sh' >/dev/null; then
    install -d "$pkgdir/etc/skel/.local/state/omarchy/migrations"
    for migration in migrations/*.sh; do
      touch "$pkgdir/etc/skel/.local/state/omarchy/migrations/$(basename "$migration")"
    done
  fi
  # Quickshell desktop shell tree.
  cp -a shell "$pkgdir/usr/share/omarchy/"

  # Runtime version file.
  install -Dm644 version "$pkgdir/usr/share/omarchy/version"
  # Each optional feature is owned by exactly one separate package.
  python "$OMARCHY_SRC/packaging/stage.py" prune "$OMARCHY_SRC" "$pkgdir"
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
