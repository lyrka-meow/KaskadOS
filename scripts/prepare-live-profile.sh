#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly SOURCE_PROFILE="${PROJECT_DIR}/profile"
readonly BUILD_ROOT="${PROJECT_DIR}/build"
readonly COMPOSITOR_BUILD="${BUILD_ROOT}/kaskad-installer-compositor"
readonly CALAMARES_BUILD="${BUILD_ROOT}/calamares"
readonly KASKAD_DESKTOP_SOURCE="${PROJECT_DIR}/components/kaskad-desktop"
readonly KASKAD_DESKTOP_BUILD="${BUILD_ROOT}/kaskad-desktop"
readonly KASKAD_COMPOSITOR_BUILD="${KASKAD_DESKTOP_BUILD}/compositor"
readonly KASKAD_PORTAL_BUILD="${KASKAD_DESKTOP_BUILD}/portal"
readonly KASKAD_QUICKSHELL_BUILD="${KASKAD_DESKTOP_BUILD}/quickshell-kaskad"
readonly KASKAD_SHELL_BUILD="${KASKAD_DESKTOP_BUILD}/shell-source"
readonly REGALIA_SOURCE="${PROJECT_DIR}/components/regalia"
readonly REGALIA_BUILD="${BUILD_ROOT}/regalia"
readonly REGALIA_BIN="${REGALIA_BUILD}/bin"
# shellcheck source=/dev/null
source "${PROJECT_DIR}/components/regalia/packaging/sing-box.env"
readonly SING_BOX_ARCHIVE="sing-box-${SING_BOX_VERSION}-linux-amd64.tar.gz"
readonly INSTALLER_THEMES="${PROJECT_DIR}/components/installer-themes"
readonly KEYRING_PACKAGE_SOURCE="${PROJECT_DIR}/repository/packages/kaskados-keyring"
readonly DESKTOP_PACKAGE_SOURCE="${PROJECT_DIR}/repository/packages/kaskados-desktop"
readonly DGOP_BUILD_SCRIPT="${SCRIPT_DIR}/build-dgop-package.sh"
readonly GLOBAL_SHORTCUTS_BUILD_SCRIPT="${SCRIPT_DIR}/build-global-shortcuts-package.sh"
readonly GLOBAL_SHORTCUTS_SYSROOT="${BUILD_ROOT}/repository-bootstrap/global-shortcuts-sysroot"
readonly PACMAN_FETCH_SCRIPT="${SCRIPT_DIR}/pacman-fetch.sh"
readonly BOOTSTRAP_REPOSITORY="${BUILD_ROOT}/repository-bootstrap/x86_64"
readonly BOOTSTRAP_PACKAGE_CACHE="${BUILD_ROOT}/package-cache"
readonly PACMAN_CHECK_DB="${BUILD_ROOT}/iso-cache-pacman-db"
readonly SOURCE_CACHE="${BUILD_ROOT}/source-cache"
readonly NVIDIA_580XX_SOURCE="${BUILD_ROOT}/repository-bootstrap/nvidia-580xx-utils"
readonly NVIDIA_580XX_32_SOURCE="${BUILD_ROOT}/repository-bootstrap/lib32-nvidia-580xx-utils"
readonly NVIDIA_580XX_COMMIT="85c38619ce2267787d0515baa443739cb9d2883c"
readonly NVIDIA_580XX_32_COMMIT="bbe7b771c897f78e518ab4453b0bc9210ef2f201"
readonly NVIDIA_580XX_VERSION="580.178.04"
readonly NVIDIA_580XX_INSTALLER="NVIDIA-Linux-x86_64-${NVIDIA_580XX_VERSION}.run"
readonly NVIDIA_580XX_INSTALLER_SHA256="5975a86ee45bffcb626f51ae33d1169b108186a2ea47ad651e72f13fa4b6d6f9"
readonly PROFILE_DIR="${PROFILE_DIR:-${BUILD_ROOT}/iso-profile}"
readonly BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"
readonly KASKAD_BUILD_JOBS="${KASKAD_BUILD_JOBS:-8}"
readonly REUSE_COMPONENTS="${KASKADOS_REUSE_COMPONENTS:-0}"

rm -f -- \
  "${BUILD_ROOT}/iso-profile.ready" \
  "${BUILD_ROOT}/iso-offline.ready" \
  "${BUILD_ROOT}/iso-resolved-packages.tsv"

die() {
  printf 'Ошибка: %s\n' "$*" >&2
  exit 1
}

required_commands=(bsdtar cmake fakeroot ldd makepkg pacman readelf repo-add)
if [[ "${REUSE_COMPONENTS}" != 1 ]]; then
  required_commands+=(curl go make ninja sha256sum tar)
fi
for command_name in "${required_commands[@]}"; do
  command -v "${command_name}" >/dev/null 2>&1 || die "не найдена команда ${command_name}"
done

if [[ "${REUSE_COMPONENTS}" != 1 ]]; then
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
    printf 'Не установлены пакеты для сборки:\n' >&2
    printf '  %s\n' "${missing_build_packages[@]}" >&2
    printf 'Установите их командой:\n  sudo pacman -S --needed' >&2
    printf ' %q' "${missing_build_packages[@]}" >&2
    printf '\n' >&2
    exit 2
  fi
fi

