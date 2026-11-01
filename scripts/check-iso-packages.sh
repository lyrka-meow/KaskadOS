#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly PROFILE_DIR="${PROFILE_DIR:-${PROJECT_DIR}/build/iso-profile}"
readonly ONLINE_CONF="${PROFILE_DIR}/pacman.conf"
readonly PACKAGE_LIST="${PROFILE_DIR}/packages.x86_64"
readonly SYNC_DB="${PROJECT_DIR}/build/iso-cache-pacman-db"

die() { printf 'Ошибка: %s\n' "$*" >&2; exit 1; }
for command_name in fakeroot pacman; do
  command -v "${command_name}" >/dev/null 2>&1 || die "не найдена команда ${command_name}"
done
[[ -f "${ONLINE_CONF}" && -f "${PACKAGE_LIST}" ]] || die 'профиль ISO ещё не подготовлен'

packages=( "$@" )
if (( ${#packages[@]} == 0 )); then
  mapfile -t packages < <(grep -Ev '^[[:space:]]*(#|$)' "${PACKAGE_LIST}")
fi
(( ${#packages[@]} > 0 )) || die 'не выбрано ни одного пакета'

install -d -m 0755 "${SYNC_DB}"
printf 'Обновляю только каталоги репозиториев; пакеты не скачиваются...\n'
fakeroot pacman --config "${ONLINE_CONF}" --dbpath "${SYNC_DB}" -Syy >/dev/null \
  || die 'не удалось обновить каталоги пакетов'
pacman --config "${ONLINE_CONF}" --dbpath "${SYNC_DB}" \
  -Sp --print-format $'@@PACKAGE@@\t%n\t%v' "${packages[@]}" \
  | awk -F '\t' '!seen[$2]++'
