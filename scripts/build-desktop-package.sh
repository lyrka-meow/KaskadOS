#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly BUILD_ROOT="${PROJECT_DIR}/build/desktop-package"
readonly PAYLOAD_ROOT="${BUILD_ROOT}/payload"
readonly PACKAGE_ROOT="${BUILD_ROOT}/makepkg"
readonly PACKAGE_DEST="${KASKADOS_PACKAGE_DEST:-${PROJECT_DIR}/out/packages/x86_64}"
readonly KASKAD_SOURCE="${PROJECT_DIR}/components/kaskad-desktop"
readonly KASKAD_BUILD="${BUILD_ROOT}/kaskad-desktop"
readonly COMPOSITOR_BUILD="${KASKAD_BUILD}/compositor"
readonly PORTAL_BUILD="${KASKAD_BUILD}/portal"
readonly QUICKSHELL_BUILD="${KASKAD_BUILD}/quickshell-kaskad"
readonly SHELL_BUILD="${KASKAD_BUILD}/shell-source"
readonly REGALIA_SOURCE="${PROJECT_DIR}/components/regalia"
readonly REGALIA_BUILD="${BUILD_ROOT}/regalia"
readonly REGALIA_BIN="${REGALIA_BUILD}/bin"
readonly PACKAGE_SOURCE="${PROJECT_DIR}/repository/packages/kaskados-desktop"
readonly DGOP_BUILD_SCRIPT="${SCRIPT_DIR}/build-dgop-package.sh"
readonly GLOBAL_SHORTCUTS_BUILD_SCRIPT="${SCRIPT_DIR}/build-global-shortcuts-package.sh"
readonly GLOBAL_SHORTCUTS_SYSROOT="${BUILD_ROOT}/global-shortcuts-sysroot"
# shellcheck source=/dev/null
source "${PROJECT_DIR}/components/regalia/packaging/sing-box.env"
readonly SING_BOX_ARCHIVE="sing-box-${SING_BOX_VERSION}-linux-amd64.tar.gz"
readonly SING_BOX_CACHE="${PACKAGE_ROOT}/sources/${SING_BOX_ARCHIVE}"
readonly BIBATA_VERSION="2.0.7"
readonly BIBATA_ARCHIVE="Bibata-Modern-Ice.tar.xz"
readonly BIBATA_SHA256="a68cae60c4dc706350e194ebc91c5fe48bc7bc9d59e119555834a2a7ee5078ef"
readonly BIBATA_CACHE="${PACKAGE_ROOT}/sources/${BIBATA_ARCHIVE}"
readonly BIBATA_SOURCE_ARCHIVE="Bibata_Cursor-${BIBATA_VERSION}.tar.gz"
readonly BIBATA_SOURCE_SHA256="1f21e5cade53d668476f973bd8ec827882a0e32c38e0e766abf007f8b3b46313"
readonly BIBATA_SOURCE_CACHE="${PACKAGE_ROOT}/sources/${BIBATA_SOURCE_ARCHIVE}"
readonly BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"
readonly KASKAD_BUILD_JOBS="${KASKAD_BUILD_JOBS:-8}"

die() {
  printf 'Ошибка: %s\n' "$*" >&2
  exit 1
}

for command_name in bsdtar cmake curl go make makepkg ninja pacman readelf sha256sum tar; do
  command -v "${command_name}" >/dev/null 2>&1 || die "не найдена команда ${command_name}"
done

