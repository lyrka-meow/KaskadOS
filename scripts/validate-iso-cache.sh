#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly BUILD_ROOT="${PROJECT_DIR}/build"
readonly PROFILE_DIR="${PROFILE_DIR:-${BUILD_ROOT}/iso-profile}"
readonly PACKAGE_LIST="${PROFILE_DIR}/packages.x86_64"
readonly ONLINE_CONF="${PROFILE_DIR}/pacman.conf"
readonly PROFILE_READY_MARKER="${BUILD_ROOT}/iso-profile.ready"
readonly READY_MARKER="${BUILD_ROOT}/iso-offline.ready"
readonly RESOLVED_PACKAGES="${BUILD_ROOT}/iso-resolved-packages.tsv"
readonly CACHE_DIR="${BUILD_ROOT}/package-cache"
readonly BOOTSTRAP_REPOSITORY="${BUILD_ROOT}/repository-bootstrap/x86_64"
readonly CANDIDATE_REPOSITORY="${BUILD_ROOT}/offline-repository-candidate/x86_64"
readonly CANDIDATE_CONF="${BUILD_ROOT}/iso-offline-candidate-pacman.conf"
readonly CANDIDATE_DB="${BUILD_ROOT}/iso-offline-candidate-pacman-db"
readonly OFFLINE_REPOSITORY="${BUILD_ROOT}/offline-repository/x86_64"
readonly OFFLINE_CONF="${BUILD_ROOT}/iso-offline-pacman.conf"
readonly OFFLINE_DB="${BUILD_ROOT}/iso-offline-pacman-db"

die() { printf 'Ошибка: %s\n' "$*" >&2; exit 1; }
stage() { printf '[%(%H:%M:%S)T] %s\n' -1 "$*"; }

stage 'Проверяю необходимые команды и подготовленный профиль ISO...'
for command_name in fakeroot pacman repo-add; do
  command -v "${command_name}" >/dev/null 2>&1 || die "не найдена команда ${command_name}"
done
[[ -f "${PROFILE_READY_MARKER}" && -f "${PACKAGE_LIST}" && -f "${ONLINE_CONF}" ]] \
  || die 'профиль ISO не подготовлен'

