#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly BUILD_ROOT="${PROJECT_DIR}/build"
readonly PROFILE_DIR="${PROFILE_DIR:-${BUILD_ROOT}/iso-profile}"
readonly ONLINE_CONF="${PROFILE_DIR}/pacman.conf"
readonly PACKAGE_LIST="${PROFILE_DIR}/packages.x86_64"
readonly CACHE_DIR="${BUILD_ROOT}/package-cache"
readonly SYNC_DB="${BUILD_ROOT}/iso-cache-pacman-db"
readonly OFFLINE_DB="${BUILD_ROOT}/iso-offline-pacman-db"
readonly BOOTSTRAP_REPOSITORY="${BUILD_ROOT}/repository-bootstrap/x86_64"
readonly OFFLINE_REPOSITORY="${BUILD_ROOT}/offline-repository/x86_64"
readonly OFFLINE_CONF="${BUILD_ROOT}/iso-offline-pacman.conf"
readonly READY_MARKER="${BUILD_ROOT}/iso-offline.ready"
readonly PROFILE_READY_MARKER="${BUILD_ROOT}/iso-profile.ready"
readonly RESOLVED_PACKAGES="${BUILD_ROOT}/iso-resolved-packages.tsv"

die() {
  printf 'Ошибка: %s\n' "$*" >&2
  exit 1
}

for command_name in fakeroot paccache pacman repo-add; do
  command -v "${command_name}" >/dev/null 2>&1 || die "не найдена команда ${command_name}"
done

[[ -f "${ONLINE_CONF}" && -f "${PACKAGE_LIST}" ]] \
  || die 'профиль ISO ещё не подготовлен; запустите make iso-update'
[[ -f "${PROFILE_READY_MARKER}" ]] \
  || die 'профиль ISO устарел; сначала упакуйте готовые компоненты'
[[ -f "${BOOTSTRAP_REPOSITORY}/kaskados-bootstrap.db.tar.gz" ]] \
  || die 'локальные пакеты KaskadOS ещё не собраны; запустите make iso-update'

# Any cache mutation invalidates the previous completeness proof. The marker is
# restored only after pacman resolves the whole ISO from the rebuilt local repo.
rm -f -- "${READY_MARKER}" "${RESOLVED_PACKAGES}"

install -d -m 0755 "${CACHE_DIR}" "${SYNC_DB}"
fakeroot pacman \
  --config "${ONLINE_CONF}" \
  --dbpath "${SYNC_DB}" \
  -Syy >/dev/null \
  || die 'не удалось обновить каталоги пакетов'