[[ "$(uname -m)" == 'x86_64' ]] || die 'сборка поддерживается только на x86_64'
[[ "$(realpath -m -- "${PROFILE_DIR}")" == "${BUILD_ROOT}"/* ]] || die 'подготовленный профиль должен находиться внутри build/'
[[ -d "${INSTALLER_THEMES}/grub" ]] || die 'не найдены темы GRUB для установщика'
[[ -d "${INSTALLER_THEMES}/sddm" ]] || die 'не найдены темы SDDM для установщика'
[[ -d "${INSTALLER_THEMES}/previews" ]] || die 'не найдены превью тем для установщика'
[[ -f "${KASKAD_DESKTOP_SOURCE}/VERSION" ]] || die 'не найден исходный код KaskadDesktop'
[[ -f "${KASKAD_DESKTOP_SOURCE}/release/release.json" ]] || die 'не найден манифест выпуска KaskadDesktop'
desktop_version="$(tr -d '\n' < "${KASKAD_DESKTOP_SOURCE}/VERSION")"
release_version="$(sed -nE 's/^[[:space:]]*"version":[[:space:]]*"([^"]+)".*/\1/p' "${KASKAD_DESKTOP_SOURCE}/release/release.json")"
release_notes="$(sed -nE 's/^[[:space:]]*"releaseNotes":[[:space:]]*"([^"]+)".*/\1/p' "${KASKAD_DESKTOP_SOURCE}/release/release.json")"
[[ "${release_version}" == "${desktop_version}" ]] \
  || die "версия release.json (${release_version:-не указана}) не совпадает с VERSION (${desktop_version})"
[[ -n "${release_notes}" && -f "${KASKAD_DESKTOP_SOURCE}/release/${release_notes}" ]] \
  || die "не найден файл заметок выпуска ${release_notes:-из release.json}"
[[ -f "${PROJECT_DIR}/components/system-update/kaskados-system-update" ]] \
  || die 'не найден системный помощник обновлений'
[[ -f "${PROJECT_DIR}/components/system-update/org.kaskados.system-update.policy" ]] \
  || die 'не найдена политика системного помощника обновлений'
[[ -f "${PROJECT_DIR}/components/file-manager/io.kaskados.Files.desktop" ]] \
  || die 'не найден ярлык файлового менеджера KaskadOS'
[[ -f "${PROJECT_DIR}/components/file-manager/mimeapps.list" ]] \
  || die 'не найдены MIME-настройки файлового менеджера KaskadOS'
[[ -f "${SOURCE_PROFILE}/airootfs/usr/share/wayland-sessions/kaskad-desktop.desktop" ]] || die 'не найдена сесия KaskadOS'
[[ -f "${REGALIA_SOURCE}/go.mod" ]] || die 'не найден исходный код Regalia'
[[ -f "${REGALIA_SOURCE}/packaging/systemd/user/regaliad.service" ]] \
  || die 'не найдена пользовательская служба Regalia'
[[ -f "${KEYRING_PACKAGE_SOURCE}/PKGBUILD" ]] \
  || die 'не найден пакет kaskados-keyring'
[[ -f "${DESKTOP_PACKAGE_SOURCE}/PKGBUILD" ]] \
  || die 'не найден пакет kaskados-desktop'
[[ -x "${DGOP_BUILD_SCRIPT}" ]] || die 'не найден скрипт сборки dgop'
[[ -x "${GLOBAL_SHORTCUTS_BUILD_SCRIPT}" ]] || die 'не найден скрипт сборки движка сочетаний'
[[ -x "${PACMAN_FETCH_SCRIPT}" ]] || die 'не найден устойчивый загрузчик пакетов'

"${SCRIPT_DIR}/check-profile.sh"

if (( EUID == 0 )); then
  die 'подготовку live-профиля запускайте обычным пользователем; sudo вызовет только mkarchiso'
fi

if [[ "${REUSE_COMPONENTS}" != 1 && -e "${BUILD_ROOT}/repository-bootstrap" ]]; then
  rm -rf -- "${BUILD_ROOT}/repository-bootstrap"
fi
install -d -m 0755 \
  "${BOOTSTRAP_REPOSITORY}" \
  "${BOOTSTRAP_PACKAGE_CACHE}" \
  "${SOURCE_CACHE}" \
  "${BUILD_ROOT}/repository-bootstrap/work"
if [[ "${REUSE_COMPONENTS}" != 1 ]]; then
# Official Arch packages are expensive to download again after an unrelated
# build failure. Keep that cache, but discard locally rebuilt packages whose
# filenames can stay the same while their contents change.
find "${BOOTSTRAP_PACKAGE_CACHE}" -maxdepth 1 -type f \
  \( -name 'kaskados-keyring-*' \
     -o -name 'dgop-*' \
     -o -name 'nvidia-580xx-*' \
     -o -name 'lib32-nvidia-580xx-*' \) \
  -delete
(
  cd -- "${KEYRING_PACKAGE_SOURCE}"
  env \
    BUILDDIR="${BUILD_ROOT}/repository-bootstrap/work" \
    PKGDEST="${BOOTSTRAP_REPOSITORY}" \
    SRCDEST="${SOURCE_CACHE}" \
    makepkg --cleanbuild --force --nodeps
)
mapfile -t keyring_packages < <(
  find "${BOOTSTRAP_REPOSITORY}" -maxdepth 1 -type f \
    -name 'kaskados-keyring-*.pkg.tar.zst' -print
)
(( ${#keyring_packages[@]} == 1 )) \
  || die 'не удалось однозначно определить собранный пакет kaskados-keyring'

KASKADOS_PACKAGE_DEST="${BOOTSTRAP_REPOSITORY}" \
KASKADOS_DGOP_BUILD_ROOT="${BUILD_ROOT}/repository-bootstrap/dgop" \
  "${DGOP_BUILD_SCRIPT}"
mapfile -t dgop_packages < <(
  find "${BOOTSTRAP_REPOSITORY}" -maxdepth 1 -type f \
    -name 'dgop-[0-9]*-x86_64.pkg.tar.zst' -print
)
(( ${#dgop_packages[@]} == 1 )) \
  || die 'не удалось однозначно определить собранный пакет dgop'
KASKADOS_PACKAGE_DEST="${BOOTSTRAP_REPOSITORY}" \
KASKADOS_GLOBAL_SHORTCUTS_BUILD_ROOT="${BUILD_ROOT}/repository-bootstrap/global-shortcuts" \
  "${GLOBAL_SHORTCUTS_BUILD_SCRIPT}"
mapfile -t global_shortcuts_packages < <(
  find "${BOOTSTRAP_REPOSITORY}" -maxdepth 1 -type f \
    -name 'kaskados-globalacceld-[0-9]*-x86_64.pkg.tar.zst' -print
)
(( ${#global_shortcuts_packages[@]} == 1 )) \
  || die 'не удалось однозначно определить движок глобальных сочетаний'
rm -rf -- "${GLOBAL_SHORTCUTS_SYSROOT}"
install -d -m 0755 "${GLOBAL_SHORTCUTS_SYSROOT}"
bsdtar -xpf "${global_shortcuts_packages[0]}" -C "${GLOBAL_SHORTCUTS_SYSROOT}"
readonly GLOBAL_SHORTCUTS_CMAKE_DIR="${GLOBAL_SHORTCUTS_SYSROOT}/usr/lib/cmake/KGlobalAccelD"
[[ -f "${GLOBAL_SHORTCUTS_CMAKE_DIR}/KGlobalAccelDConfig.cmake" ]] \
  || die 'в пакете отсутствует CMake-конфигурация движка глобальных сочетаний'
repo-add "${BOOTSTRAP_REPOSITORY}/kaskados-bootstrap.db.tar.gz" \
  "${keyring_packages[0]}" \
  "${dgop_packages[0]}" \
  "${global_shortcuts_packages[0]}"

fetch_aur_snapshot() {
  local repository_url=$1
  local commit=$2
  local destination=$3
  local attempt

  git init -q "${destination}"
  git -C "${destination}" remote add origin "${repository_url}"
  for attempt in {1..8}; do
    if git \
      -c http.version=HTTP/1.1 \
      -c http.lowSpeedLimit=1024 \
      -c http.lowSpeedTime=60 \
      -C "${destination}" \
      fetch -q --no-tags --depth 1 origin "${commit}"; then
      break
    fi
    if (( attempt == 8 )); then
      die "не удалось загрузить AUR-снимок ${repository_url} после ${attempt} попыток"
    fi
    printf 'Сетевая ошибка AUR, повтор %d/8...\n' "$((attempt + 1))" >&2
    sleep "$((attempt * 2))"
  done
  git -C "${destination}" checkout -q --detach FETCH_HEAD
  [[ "$(git -C "${destination}" rev-parse HEAD)" == "${commit}" ]] \
    || die "не удалось зафиксировать AUR-снимок ${repository_url}"
}

fetch_aur_snapshot \
  'https://aur.archlinux.org/nvidia-580xx-utils.git' \
  "${NVIDIA_580XX_COMMIT}" \
  "${NVIDIA_580XX_SOURCE}"
fetch_aur_snapshot \
  'https://aur.archlinux.org/lib32-nvidia-580xx-utils.git' \
  "${NVIDIA_580XX_32_COMMIT}" \
  "${NVIDIA_580XX_32_SOURCE}"

# The NVIDIA installer is almost 400 MiB and the upstream server sometimes
# closes a TLS connection early. Keep it outside the disposable bootstrap
# tree, resume a partial download, and retry transient failures.
nvidia_installer_path="${SOURCE_CACHE}/${NVIDIA_580XX_INSTALLER}"
nvidia_installer_partial="${nvidia_installer_path}.part"
if [[ ! -f "${nvidia_installer_path}" ]]; then
  curl_args=(
    --fail
    --location
    --retry 12
    --retry-all-errors
    --retry-delay 5
    --connect-timeout 30
    --output "${nvidia_installer_partial}"
  )
  [[ -f "${nvidia_installer_partial}" ]] && curl_args+=(--continue-at -)
  curl "${curl_args[@]}" \
    "https://download.nvidia.com/XFree86/Linux-x86_64/${NVIDIA_580XX_VERSION}/${NVIDIA_580XX_INSTALLER}"
  if ! printf '%s  %s\n' "${NVIDIA_580XX_INSTALLER_SHA256}" "${nvidia_installer_partial}" | sha256sum --check --status; then
    mv -- "${nvidia_installer_partial}" "${nvidia_installer_partial}.invalid"
    die 'контрольная сумма установщика NVIDIA не совпала'
  fi
  mv -- "${nvidia_installer_partial}" "${nvidia_installer_path}"
fi

for nvidia_source in "${NVIDIA_580XX_SOURCE}" "${NVIDIA_580XX_32_SOURCE}"; do
  (
    cd -- "${nvidia_source}"
    env \
      BUILDDIR="${BUILD_ROOT}/repository-bootstrap/work" \
      PKGDEST="${BOOTSTRAP_REPOSITORY}" \
      SRCDEST="${SOURCE_CACHE}" \
      makepkg --cleanbuild --force --nodeps
  )
done

nvidia_packages=()
for package_pattern in \
  'nvidia-580xx-dkms-[0-9]*-x86_64.pkg.tar.zst' \
  'nvidia-580xx-utils-[0-9]*-x86_64.pkg.tar.zst' \
  'lib32-nvidia-580xx-utils-[0-9]*-x86_64.pkg.tar.zst'; do
  mapfile -t matching_packages < <(
    find "${BOOTSTRAP_REPOSITORY}" -maxdepth 1 -type f -name "${package_pattern}" -print
  )
  (( ${#matching_packages[@]} == 1 )) \
    || die "не удалось однозначно определить пакет ${package_pattern}"
  nvidia_packages+=("${matching_packages[0]}")
done
repo-add "${BOOTSTRAP_REPOSITORY}/kaskados-bootstrap.db.tar.gz" \
  "${nvidia_packages[@]}"

env -u LD_LIBRARY_PATH cmake -S "${KASKAD_DESKTOP_SOURCE}/compositor" -B "${COMPOSITOR_BUILD}" -G Ninja \
  -DBUILD_TESTING=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_BUILD_RPATH_USE_ORIGIN=ON \
  -DKASKAD_INSTALLER_MINIMAL=ON \
  -DKWIN_BUILD_ACTIVITIES=OFF \
  -DKWIN_BUILD_DECORATIONS=OFF \
  -DKWIN_BUILD_GLOBALSHORTCUTS=OFF \
  -DKWIN_BUILD_QACCESSIBILITYCLIENT=OFF \
  -DKWIN_BUILD_SCREENLOCKER=OFF \
  -DKWIN_BUILD_X11=OFF
env -u LD_LIBRARY_PATH cmake --build "${COMPOSITOR_BUILD}" --target kaskad-installer --parallel "${BUILD_JOBS}"

# Removed targets can leave installable files in a reused CMake bin tree.
# Purge every legacy compositor-owned UI/script location before staging ISO
# contents so the live image has the same strict shell/compositor boundary.
rm -rf -- \
  "${KASKAD_COMPOSITOR_BUILD}"/bin/libkwin.so* \
  "${KASKAD_COMPOSITOR_BUILD}/bin/kwin/plugins" \
  "${KASKAD_COMPOSITOR_BUILD}/bin/kwin-wayland/scripts" \
  "${KASKAD_COMPOSITOR_BUILD}/bin/kwin/effects/configs" \
  "${KASKAD_COMPOSITOR_BUILD}/bin/org/kde/kwin/outputlocator" \
  "${KASKAD_COMPOSITOR_BUILD}/bin/org/kde/kwin/overview" \
  "${KASKAD_COMPOSITOR_BUILD}/bin/org/kde/kwin/showfps" \
  "${KASKAD_COMPOSITOR_BUILD}/bin/org/kde/kwin/windowview" \
  "${KASKAD_COMPOSITOR_BUILD}/bin/plasma/kcms"

rm -f -- \
  "${KASKAD_PORTAL_BUILD}/bin/notificationportaltest" \
  "${KASKAD_PORTAL_BUILD}/bin/xdgshortcuttest" \
  "${KASKAD_PORTAL_BUILD}/bin/inputcapturebarriertest"

env -u LD_LIBRARY_PATH cmake -S "${KASKAD_DESKTOP_SOURCE}/compositor" -B "${KASKAD_COMPOSITOR_BUILD}" -G Ninja \
  -DBUILD_TESTING=OFF \
  -DKWIN_BUILD_ACTIVITIES=OFF \
  -DKWIN_BUILD_SCREENLOCKER=OFF \
  -DKGlobalAccelD_DIR="${GLOBAL_SHORTCUTS_CMAKE_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
  -DCMAKE_BUILD_RPATH_USE_ORIGIN=ON \
  -DCMAKE_INSTALL_RPATH='$ORIGIN' \
  -DCMAKE_INSTALL_PREFIX=/opt/kaskad-desktop
env -u LD_LIBRARY_PATH cmake --build "${KASKAD_COMPOSITOR_BUILD}" \
  --target kaskad-compositor \
  --parallel "${KASKAD_BUILD_JOBS}"
[[ -z "$(find "${KASKAD_COMPOSITOR_BUILD}/bin/kwin/plugins" -maxdepth 1 -type f -name '*.so' -print -quit 2>/dev/null)" ]] \
  || die 'сборка KaskadDesktop неожиданно создала динамический модуль'
KASKAD_BUILD_ROOT="${KASKAD_COMPOSITOR_BUILD}" \
KASKAD_EXTRA_LIBRARY_PATH="${GLOBAL_SHORTCUTS_SYSROOT}/usr/lib" \
  "${KASKAD_DESKTOP_SOURCE}/scripts/smoke-virtual.sh"
rm -f -- "${KASKAD_COMPOSITOR_BUILD}/bin/qtwaylandscanner_kde"

env -u LD_LIBRARY_PATH cmake -S "${KASKAD_DESKTOP_SOURCE}/portal" -B "${KASKAD_PORTAL_BUILD}" -G Ninja \
  -DBUILD_TESTING=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
  -DCMAKE_BUILD_RPATH_USE_ORIGIN=ON \
  -DCMAKE_INSTALL_RPATH='$ORIGIN' \
  -DCMAKE_INSTALL_PREFIX=/opt/kaskad-desktop
env -u LD_LIBRARY_PATH cmake --build "${KASKAD_PORTAL_BUILD}" --parallel "${KASKAD_BUILD_JOBS}"
rm -f -- \
  "${KASKAD_PORTAL_BUILD}/bin/notificationportaltest" \
  "${KASKAD_PORTAL_BUILD}/bin/xdgshortcuttest" \
  "${KASKAD_PORTAL_BUILD}/bin/inputcapturebarriertest"

env -u LD_LIBRARY_PATH cmake -S "${KASKAD_DESKTOP_SOURCE}/quickshell/kaskad-module" -B "${KASKAD_QUICKSHELL_BUILD}" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
  -DCMAKE_BUILD_RPATH_USE_ORIGIN=ON \
  -DCMAKE_INSTALL_RPATH='$ORIGIN' \
  -DCMAKE_INSTALL_PREFIX=/opt/kaskad-desktop
env -u LD_LIBRARY_PATH cmake --build "${KASKAD_QUICKSHELL_BUILD}" --parallel "${KASKAD_BUILD_JOBS}"

if [[ -e "${KASKAD_SHELL_BUILD}" ]]; then
  rm -rf -- "${KASKAD_SHELL_BUILD}"
fi
mkdir -p -- "${KASKAD_SHELL_BUILD}"
cp -a -- "${KASKAD_DESKTOP_SOURCE}/shell/KaskadShell/." "${KASKAD_SHELL_BUILD}/"
make -C "${KASKAD_SHELL_BUILD}/core" \
  VERSION="$(tr -d '\n' < "${KASKAD_DESKTOP_SOURCE}/VERSION")" \
  COMMIT=kaskados \
  build

if [[ -e "${REGALIA_BUILD}" ]]; then
  rm -rf -- "${REGALIA_BUILD}"
fi
mkdir -p -- "${REGALIA_BIN}"
(
  cd -- "${REGALIA_SOURCE}"
  env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags '-s -w' -o "${REGALIA_BIN}/regalia" ./cmd/regalia
  env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags '-s -w' -o "${REGALIA_BIN}/regaliad" ./cmd/regaliad
  env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags '-s -w' -o "${REGALIA_BIN}/regalia-engine" ./cmd/regalia-engine
)
curl -fL --retry 3 --silent --show-error \
  "https://github.com/${SING_BOX_REPOSITORY}/releases/download/v${SING_BOX_VERSION}/${SING_BOX_ARCHIVE}" \
  -o "${REGALIA_BUILD}/${SING_BOX_ARCHIVE}"
printf '%s  %s\n' "${SING_BOX_SHA256}" "${REGALIA_BUILD}/${SING_BOX_ARCHIVE}" \
  | sha256sum -c -
tar -xzf "${REGALIA_BUILD}/${SING_BOX_ARCHIVE}" -C "${REGALIA_BUILD}"
install -m 0755 \
  "${REGALIA_BUILD}/sing-box-${SING_BOX_VERSION}-linux-amd64/sing-box" \
  "${REGALIA_BIN}/sing-box"

env -u LD_LIBRARY_PATH cmake -S "${PROJECT_DIR}/components/calamares" -B "${CALAMARES_BUILD}" -G Ninja \
  -DBUILD_SCHEMA_TESTING=OFF \
  -DBUILD_TESTING=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DINSTALL_CONFIG=ON \
  -DWITH_QT6=ON
env -u LD_LIBRARY_PATH cmake --build "${CALAMARES_BUILD}" --parallel "${BUILD_JOBS}"
else
  mapfile -t keyring_packages < <(
    find "${BOOTSTRAP_REPOSITORY}" -maxdepth 1 -type f \
      -name 'kaskados-keyring-*.pkg.tar.zst' -print
  )
  mapfile -t dgop_packages < <(
    find "${BOOTSTRAP_REPOSITORY}" -maxdepth 1 -type f \
      -name 'dgop-[0-9]*-x86_64.pkg.tar.zst' -print
  )
  mapfile -t global_shortcuts_packages < <(
    find "${BOOTSTRAP_REPOSITORY}" -maxdepth 1 -type f \
      -name 'kaskados-globalacceld-[0-9]*-x86_64.pkg.tar.zst' -print
  )
  nvidia_packages=()
  for package_pattern in \
    'nvidia-580xx-dkms-[0-9]*-x86_64.pkg.tar.zst' \
    'nvidia-580xx-utils-[0-9]*-x86_64.pkg.tar.zst' \
    'lib32-nvidia-580xx-utils-[0-9]*-x86_64.pkg.tar.zst'; do
    mapfile -t matching_packages < <(
      find "${BOOTSTRAP_REPOSITORY}" -maxdepth 1 -type f -name "${package_pattern}" -print
    )
    (( ${#matching_packages[@]} == 1 )) \
      || die "нет готового локального пакета ${package_pattern}; сначала загрузите и соберите его"
    nvidia_packages+=("${matching_packages[0]}")
  done
  (( ${#keyring_packages[@]} == 1 )) || die 'нет готового пакета kaskados-keyring'
  (( ${#dgop_packages[@]} == 1 )) || die 'нет готового пакета dgop'
  (( ${#global_shortcuts_packages[@]} == 1 )) \
    || die 'нет готового пакета kaskados-globalacceld'
  [[ -x "${CALAMARES_BUILD}/calamares" ]] || die 'Calamares ещё не собран'
  [[ -x "${COMPOSITOR_BUILD}/bin/kaskad-installer" ]] \
    || die 'композитор установщика ещё не собран'
  [[ -x "${KASKAD_COMPOSITOR_BUILD}/bin/kaskad-compositor" ]] \
    || die 'композитор Kaskad DE ещё не собран'
  [[ -x "${KASKAD_PORTAL_BUILD}/bin/xdg-desktop-portal-kaskad" ]] \
    || die 'портал Kaskad DE ещё не собран'
  [[ -x "${KASKAD_SHELL_BUILD}/core/bin/kaskad-shell" ]] \
    || die 'оболочка Kaskad DE ещё не собрана'
  [[ -x "${REGALIA_BIN}/regalia" && -x "${REGALIA_BIN}/regaliad" \
      && -x "${REGALIA_BIN}/regalia-engine" ]] || die 'Regalia VPN ещё не собрана'
  [[ -x "${REGALIA_BIN}/sing-box" ]] || die 'sing-box ещё не скачан'
  printf 'Использую готовые локальные сборки компонентов; пересборка не выполняется.\n'
fi

if [[ -e "${PROFILE_DIR}" ]]; then
  rm -rf -- "${PROFILE_DIR}"
fi
mkdir -p -- "${PROFILE_DIR}"
cp -a -- "${SOURCE_PROFILE}/." "${PROFILE_DIR}/"

# Для сборки ISO используем официальные CDN Arch и внешний curl с HTTP/1.1,
# продолжением загрузки и повторами. Это защищает pacstrap от рассинхронных
# зеркал и случайных HTTP/2/TLS-обрывов. В установленную систему по-прежнему
# попадает исходный pacman.conf с обычным mirrorlist.
sed -i \
  '/^Include = \/etc\/pacman.d\/mirrorlist$/c\Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch\
Server = https://fastly.mirror.pkgbuild.com/$repo/os/$arch' \
  "${PROFILE_DIR}/pacman.conf"
grep -Fqx 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' \
  "${PROFILE_DIR}/pacman.conf" \
  || die 'не удалось настроить основное зеркало Arch для сборки ISO'
if grep -Fqx 'Include = /etc/pacman.d/mirrorlist' "${PROFILE_DIR}/pacman.conf"; then
  die 'в профиле сборки осталась зависимость от списка зеркал хост-системы'
fi
sed -i \
  -e 's/^ParallelDownloads = .*/ParallelDownloads = 3/' \
  -e '/^ParallelDownloads = 3$/a DisableDownloadTimeout' \
  -e "/^#XferCommand = \/usr\/bin\/curl/a XferCommand = ${PACMAN_FETCH_SCRIPT} %o %u" \
  "${PROFILE_DIR}/pacman.conf"
grep -Fqx 'DisableDownloadTimeout' "${PROFILE_DIR}/pacman.conf" \
  || die 'не удалось отключить тайм-аут медленной загрузки для сборки ISO'
grep -Fqx "XferCommand = ${PACMAN_FETCH_SCRIPT} %o %u" \
  "${PROFILE_DIR}/pacman.conf" \
  || die 'не удалось настроить устойчивую загрузку пакетов для сборки ISO'

# Временные пакеты bootstrap-репозитория пересобираются под теми же версиями.
# Отдельный свежий кэш не позволяет pacman взять одноимённый пакет от прошлой сборки.
sed -i \
  "s|^#CacheDir.*|CacheDir = ${BOOTSTRAP_PACKAGE_CACHE}/|" \
  "${PROFILE_DIR}/pacman.conf"
grep -Fqx "CacheDir = ${BOOTSTRAP_PACKAGE_CACHE}/" "${PROFILE_DIR}/pacman.conf" \
  || die 'не удалось настроить отдельный кэш пакетов для сборки ISO'

install -Dm0644 "${SOURCE_PROFILE}/pacman.conf" \
  "${PROFILE_DIR}/airootfs/etc/pacman.conf"
sed -i \
  "/^\[core\]$/i [kaskados]\nSigLevel = Required DatabaseRequired\nServer = https://repo.kaskados.xyz/\$arch\n" \
  "${PROFILE_DIR}/airootfs/etc/pacman.conf"
sed -i \
  "/^\[core\]$/i [kaskados-bootstrap]\nSigLevel = PackageOptional DatabaseNever TrustAll\nServer = file://${BOOTSTRAP_REPOSITORY}\n" \
  "${PROFILE_DIR}/pacman.conf"
printf '%s\n' 'kaskados-keyring' >> "${PROFILE_DIR}/packages.x86_64"
printf '%s\n' 'dgop' >> "${PROFILE_DIR}/packages.x86_64"
printf '%s\n' \
  'nvidia-580xx-dkms' \
  'nvidia-580xx-utils' \
  'lib32-nvidia-580xx-utils' \
  'nvidia-prime' \
  >> "${PROFILE_DIR}/packages.x86_64"

install -d -m 0755 \
  "${PROFILE_DIR}/airootfs/usr/share/kaskados-installer/theme-pool" \
  "${PROFILE_DIR}/airootfs/usr/share/kaskados-installer/theme-previews"
cp -a -- \
  "${INSTALLER_THEMES}/grub" \
  "${INSTALLER_THEMES}/sddm" \
  "${INSTALLER_THEMES}/SOURCES.md" \
  "${PROFILE_DIR}/airootfs/usr/share/kaskados-installer/theme-pool/"
cp -a -- \
  "${INSTALLER_THEMES}/previews/." \
  "${PROFILE_DIR}/airootfs/usr/share/kaskados-installer/theme-previews/"

DESTDIR="${PROFILE_DIR}/airootfs" env -u LD_LIBRARY_PATH cmake --install "${CALAMARES_BUILD}" --strip

install -d -m 0755 "${PROFILE_DIR}/airootfs/opt/kaskados-installer/bin"
install -m 0755 \
  "${COMPOSITOR_BUILD}/bin/kaskad-installer" \
  "${PROFILE_DIR}/airootfs/opt/kaskados-installer/bin/kaskad-installer"
cp -a -- \
  "${COMPOSITOR_BUILD}"/bin/libkaskad-compositor.so* \
  "${PROFILE_DIR}/airootfs/opt/kaskados-installer/bin/"

readonly KASKAD_STAGE="${PROFILE_DIR}/airootfs/opt/kaskad-desktop"
install -d -m 0755 \
  "${KASKAD_STAGE}/build/compositor" \
  "${KASKAD_STAGE}/build/portal" \
  "${KASKAD_STAGE}/build/quickshell-kaskad" \
  "${KASKAD_STAGE}/shell/KaskadShell/core/bin" \
  "${PROFILE_DIR}/airootfs/usr/bin" \
  "${PROFILE_DIR}/airootfs/usr/lib/systemd/user" \
  "${PROFILE_DIR}/airootfs/usr/share/applications" \
  "${PROFILE_DIR}/airootfs/usr/share/dbus-1/services" \
  "${PROFILE_DIR}/airootfs/usr/share/xdg-desktop-portal/portals"
cp -a -- "${KASKAD_COMPOSITOR_BUILD}/bin" "${KASKAD_STAGE}/build/compositor/"
cp -a -- "${KASKAD_PORTAL_BUILD}/bin" "${KASKAD_STAGE}/build/portal/"
cp -a -- "${KASKAD_QUICKSHELL_BUILD}/Kaskad" "${KASKAD_STAGE}/build/quickshell-kaskad/"
cp -a -- "${KASKAD_QUICKSHELL_BUILD}"/libquickshell-kaskad.so* \
  "${KASKAD_STAGE}/build/quickshell-kaskad/"
install -m 0755 "${KASKAD_SHELL_BUILD}/core/bin/kaskad-shell" \
  "${KASKAD_STAGE}/shell/KaskadShell/core/bin/kaskad-shell"
ln -sfn /opt/kaskad-desktop/shell/KaskadShell/core/bin/kaskad-shell \
  "${PROFILE_DIR}/airootfs/usr/bin/kaskad-shell"
cp -a -- \
  "${KASKAD_DESKTOP_SOURCE}/shell/KaskadShell/quickshell" \
  "${KASKAD_DESKTOP_SOURCE}/shell/KaskadShell/kaskad-qml-common" \
  "${KASKAD_STAGE}/shell/KaskadShell/"
cp -a -- \
  "${KASKAD_DESKTOP_SOURCE}/config" \
  "${KASKAD_DESKTOP_SOURCE}/release" \
  "${KASKAD_DESKTOP_SOURCE}/session" \
  "${KASKAD_DESKTOP_SOURCE}/start-kaskad-desktop" \
  "${KASKAD_STAGE}/"
install -m 0644 "${KASKAD_DESKTOP_SOURCE}/session/kaskaddesktop-portals.conf" \
  "${PROFILE_DIR}/airootfs/usr/share/xdg-desktop-portal/kaskaddesktop-portals.conf"
install -m 0644 "${KASKAD_DESKTOP_SOURCE}/portal/data/kaskad.portal" \
  "${PROFILE_DIR}/airootfs/usr/share/xdg-desktop-portal/portals/kaskad.portal"
sed 's|@KASKAD_PORTAL_EXECUTABLE@|/opt/kaskad-desktop/build/portal/bin/xdg-desktop-portal-kaskad|g' \
  "${KASKAD_DESKTOP_SOURCE}/session/org.freedesktop.impl.portal.desktop.kaskad.desktop.in" \
  > "${PROFILE_DIR}/airootfs/usr/share/applications/org.freedesktop.impl.portal.desktop.kaskad.desktop"
sed 's|@KASKAD_PORTAL_EXECUTABLE@|/opt/kaskad-desktop/build/portal/bin/xdg-desktop-portal-kaskad|g' \
  "${KASKAD_DESKTOP_SOURCE}/session/org.freedesktop.impl.portal.desktop.kaskad.service.in" \
  > "${PROFILE_DIR}/airootfs/usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kaskad.service"
sed 's|@KASKAD_PORTAL_EXECUTABLE@|/opt/kaskad-desktop/build/portal/bin/xdg-desktop-portal-kaskad|g' \
  "${KASKAD_DESKTOP_SOURCE}/session/xdg-desktop-portal-kaskad.service.in" \
  > "${PROFILE_DIR}/airootfs/usr/lib/systemd/user/xdg-desktop-portal-kaskad.service"
install -m 0644 "${KASKAD_DESKTOP_SOURCE}/VERSION" "${KASKAD_STAGE}/VERSION"
install -d -m 0755 "${PROFILE_DIR}/airootfs/usr/share/kaskados/releases"
install -m 0644 "${KASKAD_DESKTOP_SOURCE}/release/release.json" \
  "${PROFILE_DIR}/airootfs/usr/share/kaskados/release.json"
find "${KASKAD_DESKTOP_SOURCE}/release/releases" -maxdepth 1 -type f -name '*.json' \
  -exec install -m 0644 -t "${PROFILE_DIR}/airootfs/usr/share/kaskados/releases" -- {} +
install -Dm0755 "${PROJECT_DIR}/components/system-update/kaskados-system-update" \
  "${PROFILE_DIR}/airootfs/usr/lib/kaskados/kaskados-system-update"
install -Dm0644 "${PROJECT_DIR}/components/system-update/org.kaskados.system-update.policy" \
  "${PROFILE_DIR}/airootfs/usr/share/polkit-1/actions/org.kaskados.system-update.policy"
install -Dm0755 "${PROJECT_DIR}/components/system-update/kaskados-hotspot-control" \
  "${PROFILE_DIR}/airootfs/usr/lib/kaskados/kaskados-hotspot-control"
install -Dm0644 "${PROJECT_DIR}/components/system-update/kaskados-hotspot-routing.service" \
  "${PROFILE_DIR}/airootfs/usr/lib/systemd/system/kaskados-hotspot-routing.service"
install -Dm0644 "${PROJECT_DIR}/components/system-update/kaskados-hotspot-routing.timer" \
  "${PROFILE_DIR}/airootfs/usr/lib/systemd/system/kaskados-hotspot-routing.timer"
install -Dm0755 "${PROJECT_DIR}/components/system-update/90-kaskados-hotspot-routing" \
  "${PROFILE_DIR}/airootfs/usr/lib/NetworkManager/dispatcher.d/90-kaskados-hotspot-routing"
install -Dm0644 "${PROJECT_DIR}/components/system-update/org.kaskados.hotspot-control.policy" \
  "${PROFILE_DIR}/airootfs/usr/share/polkit-1/actions/org.kaskados.hotspot-control.policy"
install -Dm0644 "${PROJECT_DIR}/components/system-update/90-kaskados-hotspot.conf" \
  "${PROFILE_DIR}/airootfs/usr/lib/NetworkManager/conf.d/90-kaskados-hotspot.conf"
install -Dm0644 "${PROJECT_DIR}/components/system-update/90-kaskados-hotspot-analytics.conf" \
  "${PROFILE_DIR}/airootfs/etc/NetworkManager/dnsmasq-shared.d/90-kaskados-hotspot-analytics.conf"
install -Dm0644 "${PROJECT_DIR}/components/file-manager/io.kaskados.Files.desktop" \
  "${PROFILE_DIR}/airootfs/usr/share/applications/io.kaskados.Files.desktop"
install -Dm0644 "${PROJECT_DIR}/components/file-manager/mimeapps.list" \
  "${PROFILE_DIR}/airootfs/etc/xdg/mimeapps.list"
install -Dm0755 "${REGALIA_BIN}/regalia" \
  "${PROFILE_DIR}/airootfs/usr/bin/regalia"
install -Dm0755 "${REGALIA_BIN}/regaliad" \
  "${PROFILE_DIR}/airootfs/usr/bin/regaliad"
install -Dm0755 "${REGALIA_BIN}/regalia-engine" \
  "${PROFILE_DIR}/airootfs/usr/lib/regalia/regalia-engine"
install -Dm0755 "${REGALIA_BIN}/sing-box" \
  "${PROFILE_DIR}/airootfs/usr/lib/regalia/sing-box"
install -Dm0644 "${REGALIA_SOURCE}/packaging/systemd/regalia-engine@.service" \
  "${PROFILE_DIR}/airootfs/usr/lib/systemd/system/regalia-engine@.service"
install -Dm0644 "${REGALIA_SOURCE}/packaging/systemd/user/regaliad.service" \
  "${PROFILE_DIR}/airootfs/usr/lib/systemd/user/regaliad.service"
install -Dm0644 "${REGALIA_SOURCE}/packaging/polkit/50-regalia-engine.rules" \
  "${PROFILE_DIR}/airootfs/usr/share/polkit-1/rules.d/50-regalia-engine.rules"
install -d -m 0755 "${PROFILE_DIR}/airootfs/etc/systemd/user/default.target.wants"
ln -sfn /usr/lib/systemd/user/regaliad.service \
  "${PROFILE_DIR}/airootfs/etc/systemd/user/default.target.wants/regaliad.service"

declare -A runtime_packages=()
declare -A system_libraries=()
readonly STAGED_ROOT="${PROFILE_DIR}/airootfs"
readonly STAGED_LIBRARY_PATH="${STAGED_ROOT}/usr/lib:${STAGED_ROOT}/opt/kaskados-installer/bin:${KASKAD_STAGE}/build/compositor/bin:${KASKAD_STAGE}/build/portal/bin:${KASKAD_STAGE}/build/quickshell-kaskad"

# ISO artifacts also come straight from build directories. Catch an absolute
# developer path before dependency discovery can accidentally make it work.
while IFS= read -r -d '' artifact; do
  readelf -h "${artifact}" >/dev/null 2>&1 || continue
  dynamic_section="$(readelf -d "${artifact}" 2>/dev/null || true)"
  if grep -E '\((RPATH|RUNPATH)\)' <<<"${dynamic_section}" \
      | grep -Eq '(/home/|/build/|/tmp/)'; then
    printf 'Недопустимый путь сборки в ELF ISO %s:\n%s\n' \
      "${artifact}" \
      "$(grep -E '\((RPATH|RUNPATH)\)' <<<"${dynamic_section}")" >&2
    exit 1
  fi
done < <(find \
  "${PROFILE_DIR}/airootfs/usr/bin" \
  "${PROFILE_DIR}/airootfs/usr/lib" \
  "${PROFILE_DIR}/airootfs/opt/kaskados-installer/bin" \
  "${PROFILE_DIR}/airootfs/opt/kaskad-desktop" \
  -type f -print0)

for package_name in \
  brightnessctl \
  cava \
  curl \
  ddcutil \
  mesa \
  pacman-contrib \
  pciutils \
  polkit \
  qt6-5compat \
  qt6-connectivity \
  qt6-imageformats \
  qt6-multimedia \
  qt6-positioning \
  qt6-sensors \
  qt6-svg \
  qt6-wayland \
  quickshell \
  ttf-dejavu \
  xkeyboard-config \
  xorg-xwayland; do
  runtime_packages["${package_name}"]=1
done

while IFS= read -r -d '' artifact; do
  if ! readelf -h "${artifact}" >/dev/null 2>&1; then
    continue
  fi

  ldd_output="$(env LD_LIBRARY_PATH="${STAGED_LIBRARY_PATH}" ldd "${artifact}" 2>/dev/null || true)"
  if grep -Fq 'not found' <<< "${ldd_output}"; then
    printf 'Неразрешённые библиотеки в %s:\n%s\n' "${artifact}" "${ldd_output}" >&2
    exit 1
  fi

  while IFS= read -r library; do
    [[ -e "${library}" ]] || continue
    [[ "${library}" != "${STAGED_ROOT}/"* ]] || continue
    system_libraries["${library}"]=1
  done < <(awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\//) { sub(/\(.*/, "", $i); print $i } }' <<< "${ldd_output}")
done < <(find \
  "${PROFILE_DIR}/airootfs/usr/bin" \
  "${PROFILE_DIR}/airootfs/usr/lib" \
  "${PROFILE_DIR}/airootfs/opt/kaskados-installer/bin" \
  "${PROFILE_DIR}/airootfs/opt/kaskad-desktop" \
  -type f -print0)

if (( ${#system_libraries[@]} > 0 )); then
  package_owner_output="$(pacman -Qqo -- "${!system_libraries[@]}")" \
    || die 'не удалось определить пакеты системных библиотек'
  while IFS= read -r package_name; do
    [[ -n "${package_name}" ]] && runtime_packages["${package_name}"]=1
  done <<< "${package_owner_output}"
fi

# The bootstrap repository has just been created, so it is not present in the
# host's /var/lib/pacman/sync database. Synchronize into a disposable writable
# database instead of querying the stale host database. fakeroot satisfies
# pacman's root check without modifying the host package database.
if [[ "${REUSE_COMPONENTS}" != 1 ]]; then
  if [[ -e "${PACMAN_CHECK_DB}" ]]; then
    rm -rf -- "${PACMAN_CHECK_DB}"
  fi
  install -d -m 0755 "${PACMAN_CHECK_DB}"
  fakeroot pacman \
    --config "${PROFILE_DIR}/pacman.conf" \
    --dbpath "${PACMAN_CHECK_DB}" \
    -Syy >/dev/null \
    || die 'не удалось синхронизировать базы для проверки пакетов'
else
  [[ -d "${PACMAN_CHECK_DB}/sync" ]] \
    || die 'нет локальных каталогов пакетов; сначала выполните проверку пакетов'
  ln -sfn "${BOOTSTRAP_REPOSITORY}/kaskados-bootstrap.db.tar.gz" \
    "${PACMAN_CHECK_DB}/sync/kaskados-bootstrap.db"
fi
pacman \
  --config "${PROFILE_DIR}/pacman.conf" \
  --dbpath "${PACMAN_CHECK_DB}" \
  -Si "${!runtime_packages[@]}" >/dev/null \
  || die 'один или несколько пакетов времени выполнения отсутствуют в репозиториях ISO'

for package_name in "${!runtime_packages[@]}"; do
  printf '%s\n' "${package_name}" >> "${PROFILE_DIR}/packages.x86_64"
done

desktop_pkgver="$(tr '-' '_' < "${KASKAD_DESKTOP_SOURCE}/VERSION" | tr -d '\n')"
(
  cd -- "${DESKTOP_PACKAGE_SOURCE}"
  env \
    KASKADOS_DESKTOP_PAYLOAD="${PROFILE_DIR}/airootfs" \
    KASKADOS_DESKTOP_PKGVER="${desktop_pkgver}" \
    BUILDDIR="${BUILD_ROOT}/repository-bootstrap/work" \
    PKGDEST="${BOOTSTRAP_REPOSITORY}" \
    SRCDEST="${SOURCE_CACHE}" \
    makepkg --cleanbuild --force --nodeps
)
mapfile -t desktop_packages < <(
  find "${BOOTSTRAP_REPOSITORY}" -maxdepth 1 -type f \
    -name "kaskados-desktop-${desktop_pkgver}-*.pkg.tar.zst" -print
)
(( ${#desktop_packages[@]} == 1 )) \
  || die 'не удалось однозначно определить собранный пакет kaskados-desktop'

for executable_path in \
  opt/kaskad-desktop/build/compositor/bin/kaskad-compositor \
  opt/kaskad-desktop/build/portal/bin/xdg-desktop-portal-kaskad \
  opt/kaskad-desktop/session/prepare-user-config \
  opt/kaskad-desktop/session/run-kaskad \
  opt/kaskad-desktop/shell/KaskadShell/core/bin/kaskad-shell \
  opt/kaskad-desktop/shell/KaskadShell/quickshell/scripts/system-info.sh \
  opt/kaskad-desktop/shell/KaskadShell/quickshell/scripts/system-maintenance.sh \
  opt/kaskad-desktop/start-kaskad-desktop \
  usr/bin/regalia \
  usr/bin/regaliad \
  usr/bin/start-kaskad-desktop \
  usr/lib/regalia/regalia-engine \
  usr/lib/regalia/sing-box; do
  archive_mode="$(bsdtar -tvf "${desktop_packages[0]}" "${executable_path}" | awk 'NR == 1 { print $1 }')"
  [[ "${archive_mode}" == '-rwxr-xr-x' ]] \
    || die "в пакете kaskados-desktop неверные права ${archive_mode:-отсутствуют} для ${executable_path}"
done

repo-add "${BOOTSTRAP_REPOSITORY}/kaskados-bootstrap.db.tar.gz" \
  "${desktop_packages[0]}"

# KaskadDesktop и встроенные компоненты сначала собираются в airootfs,
# который используется как payload для пакета. После сборки убираем точно
# эти файлы из профиля: в готовую систему их должен устанавливать и обновлять pacman.
while IFS= read -r package_path; do
  [[ -n "${package_path}" ]] || continue
  case "${package_path}" in
    /*|..|../*|*/../*)
      die "небезопасный путь в пакете kaskados-desktop: ${package_path}"
      ;;
  esac

  staged_path="${PROFILE_DIR}/airootfs/${package_path#./}"
  if [[ -L "${staged_path}" || -f "${staged_path}" ]]; then
    rm -f -- "${staged_path}"
  fi
done < <(bsdtar -tf "${desktop_packages[0]}")

printf '%s\n' 'kaskados-desktop' >> "${PROFILE_DIR}/packages.x86_64"

LC_ALL=C sort -u -o "${PROFILE_DIR}/packages.x86_64" "${PROFILE_DIR}/packages.x86_64"

touch "${BUILD_ROOT}/iso-profile.ready"

printf 'Подготовлен live-профиль: %s\n' "${PROFILE_DIR}"
printf 'Композитор: %s\n' "${PROFILE_DIR}/airootfs/opt/kaskados-installer/bin/kaskad-installer"
printf 'Calamares:  %s\n' "${PROFILE_DIR}/airootfs/usr/bin/calamares"
printf 'Пакет DE:   %s\n' "${desktop_packages[0]}"