rm -f -- "${READY_MARKER}" "${RESOLVED_PACKAGES}"
mapfile -t all_iso_packages < <(grep -Ev '^[[:space:]]*(#|$)' "${PACKAGE_LIST}")
(( ${#all_iso_packages[@]} > 0 )) || die 'список требований ISO пуст'
stage "В профиле найдено требований: ${#all_iso_packages[@]}."

write_local_config() {
  local repository=$1
  local output=$2
  awk '
    /^\[[^]]+\]$/ && $0 != "[options]" { exit }
    { print }
  ' "${ONLINE_CONF}" > "${output}"
  sed -i \
    -e '/^CacheDir[[:space:]]*=/d' \
    -e '/^XferCommand[[:space:]]*=/d' \
    -e "/^\[options\]$/a CacheDir = ${CACHE_DIR}/" \
    "${output}"
  cat >> "${output}" <<EOF

[kaskados-offline]
SigLevel = PackageOptional DatabaseNever TrustAll
Server = file://${repository}
EOF
}

link_all_cached_packages() {
  local destination=$1
  install -d -m 0755 "${destination}"
  find "${destination}" -mindepth 1 -maxdepth 1 -delete
  while IFS= read -r -d '' package_path; do
    case "$(basename -- "${package_path}")" in
      *-debug-*.pkg.tar.*) continue ;;
    esac
    ln -sfn "${package_path}" "${destination}/$(basename -- "${package_path}")"
  done < <(find "${CACHE_DIR}" "${BOOTSTRAP_REPOSITORY}" -maxdepth 1 -type f \
    \( -name '*.pkg.tar.zst' -o -name '*.pkg.tar.xz' \) -print0)
}

stage 'Собираю единый список пакетов из локального кэша и bootstrap-репозитория...'
link_all_cached_packages "${CANDIDATE_REPOSITORY}"
mapfile -d '' -t candidate_packages < <(find "${CANDIDATE_REPOSITORY}" -maxdepth 1 \
  -type l \( -name '*.pkg.tar.zst' -o -name '*.pkg.tar.xz' \) -print0)
(( ${#candidate_packages[@]} > 0 )) || die 'локальный кэш пуст'
stage "Найдено локальных архивов: ${#candidate_packages[@]}. Создаю временную базу репозитория..."
repo-add "${CANDIDATE_REPOSITORY}/kaskados-offline.db.tar.gz" \
  "${candidate_packages[@]}" >/dev/null
stage 'Открываю временный репозиторий строго из локальных файлов...'
write_local_config "${CANDIDATE_REPOSITORY}" "${CANDIDATE_CONF}"
if [[ -e "${CANDIDATE_DB}" ]]; then rm -rf -- "${CANDIDATE_DB}"; fi
install -d -m 0755 "${CANDIDATE_DB}"
fakeroot pacman --config "${CANDIDATE_CONF}" --dbpath "${CANDIDATE_DB}" -Syy >/dev/null \
  || die 'не удалось открыть локальный кэш'

stage 'Разрешаю полный граф зависимостей ISO без обращения к сети...'
resolved_tmp="${RESOLVED_PACKAGES}.tmp"
if ! pacman --config "${CANDIDATE_CONF}" --dbpath "${CANDIDATE_DB}" \
    -Sp --print-format $'%n\t%v' "${all_iso_packages[@]}" \
    | awk -F '\t' 'NF >= 2 && !seen[$1]++ { print $1 "\t" $2 }' \
    | LC_ALL=C sort -t $'\t' -k1,1 > "${resolved_tmp}"; then
  rm -f -- "${resolved_tmp}"
  die 'в локальном кэше не хватает пакета или нужной версии; обновите кэш из сети'
fi
[[ -s "${resolved_tmp}" ]] || die 'не удалось разрешить состав ISO из локального кэша'
mv -- "${resolved_tmp}" "${RESOLVED_PACKAGES}"

declare -A resolved_versions=()
while IFS=$'\t' read -r package_name package_version; do
  resolved_versions["${package_name}"]="${package_version}"
done < "${RESOLVED_PACKAGES}"
stage "Граф разрешён: ${#resolved_versions[@]} пакетов. Проверяю версии локальных архивов..."
install -d -m 0755 "${OFFLINE_REPOSITORY}"
find "${OFFLINE_REPOSITORY}" -mindepth 1 -maxdepth 1 -delete
mapfile -t candidate_info < <(pacman -Qp "${candidate_packages[@]}" 2>/dev/null)
(( ${#candidate_packages[@]} == ${#candidate_info[@]} )) \
  || die 'не удалось прочитать метаданные всех пакетов кэша'
stage 'Отбираю только точные версии, вошедшие в разрешённый состав ISO...'
for index in "${!candidate_packages[@]}"; do
  package_path="${candidate_packages[index]}"
  package_info="${candidate_info[index]}"
  package_name="${package_info%% *}"
  package_version="${package_info#* }"
  [[ "${resolved_versions["${package_name}"]:-}" == "${package_version}" ]] || continue
  ln -sfn "$(readlink -f -- "${package_path}")" \
    "${OFFLINE_REPOSITORY}/$(basename -- "${package_path}")"
done

mapfile -d '' -t exact_packages < <(find "${OFFLINE_REPOSITORY}" -maxdepth 1 -type l \
  \( -name '*.pkg.tar.zst' -o -name '*.pkg.tar.xz' \) -print0)
(( ${#exact_packages[@]} == ${#resolved_versions[@]} )) \
  || die 'не все разрешённые пакеты найдены в кэше'
stage "Отобрано точных архивов: ${#exact_packages[@]}. Создаю итоговую базу офлайн-репозитория..."
repo-add "${OFFLINE_REPOSITORY}/kaskados-offline.db.tar.gz" "${exact_packages[@]}" >/dev/null
stage 'Проверяю итоговый репозиторий через pacman...'
write_local_config "${OFFLINE_REPOSITORY}" "${OFFLINE_CONF}"
if [[ -e "${OFFLINE_DB}" ]]; then rm -rf -- "${OFFLINE_DB}"; fi
install -d -m 0755 "${OFFLINE_DB}"
fakeroot pacman --config "${OFFLINE_CONF}" --dbpath "${OFFLINE_DB}" -Syy >/dev/null \
  || die 'не удалось открыть точный офлайн-репозиторий'
pacman --config "${OFFLINE_CONF}" --dbpath "${OFFLINE_DB}" \
  -Sp --print-format '%n' "${all_iso_packages[@]}" >/dev/null \
  || die 'точный офлайн-репозиторий не покрывает состав ISO'

touch "${READY_MARKER}"
stage "Готово. Локальный кэш полон: ${#resolved_versions[@]} пакетов. Сеть не использовалась."
