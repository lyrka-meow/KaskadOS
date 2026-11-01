#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

die() { printf 'Ошибка: %s\n' "$*" >&2; exit 1; }
[[ ${1:-} == sing-box ]] || die 'поддерживается только компонент sing-box'
command -v curl >/dev/null 2>&1 || die 'не найдена команда curl'

# shellcheck source=/dev/null
source "${PROJECT_DIR}/components/regalia/packaging/sing-box.env"
latest_url=$(curl --fail --location --silent --show-error --output /dev/null \
  --write-out '%{url_effective}' \
  "https://github.com/${SING_BOX_REPOSITORY}/releases/latest")
latest=${latest_url##*/v}
[[ -n "${latest}" && "${latest}" != "${latest_url}" ]] \
  || die 'GitHub не вернул версию последнего релиза sing-box'
printf '@@COMPONENT@@\tsing-box\t%s\t%s\n' "${SING_BOX_VERSION}" "${latest}"