required_build_packages=(
  base-devel
  curl
  extra-cmake-modules
  git
  go
  kbookmarks
  kcolorscheme
  kcompletion
  kconfig
  kcoreaddons
  kcrash
  kdecoration
  kglobalaccel
  kglobalacceld
  ki18n
  kiconthemes
  kidletime
  kitemviews
  kjobwidgets
  knighttime
  knotifications
  kpackage
  kpmcore
  kservice
  kstatusnotifieritem
  kwayland
  kwidgetsaddons
  kwindowsystem
  libqaccessibilityclient-qt6
  libpwquality
  plasma-wayland-protocols
  qt6-declarative
  solid
  vulkan-headers
  wayland-protocols
  yaml-cpp
)
mapfile -t missing_build_packages < <(pacman -T "${required_build_packages[@]}" 2>/dev/null || true)
if (( ${#missing_build_packages[@]} > 0 )); then
  printf 'Не установлены пакеты для сборки DE:\n' >&2
  printf '  %s\n' "${missing_build_packages[@]}" >&2
  printf 'Установите их командой:\n  sudo pacman -S --needed' >&2
  printf ' %q' "${missing_build_packages[@]}" >&2
  printf '\n' >&2
  exit 2
fi

if (( EUID == 0 )); then
  die 'пакет рабочей среды нужно собирать обычным пользователем'
fi

[[ "$(uname -m)" == x86_64 ]] || die 'сборка поддерживается только на x86_64'
[[ -f "${KASKAD_SOURCE}/VERSION" ]] || die 'не найдена версия KaskadDesktop'
[[ -f "${KASKAD_SOURCE}/release/release.json" ]] || die 'не найден манифест выпуска KaskadDesktop'
desktop_version="$(tr -d '\n' < "${KASKAD_SOURCE}/VERSION")"
release_version="$(sed -nE 's/^[[:space:]]*"version":[[:space:]]*"([^"]+)".*/\1/p' "${KASKAD_SOURCE}/release/release.json")"
release_notes="$(sed -nE 's/^[[:space:]]*"releaseNotes":[[:space:]]*"([^"]+)".*/\1/p' "${KASKAD_SOURCE}/release/release.json")"
[[ "${release_version}" == "${desktop_version}" ]] \
  || die "версия release.json (${release_version:-не указана}) не совпадает с VERSION (${desktop_version})"
[[ -n "${release_notes}" && -f "${KASKAD_SOURCE}/release/${release_notes}" ]] \
  || die "не найден файл заметок выпуска ${release_notes:-из release.json}"
[[ -f "${REGALIA_SOURCE}/go.mod" ]] || die 'не найден исходный код Regalia'
[[ -f "${PACKAGE_SOURCE}/PKGBUILD" ]] || die 'не найден PKGBUILD kaskados-desktop'
[[ -x "${DGOP_BUILD_SCRIPT}" ]] || die 'не найден скрипт сборки dgop'
[[ -x "${GLOBAL_SHORTCUTS_BUILD_SCRIPT}" ]] || die 'не найден скрипт сборки движка сочетаний'

install -d -m 0755 \
  "${BUILD_ROOT}" \
  "${PACKAGE_ROOT}/work" \
  "${PACKAGE_ROOT}/sources" \
  "${PACKAGE_DEST}"

KASKADOS_PACKAGE_DEST="${PACKAGE_DEST}" "${DGOP_BUILD_SCRIPT}"
KASKADOS_PACKAGE_DEST="${PACKAGE_DEST}" "${GLOBAL_SHORTCUTS_BUILD_SCRIPT}"
mapfile -t global_shortcuts_packages < <(
  find "${PACKAGE_DEST}" -maxdepth 1 -type f \
    -name 'kaskados-globalacceld-[0-9]*-x86_64.pkg.tar.zst' -printf '%T@ %p\n' \
    | sort -nr | head -n 1 | cut -d ' ' -f 2-
)
(( ${#global_shortcuts_packages[@]} == 1 )) \
  || die 'не удалось однозначно определить собранный движок глобальных сочетаний'
rm -rf -- "${GLOBAL_SHORTCUTS_SYSROOT}"
install -d -m 0755 "${GLOBAL_SHORTCUTS_SYSROOT}"
bsdtar -xpf "${global_shortcuts_packages[0]}" -C "${GLOBAL_SHORTCUTS_SYSROOT}"
readonly GLOBAL_SHORTCUTS_CMAKE_DIR="${GLOBAL_SHORTCUTS_SYSROOT}/usr/lib/cmake/KGlobalAccelD"
[[ -f "${GLOBAL_SHORTCUTS_CMAKE_DIR}/KGlobalAccelDConfig.cmake" ]] \
  || die 'в пакете отсутствует CMake-конфигурация движка глобальных сочетаний'

# A reused CMake tree retains outputs of targets that disappeared from the
# graph. The payload is staged directly from these trees, so a release must
# start from empty component builds instead of trying to maintain an
# ever-growing blacklist of historical artifacts.
rm -rf -- \
  "${COMPOSITOR_BUILD}" \
  "${PORTAL_BUILD}" \
  "${QUICKSHELL_BUILD}"

env -u LD_LIBRARY_PATH cmake \
  -S "${KASKAD_SOURCE}/compositor" \
  -B "${COMPOSITOR_BUILD}" \
  -G Ninja \
  -DBUILD_TESTING=OFF \
  -DKWIN_BUILD_ACTIVITIES=OFF \
  -DKWIN_BUILD_SCREENLOCKER=OFF \
  -DKGlobalAccelD_DIR="${GLOBAL_SHORTCUTS_CMAKE_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
  -DCMAKE_BUILD_RPATH_USE_ORIGIN=ON \
  -DCMAKE_INSTALL_RPATH='$ORIGIN' \
  -DCMAKE_INSTALL_PREFIX=/opt/kaskad-desktop
env -u LD_LIBRARY_PATH cmake --build "${COMPOSITOR_BUILD}" \
  --target kaskad-compositor kaskad-cursor-exporter kaskad-cursor-x11-smoke \
  --parallel "${KASKAD_BUILD_JOBS}"
[[ -z "$(find "${COMPOSITOR_BUILD}/bin/kwin/plugins" -maxdepth 1 -type f -name '*.so' -print -quit 2>/dev/null)" ]] \
  || die 'сборка KaskadDesktop неожиданно создала динамический модуль'
KASKAD_BUILD_ROOT="${COMPOSITOR_BUILD}" \
KASKAD_EXTRA_LIBRARY_PATH="${GLOBAL_SHORTCUTS_SYSROOT}/usr/lib" \
  "${KASKAD_SOURCE}/scripts/smoke-virtual.sh"
rm -f -- "${COMPOSITOR_BUILD}/bin/qtwaylandscanner_kde"

if ! printf '%s  %s\n' "${BIBATA_SHA256}" "${BIBATA_CACHE}" | sha256sum -c - >/dev/null 2>&1; then
  rm -f -- "${BIBATA_CACHE}"
  curl -fL --retry 8 --retry-all-errors --retry-delay 2 --silent --show-error \
    "https://github.com/ful1e5/Bibata_Cursor/releases/download/v${BIBATA_VERSION}/${BIBATA_ARCHIVE}" \
    -o "${BIBATA_CACHE}"
fi
printf '%s  %s\n' "${BIBATA_SHA256}" "${BIBATA_CACHE}" | sha256sum -c -

if ! printf '%s  %s\n' "${BIBATA_SOURCE_SHA256}" "${BIBATA_SOURCE_CACHE}" | sha256sum -c - >/dev/null 2>&1; then
  rm -f -- "${BIBATA_SOURCE_CACHE}"
  curl -fL --retry 8 --retry-all-errors --retry-delay 2 --silent --show-error \
    "https://github.com/ful1e5/Bibata_Cursor/archive/refs/tags/v${BIBATA_VERSION}.tar.gz" \
    -o "${BIBATA_SOURCE_CACHE}"
fi
printf '%s  %s\n' "${BIBATA_SOURCE_SHA256}" "${BIBATA_SOURCE_CACHE}" | sha256sum -c -

env -u LD_LIBRARY_PATH cmake \
  -S "${KASKAD_SOURCE}/portal" \
  -B "${PORTAL_BUILD}" \
  -G Ninja \
  -DBUILD_TESTING=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
  -DCMAKE_BUILD_RPATH_USE_ORIGIN=ON \
  -DCMAKE_INSTALL_RPATH='$ORIGIN' \
  -DCMAKE_INSTALL_PREFIX=/opt/kaskad-desktop
env -u LD_LIBRARY_PATH cmake --build "${PORTAL_BUILD}" --parallel "${KASKAD_BUILD_JOBS}"
rm -f -- \
  "${PORTAL_BUILD}/bin/notificationportaltest" \
  "${PORTAL_BUILD}/bin/xdgshortcuttest" \
  "${PORTAL_BUILD}/bin/inputcapturebarriertest"

env -u LD_LIBRARY_PATH cmake \
  -S "${KASKAD_SOURCE}/quickshell/kaskad-module" \
  -B "${QUICKSHELL_BUILD}" \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
  -DCMAKE_BUILD_RPATH_USE_ORIGIN=ON \
  -DCMAKE_INSTALL_RPATH='$ORIGIN' \
  -DCMAKE_INSTALL_PREFIX=/opt/kaskad-desktop
env -u LD_LIBRARY_PATH cmake --build "${QUICKSHELL_BUILD}" --parallel "${KASKAD_BUILD_JOBS}"
if [[ -e "${SHELL_BUILD}" ]]; then
  rm -rf -- "${SHELL_BUILD}"
fi
install -d -m 0755 "${SHELL_BUILD}"
cp -a -- "${KASKAD_SOURCE}/shell/KaskadShell/." "${SHELL_BUILD}/"
make -C "${SHELL_BUILD}/core" \
  VERSION="$(tr -d '\n' < "${KASKAD_SOURCE}/VERSION")" \
  COMMIT=kaskados \
  build

KASKAD_BUILD_ROOT="${COMPOSITOR_BUILD}" \
KASKAD_QUICKSHELL_BUILD_ROOT="${QUICKSHELL_BUILD}" \
KASKAD_SHELL_ROOT="${SHELL_BUILD}/quickshell" \
KASKAD_SHELL_BACKEND="${SHELL_BUILD}/core/bin/kaskad-shell" \
KASKAD_PORTAL_BINARY="${PORTAL_BUILD}/bin/xdg-desktop-portal-kaskad" \
  "${KASKAD_SOURCE}/scripts/smoke-shell.sh"

if [[ -e "${REGALIA_BUILD}" ]]; then
  rm -rf -- "${REGALIA_BUILD}"
fi
install -d -m 0755 "${REGALIA_BIN}"
(
  cd -- "${REGALIA_SOURCE}"
  env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags '-s -w' -o "${REGALIA_BIN}/regalia" ./cmd/regalia
  env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags '-s -w' -o "${REGALIA_BIN}/regaliad" ./cmd/regaliad
  env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags '-s -w' -o "${REGALIA_BIN}/regalia-engine" ./cmd/regalia-engine
)

if ! printf '%s  %s\n' "${SING_BOX_SHA256}" "${SING_BOX_CACHE}" | sha256sum -c - >/dev/null 2>&1; then
  rm -f -- "${SING_BOX_CACHE}"
  curl -fL --retry 8 --retry-all-errors --retry-delay 2 --silent --show-error \
    "https://github.com/${SING_BOX_REPOSITORY}/releases/download/v${SING_BOX_VERSION}/${SING_BOX_ARCHIVE}" \
    -o "${SING_BOX_CACHE}"
fi
printf '%s  %s\n' "${SING_BOX_SHA256}" "${SING_BOX_CACHE}" | sha256sum -c -
install -m 0644 "${SING_BOX_CACHE}" "${REGALIA_BUILD}/${SING_BOX_ARCHIVE}"
tar -xzf "${REGALIA_BUILD}/${SING_BOX_ARCHIVE}" -C "${REGALIA_BUILD}"
install -m 0755 \
  "${REGALIA_BUILD}/sing-box-${SING_BOX_VERSION}-linux-amd64/sing-box" \
  "${REGALIA_BIN}/sing-box"

if [[ -e "${PAYLOAD_ROOT}" ]]; then
  rm -rf -- "${PAYLOAD_ROOT}"
fi
readonly KASKAD_STAGE="${PAYLOAD_ROOT}/opt/kaskad-desktop"
install -d -m 0755 \
  "${KASKAD_STAGE}/build/compositor" \
  "${KASKAD_STAGE}/build/portal" \
  "${KASKAD_STAGE}/build/quickshell-kaskad" \
  "${KASKAD_STAGE}/shell/KaskadShell/core/bin" \
  "${PAYLOAD_ROOT}/usr/bin" \
  "${PAYLOAD_ROOT}/usr/lib/systemd/user" \
  "${PAYLOAD_ROOT}/usr/lib/udev/rules.d" \
  "${PAYLOAD_ROOT}/usr/share/applications" \
  "${PAYLOAD_ROOT}/usr/share/dbus-1/services" \
  "${PAYLOAD_ROOT}/usr/share/mime/packages" \
  "${PAYLOAD_ROOT}/usr/share/kaskados/releases" \
  "${PAYLOAD_ROOT}/usr/share/icons" \
  "${PAYLOAD_ROOT}/usr/share/licenses/kaskados-desktop" \
  "${PAYLOAD_ROOT}/usr/share/kaskados/sources" \
  "${PAYLOAD_ROOT}/usr/share/wayland-sessions" \
  "${PAYLOAD_ROOT}/usr/share/xdg-desktop-portal/portals"

cp -a -- "${COMPOSITOR_BUILD}/bin" "${KASKAD_STAGE}/build/compositor/"

cursor_unpack="${KASKAD_BUILD}/cursor-theme"
rm -rf -- "${cursor_unpack}"
install -d -m 0755 "${cursor_unpack}"
tar -xJf "${BIBATA_CACHE}" -C "${cursor_unpack}"
mv -- "${cursor_unpack}/Bibata-Modern-Ice" "${PAYLOAD_ROOT}/usr/share/icons/KaskadCursorBase"
sed -i \
  -e 's/^Name=.*/Name=Kaskad Cursor Base/' \
  -e 's/^Comment=.*/Comment=Bibata Modern Ice base for the Kaskad dynamic cursor/' \
  "${PAYLOAD_ROOT}/usr/share/icons/KaskadCursorBase/index.theme"
tar -xOf "${BIBATA_SOURCE_CACHE}" "Bibata_Cursor-${BIBATA_VERSION}/LICENSE" \
  > "${PAYLOAD_ROOT}/usr/share/licenses/kaskados-desktop/Bibata-Cursor.LICENSE"
install -m 0644 "${BIBATA_SOURCE_CACHE}" \
  "${PAYLOAD_ROOT}/usr/share/kaskados/sources/${BIBATA_SOURCE_ARCHIVE}"

"${COMPOSITOR_BUILD}/bin/kaskad-cursor-exporter" \
  --base "${PAYLOAD_ROOT}/usr/share/icons/KaskadCursorBase" \
  --verify-only
"${COMPOSITOR_BUILD}/bin/kaskad-cursor-exporter" \
  --base "${PAYLOAD_ROOT}/usr/share/icons/KaskadCursorBase" \
  --self-test
KASKAD_BUILD_ROOT="${COMPOSITOR_BUILD}" \
KASKAD_EXTRA_LIBRARY_PATH="${GLOBAL_SHORTCUTS_SYSROOT}/usr/lib" \
KASKAD_CURSOR_BASE="${PAYLOAD_ROOT}/usr/share/icons/KaskadCursorBase" \
  "${KASKAD_SOURCE}/scripts/smoke-virtual.sh"
rm -f -- "${KASKAD_STAGE}/build/compositor/bin/kaskad-cursor-x11-smoke"
cp -a -- "${PORTAL_BUILD}/bin" "${KASKAD_STAGE}/build/portal/"
cp -a -- "${QUICKSHELL_BUILD}/Kaskad" "${KASKAD_STAGE}/build/quickshell-kaskad/"
cp -a -- "${QUICKSHELL_BUILD}"/libquickshell-kaskad.so* \
  "${KASKAD_STAGE}/build/quickshell-kaskad/"
install -m 0755 "${SHELL_BUILD}/core/bin/kaskad-shell" \
  "${KASKAD_STAGE}/shell/KaskadShell/core/bin/kaskad-shell"
cp -a -- \
  "${KASKAD_SOURCE}/shell/KaskadShell/quickshell" \
  "${KASKAD_SOURCE}/shell/KaskadShell/kaskad-qml-common" \
  "${KASKAD_STAGE}/shell/KaskadShell/"
cp -a -- \
  "${KASKAD_SOURCE}/config" \
  "${KASKAD_SOURCE}/release" \
  "${KASKAD_SOURCE}/session" \
  "${KASKAD_SOURCE}/start-kaskad-desktop" \
  "${KASKAD_STAGE}/"
install -m 0644 "${KASKAD_SOURCE}/VERSION" "${KASKAD_STAGE}/VERSION"

ln -s /opt/kaskad-desktop/shell/KaskadShell/core/bin/kaskad-shell "${PAYLOAD_ROOT}/usr/bin/kaskad-shell"
install -m 0755 "${PROJECT_DIR}/profile/airootfs/usr/bin/start-kaskad-desktop" \
  "${PAYLOAD_ROOT}/usr/bin/start-kaskad-desktop"
install -m 0644 "${PROJECT_DIR}/profile/airootfs/usr/share/wayland-sessions/kaskad-desktop.desktop" \
  "${PAYLOAD_ROOT}/usr/share/wayland-sessions/kaskad-desktop.desktop"
install -m 0644 "${KASKAD_SOURCE}/session/org.kaskados.Layout.desktop" \
  "${PAYLOAD_ROOT}/usr/share/applications/org.kaskados.Layout.desktop"
install -m 0644 "${KASKAD_SOURCE}/shell/KaskadShell/assets/org.kaskados.Shell.desktop" \
  "${PAYLOAD_ROOT}/usr/share/applications/org.kaskados.Shell.desktop"
install -m 0644 "${KASKAD_SOURCE}/session/org.kaskados.layout.xml" \
  "${PAYLOAD_ROOT}/usr/share/mime/packages/org.kaskados.layout.xml"
install -m 0644 "${KASKAD_SOURCE}/session/kaskaddesktop-portals.conf" \
  "${PAYLOAD_ROOT}/usr/share/xdg-desktop-portal/kaskaddesktop-portals.conf"
install -m 0644 "${KASKAD_SOURCE}/session/70-kaskados-input.rules" \
  "${PAYLOAD_ROOT}/usr/lib/udev/rules.d/70-kaskados-input.rules"
install -m 0644 "${KASKAD_SOURCE}/portal/data/kaskad.portal" \
  "${PAYLOAD_ROOT}/usr/share/xdg-desktop-portal/portals/kaskad.portal"
sed 's|@KASKAD_PORTAL_EXECUTABLE@|/opt/kaskad-desktop/build/portal/bin/xdg-desktop-portal-kaskad|g' \
  "${KASKAD_SOURCE}/session/org.freedesktop.impl.portal.desktop.kaskad.desktop.in" \
  > "${PAYLOAD_ROOT}/usr/share/applications/org.freedesktop.impl.portal.desktop.kaskad.desktop"
sed 's|@KASKAD_PORTAL_EXECUTABLE@|/opt/kaskad-desktop/build/portal/bin/xdg-desktop-portal-kaskad|g' \
  "${KASKAD_SOURCE}/session/org.freedesktop.impl.portal.desktop.kaskad.service.in" \
  > "${PAYLOAD_ROOT}/usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kaskad.service"
sed 's|@KASKAD_PORTAL_EXECUTABLE@|/opt/kaskad-desktop/build/portal/bin/xdg-desktop-portal-kaskad|g' \
  "${KASKAD_SOURCE}/session/xdg-desktop-portal-kaskad.service.in" \
  > "${PAYLOAD_ROOT}/usr/lib/systemd/user/xdg-desktop-portal-kaskad.service"

install -m 0644 "${KASKAD_SOURCE}/release/release.json" \
  "${PAYLOAD_ROOT}/usr/share/kaskados/release.json"
find "${KASKAD_SOURCE}/release/releases" -maxdepth 1 -type f -name '*.json' \
  -exec install -m 0644 -t "${PAYLOAD_ROOT}/usr/share/kaskados/releases" -- {} +
install -Dm0755 "${PROJECT_DIR}/components/system-update/kaskados-system-update" \
  "${PAYLOAD_ROOT}/usr/lib/kaskados/kaskados-system-update"
install -Dm0644 "${PROJECT_DIR}/components/system-update/org.kaskados.system-update.policy" \
  "${PAYLOAD_ROOT}/usr/share/polkit-1/actions/org.kaskados.system-update.policy"
install -Dm0755 "${PROJECT_DIR}/components/system-update/kaskados-hotspot-control" \
  "${PAYLOAD_ROOT}/usr/lib/kaskados/kaskados-hotspot-control"
install -Dm0644 "${PROJECT_DIR}/components/system-update/kaskados-hotspot-routing.service" \
  "${PAYLOAD_ROOT}/usr/lib/systemd/system/kaskados-hotspot-routing.service"
install -Dm0644 "${PROJECT_DIR}/components/system-update/kaskados-hotspot-routing.timer" \
  "${PAYLOAD_ROOT}/usr/lib/systemd/system/kaskados-hotspot-routing.timer"
install -Dm0755 "${PROJECT_DIR}/components/system-update/90-kaskados-hotspot-routing" \
  "${PAYLOAD_ROOT}/usr/lib/NetworkManager/dispatcher.d/90-kaskados-hotspot-routing"
install -Dm0644 "${PROJECT_DIR}/components/system-update/org.kaskados.hotspot-control.policy" \
  "${PAYLOAD_ROOT}/usr/share/polkit-1/actions/org.kaskados.hotspot-control.policy"
install -Dm0644 "${PROJECT_DIR}/components/system-update/90-kaskados-hotspot.conf" \
  "${PAYLOAD_ROOT}/usr/lib/NetworkManager/conf.d/90-kaskados-hotspot.conf"
install -Dm0644 "${PROJECT_DIR}/components/system-update/90-kaskados-hotspot-analytics.conf" \
  "${PAYLOAD_ROOT}/etc/NetworkManager/dnsmasq-shared.d/90-kaskados-hotspot-analytics.conf"
install -Dm0644 "${PROJECT_DIR}/components/file-manager/io.kaskados.Files.desktop" \
  "${PAYLOAD_ROOT}/usr/share/applications/io.kaskados.Files.desktop"
install -Dm0644 "${PROJECT_DIR}/components/file-manager/mimeapps.list" \
  "${PAYLOAD_ROOT}/etc/xdg/mimeapps.list"

install -Dm0755 "${REGALIA_BIN}/regalia" "${PAYLOAD_ROOT}/usr/bin/regalia"
install -Dm0755 "${REGALIA_BIN}/regaliad" "${PAYLOAD_ROOT}/usr/bin/regaliad"
install -Dm0755 "${REGALIA_BIN}/regalia-engine" \
  "${PAYLOAD_ROOT}/usr/lib/regalia/regalia-engine"
install -Dm0755 "${REGALIA_BIN}/sing-box" "${PAYLOAD_ROOT}/usr/lib/regalia/sing-box"
install -Dm0644 "${REGALIA_SOURCE}/packaging/systemd/regalia-engine@.service" \
  "${PAYLOAD_ROOT}/usr/lib/systemd/system/regalia-engine@.service"
install -Dm0644 "${REGALIA_SOURCE}/packaging/systemd/user/regaliad.service" \
  "${PAYLOAD_ROOT}/usr/lib/systemd/user/regaliad.service"
install -Dm0644 "${REGALIA_SOURCE}/packaging/polkit/50-regalia-engine.rules" \
  "${PAYLOAD_ROOT}/usr/share/polkit-1/rules.d/50-regalia-engine.rules"
install -d -m 0755 "${PAYLOAD_ROOT}/etc/systemd/user/default.target.wants"
ln -s /usr/lib/systemd/user/regaliad.service \
  "${PAYLOAD_ROOT}/etc/systemd/user/default.target.wants/regaliad.service"

# The payload is copied directly out of build trees instead of going through
# `cmake --install`. Refuse any ELF that still remembers a developer checkout;
# such a package may appear healthy locally and fail on every other machine.
while IFS= read -r -d '' artifact; do
  readelf -h "${artifact}" >/dev/null 2>&1 || continue
  dynamic_section="$(readelf -d "${artifact}" 2>/dev/null || true)"
  if grep -E '\((RPATH|RUNPATH)\)' <<<"${dynamic_section}" \
      | grep -Eq '(/home/|/build/|/tmp/)'; then
    printf 'Недопустимый путь сборки в ELF %s:\n%s\n' \
      "${artifact}" \
      "$(grep -E '\((RPATH|RUNPATH)\)' <<<"${dynamic_section}")" >&2
    exit 1
  fi
done < <(find "${PAYLOAD_ROOT}" -type f -print0)

desktop_pkgver="$(tr '-' '_' < "${KASKAD_SOURCE}/VERSION" | tr -d '\n')"
desktop_pkgrel="${KASKADOS_DESKTOP_PKGREL:-1}"
(
  cd -- "${PACKAGE_SOURCE}"
  env \
    KASKADOS_DESKTOP_PAYLOAD="${PAYLOAD_ROOT}" \
    KASKADOS_DESKTOP_PKGVER="${desktop_pkgver}" \
    KASKADOS_DESKTOP_PKGREL="${desktop_pkgrel}" \
    BUILDDIR="${PACKAGE_ROOT}/work" \
    PKGDEST="${PACKAGE_DEST}" \
    SRCDEST="${PACKAGE_ROOT}/sources" \
    makepkg --cleanbuild --force --nodeps
)

mapfile -t packages < <(
  find "${PACKAGE_DEST}" -maxdepth 1 -type f \
    -name "kaskados-desktop-${desktop_pkgver}-${desktop_pkgrel}-x86_64.pkg.tar.zst" -print
)
(( ${#packages[@]} == 1 )) || die 'не удалось однозначно определить пакет kaskados-desktop'

package_metadata="$(bsdtar -xOf "${packages[0]}" .PKGINFO)"
if grep -qx 'depend = kwin' <<<"${package_metadata}"; then
  die 'пакет рабочей среды не должен зависеть от системного kwin'
fi
if bsdtar -tf "${packages[0]}" \
    | grep -Eq '/build/compositor/bin/kwin/plugins/.*\.so$'; then
  die 'в пакет рабочей среды попал динамический модуль композитора'
fi
if bsdtar -tf "${packages[0]}" \
    | grep -Eq '/build/compositor/bin/libkwin\.so'; then
  die 'в пакет рабочей среды попало устаревшее имя библиотеки KWin'
fi
if bsdtar -tf "${packages[0]}" \
    | grep -Eq '/build/compositor/bin/org/kde/kwin/private/'; then
  die 'в пакет рабочей среды попал приватный QML-интерфейс KWin'
fi
if bsdtar -tf "${packages[0]}" \
    | grep -Eq '/build/compositor/bin/(kwin_eis_prompter|kwin_(dialog|killer)_helper|kwin_wayland_wrapper|kwindowprop|kwin5_update_default_rules|kwin-[0-9][^/]*)$'; then
  die 'в пакет рабочей среды попал устаревший вспомогательный файл KWin'
fi
if bsdtar -tf "${packages[0]}" \
    | grep -Eq '(^|/)opt/kaskad-desktop/(INSTALL_INFO|installer/)'; then
  die 'в пакет рабочей среды попала устаревшая GitHub-схема установки'
fi
for required_cursor_file in \
  usr/share/icons/KaskadCursorBase/cursors/left_ptr \
  usr/share/icons/KaskadCursorBase/cursors/text \
  usr/share/icons/KaskadCursorBase/cursors/nwse-resize \
  opt/kaskad-desktop/build/compositor/bin/kaskad-cursor-exporter; do
  bsdtar -tf "${packages[0]}" | grep -Fqx "${required_cursor_file}" \
    || die "в пакете отсутствует обязательный файл курсора ${required_cursor_file}"
done

printf 'Пакет рабочей среды готов: %s\n' "${packages[0]}"
