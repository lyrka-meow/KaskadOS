#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly PROFILE_DIR="${PROFILE_DIR:-${PROJECT_DIR}/build/iso-profile}"
readonly WORK_DIR="${WORK_DIR:-${PROJECT_DIR}/work}"
readonly OUT_DIR="${OUT_DIR:-${PROJECT_DIR}/out}"
readonly OFFLINE_CONF="${PROJECT_DIR}/build/iso-offline-pacman.conf"
readonly READY_MARKER="${PROJECT_DIR}/build/iso-offline.ready"
readonly PROFILE_READY_MARKER="${PROJECT_DIR}/build/iso-profile.ready"
readonly RESOLVED_PACKAGES="${PROJECT_DIR}/build/iso-resolved-packages.tsv"
readonly PRIVILEGE_HELPER="${KASKADOS_PRIVILEGE_HELPER:-sudo}"

die() {
  printf 'Ошибка: %s\n' "$*" >&2
  exit 1
}

[[ -f "${PROFILE_DIR}/profiledef.sh" && -f "${PROFILE_DIR}/packages.x86_64" ]] \
  || die 'нет подготовленного профиля; запустите make iso-update'
[[ -f "${PROFILE_READY_MARKER}" ]] \
  || die 'профиль ISO устарел; сначала упакуйте готовые компоненты'
[[ -f "${OFFLINE_CONF}" && -f "${READY_MARKER}" && -s "${RESOLVED_PACKAGES}" ]] \
  || die 'офлайн-кэш не подготовлен; запустите make iso-update'
[[ ! "${PROFILE_DIR}/packages.x86_64" -nt "${READY_MARKER}" ]] \
  || die 'список пакетов новее кэша; запустите make iso-update'
command -v mkarchiso >/dev/null 2>&1 || die 'не найден mkarchiso; установите пакет archiso'

if [[ -e "${WORK_DIR}" ]]; then
  "${SCRIPT_DIR}/clean-work.sh"
fi
mkdir -p -- "${OUT_DIR}"

run_mkarchiso() {
  /usr/bin/mkarchiso -v -r \
    -C "${OFFLINE_CONF}" \
    -w "${WORK_DIR}" \
    -o "${OUT_DIR}" \
    "${PROFILE_DIR}"
}

printf 'Сборка ISO только из локального кэша.\n'
if (( EUID == 0 )); then
  run_mkarchiso
elif [[ "${PRIVILEGE_HELPER}" == pkexec ]]; then
  pkexec /usr/bin/mkarchiso -v -r \
    -C "${OFFLINE_CONF}" -w "${WORK_DIR}" -o "${OUT_DIR}" "${PROFILE_DIR}"
else
  [[ "${PRIVILEGE_HELPER}" == sudo ]] || die "неподдерживаемый помощник прав: ${PRIVILEGE_HELPER}"
  sudo -v
  sudo /usr/bin/mkarchiso -v -r \
    -C "${OFFLINE_CONF}" -w "${WORK_DIR}" -o "${OUT_DIR}" "${PROFILE_DIR}"
fi

printf 'Готовый ISO: %s\n' "${OUT_DIR}"
