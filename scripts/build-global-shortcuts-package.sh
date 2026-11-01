#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly PACKAGE_SOURCE="${PROJECT_DIR}/repository/packages/kaskados-globalacceld"
readonly BUILD_ROOT="${KASKADOS_GLOBAL_SHORTCUTS_BUILD_ROOT:-${PROJECT_DIR}/build/global-shortcuts-package}"
readonly PACKAGE_DEST="${KASKADOS_PACKAGE_DEST:-${PROJECT_DIR}/out/packages/x86_64}"

die() {
  printf 'Ошибка: %s\n' "$*" >&2
  exit 1
}

command -v makepkg >/dev/null 2>&1 || die 'не найдена команда makepkg'
(( EUID != 0 )) || die 'пакет нужно собирать обычным пользователем'
[[ "$(uname -m)" == x86_64 ]] || die 'сборка поддерживается только на x86_64'
[[ -f "${PACKAGE_SOURCE}/PKGBUILD" ]] || die 'не найден PKGBUILD'

install -d -m 0755 "${BUILD_ROOT}/work" "${BUILD_ROOT}/sources" "${PACKAGE_DEST}"
(
  cd -- "${PACKAGE_SOURCE}"
  env \
    BUILDDIR="${BUILD_ROOT}/work" \
    PKGDEST="${PACKAGE_DEST}" \
    SRCDEST="${BUILD_ROOT}/sources" \
    makepkg --cleanbuild --force --nodeps
)

mapfile -t packages < <(
  find "${PACKAGE_DEST}" -maxdepth 1 -type f \
    -name 'kaskados-globalacceld-*-x86_64.pkg.tar.zst' -printf '%T@ %p\n' \
    | grep -v '/kaskados-globalacceld-debug-' \
    | sort -nr | head -n 1 | cut -d ' ' -f 2-
)
(( ${#packages[@]} == 1 )) || die 'не удалось определить собранный пакет'
printf 'Пакет движка сочетаний готов: %s\n' "${packages[0]}"