packages=()
mapfile -t all_iso_packages < <(grep -Ev '^[[:space:]]*(#|$)' "${PACKAGE_LIST}")
partial_update=false
if (( $# > 0 )); then
  partial_update=true
  packages=( "$@" )
  printf 'Обновляю в кэше: %s\n' "${packages[*]}"
else
  packages=( "${all_iso_packages[@]}" )
  printf 'Обновляю полный кэш ISO (%d требований)...\n' "${#packages[@]}"
fi

(( ${#packages[@]} > 0 )) || die 'список пакетов ISO пуст'
fakeroot pacman \
  --config "${ONLINE_CONF}" \
  --dbpath "${SYNC_DB}" \
  --cachedir "${CACHE_DIR}" \
  -Sw --noconfirm "${packages[@]}" \
  || die 'не удалось заполнить кэш ISO'
paccache --remove --keep 1 --cachedir "${CACHE_DIR}" >/dev/null

# Record the exact transaction pacman resolves from the current repository
# catalogs. The first column is the real package name and the second is the
# exact version selected for the ISO. This is the source of truth for showing
# transitive dependencies separately from the root requirements.
resolved_tmp="${RESOLVED_PACKAGES}.tmp"
pacman \
  --config "${ONLINE_CONF}" \
  --dbpath "${SYNC_DB}" \
  -Sp --print-format $'%n\t%v' "${all_iso_packages[@]}" \
  | awk -F '\t' 'NF >= 2 && !seen[$1]++ { print $1 "\t" $2 }' \
  | LC_ALL=C sort -t $'\t' -k1,1 \
  > "${resolved_tmp}" \
  || die 'не удалось разрешить точный состав пакетов ISO'
[[ -s "${resolved_tmp}" ]] || die 'список разрешённых пакетов ISO пуст'
mv -- "${resolved_tmp}" "${RESOLVED_PACKAGES}"

# Rebuild a single file:// repository from the persistent official-package
# cache and the locally built KaskadOS packages. Package files are linked, not
# copied, so the offline repository does not consume the same disk space twice.
install -d -m 0755 "${OFFLINE_REPOSITORY}"
find "${OFFLINE_REPOSITORY}" -mindepth 1 -maxdepth 1 -delete
declare -A resolved_versions=()
while IFS=$'\t' read -r package_name package_version; do
  [[ -n "${package_name}" && -n "${package_version}" ]] || continue
  resolved_versions["${package_name}"]="${package_version}"
done < "${RESOLVED_PACKAGES}"
mapfile -d '' -t available_archives < <(find "${CACHE_DIR}" "${BOOTSTRAP_REPOSITORY}" \
  -maxdepth 1 -type f \( -name '*.pkg.tar.zst' -o -name '*.pkg.tar.xz' \) \
  ! -name '*-debug-*.pkg.tar.*' -print0)
mapfile -t available_info < <(pacman -Qp "${available_archives[@]}" 2>/dev/null)
(( ${#available_archives[@]} == ${#available_info[@]} )) \
  || die 'не удалось прочитать метаданные всех пакетов кэша'
for index in "${!available_archives[@]}"; do
  package_path="${available_archives[index]}"
  package_info="${available_info[index]}"
  package_name="${package_info%% *}"
  package_version="${package_info#* }"
  [[ -n "${resolved_versions["${package_name}"]:-}" ]] || continue
  [[ "${resolved_versions["${package_name}"]}" == "${package_version}" ]] || continue
  ln -sfn "${package_path}" "${OFFLINE_REPOSITORY}/$(basename -- "${package_path}")"
done

mapfile -d '' -t cached_packages < <(
  find "${OFFLINE_REPOSITORY}" -maxdepth 1 -type l \
    \( -name '*.pkg.tar.zst' -o -name '*.pkg.tar.xz' \) -print0
)
(( ${#cached_packages[@]} > 0 )) || die 'офлайн-репозиторий оказался пуст'
repo-add "${OFFLINE_REPOSITORY}/kaskados-offline.db.tar.gz" "${cached_packages[@]}" >/dev/null

# Keep only [options] from the online configuration. Every repository below is
# local, so mkarchiso has no URL it could contact during `make iso`.
awk '
  /^\[[^]]+\]$/ && $0 != "[options]" { exit }
  { print }
' "${ONLINE_CONF}" > "${OFFLINE_CONF}"
sed -i \
  -e '/^CacheDir[[:space:]]*=/d' \
  -e '/^XferCommand[[:space:]]*=/d' \
  -e "/^\[options\]$/a CacheDir = ${CACHE_DIR}/" \
  "${OFFLINE_CONF}"
cat >> "${OFFLINE_CONF}" <<EOF

[kaskados-offline]
SigLevel = PackageOptional DatabaseNever TrustAll
Server = file://${OFFLINE_REPOSITORY}
EOF

if [[ -e "${OFFLINE_DB}" ]]; then
  rm -rf -- "${OFFLINE_DB}"
fi
install -d -m 0755 "${OFFLINE_DB}"
fakeroot pacman \
  --config "${OFFLINE_CONF}" \
  --dbpath "${OFFLINE_DB}" \
  -Syy >/dev/null \
  || die 'не удалось открыть собранный офлайн-репозиторий'
if pacman \
  --config "${OFFLINE_CONF}" \
  --dbpath "${OFFLINE_DB}" \
  -Sp --print-format '%n' "${all_iso_packages[@]}" >/dev/null 2>&1; then
  touch "${READY_MARKER}"
  printf 'Офлайн-кэш ISO готов: %s\n' "${CACHE_DIR}"
else
  rm -f -- "${READY_MARKER}"
  if [[ "${partial_update}" == true ]]; then
    printf 'Выбранные пакеты сохранены. Полный кэш ISO пока не готов.\n'
  else
    die 'не удалось подготовить полный офлайн-кэш ISO'
  fi
fi
printf 'Локальный репозиторий: %s\n' "${OFFLINE_REPOSITORY}"
