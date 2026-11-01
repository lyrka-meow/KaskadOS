#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly MANIFEST="${PROJECT_DIR}/components/regalia/packaging/sing-box.env"
readonly BUILD_ROOT="${PROJECT_DIR}/build"

die() { printf 'Ошибка: %s\n' "$*" >&2; exit 1; }
for command_name in curl python3 sha256sum tar; do
  command -v "${command_name}" >/dev/null 2>&1 || die "не найдена команда ${command_name}"
done
# shellcheck source=/dev/null
source "${MANIFEST}"

temporary=$(mktemp -d)
trap 'rm -rf -- "${temporary}"' EXIT
api_json="${temporary}/release.json"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh api "repos/${SING_BOX_REPOSITORY}/releases/latest" > "${api_json}"
else
  curl --fail --location --silent --show-error \
    -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/${SING_BOX_REPOSITORY}/releases/latest" \
    -o "${api_json}"
fi

mapfile -t release < <(python3 - "${api_json}" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
version = str(data.get("tag_name", "")).removeprefix("v")
archive_name = f"sing-box-{version}-linux-amd64.tar.gz"
archive_url = ""
archive_sha256 = ""
for asset in data.get("assets", []):
    name = asset.get("name", "")
    url = asset.get("browser_download_url", "")
    if name == archive_name:
        archive_url = url
        archive_sha256 = str(asset.get("digest", "")).removeprefix("sha256:")
print(version)
print(archive_name)
print(archive_url)
print(archive_sha256)
PY
)
version=${release[0]:-}
archive_name=${release[1]:-}
archive_url=${release[2]:-}
sha256=${release[3]:-}
[[ -n "${version}" && -n "${archive_url}" && "${sha256}" =~ ^[0-9a-fA-F]{64}$ ]] \
  || die 'в последнем релизе sing-box не найдены архив amd64 или доверенный SHA-256'

archive="${temporary}/${archive_name}"
curl --fail --location --retry 5 --output "${archive}" "${archive_url}"
printf '%s  %s\n' "${sha256}" "${archive}" | sha256sum --check --status \
  || die 'контрольная сумма загруженного sing-box не совпала'

source_cache="${BUILD_ROOT}/source-cache"
regalia_build="${BUILD_ROOT}/regalia"
mkdir -p -- "${source_cache}" "${regalia_build}/bin"
install -m 0644 "${archive}" "${source_cache}/${archive_name}"
rm -rf -- "${regalia_build}/sing-box-${version}-linux-amd64"
tar -xzf "${archive}" -C "${regalia_build}"
install -m 0755 "${regalia_build}/sing-box-${version}-linux-amd64/sing-box" \
  "${regalia_build}/bin/sing-box"

manifest_new="${temporary}/sing-box.env"
cat > "${manifest_new}" <<EOF
# Единственный источник версии внешнего движка Regalia.
SING_BOX_REPOSITORY=${SING_BOX_REPOSITORY}
SING_BOX_VERSION=${version}
SING_BOX_SHA256=${sha256,,}
EOF
install -m 0644 "${manifest_new}" "${MANIFEST}"
rm -f -- \
  "${BUILD_ROOT}/iso-profile.ready" \
  "${BUILD_ROOT}/iso-offline.ready" \
  "${BUILD_ROOT}/iso-resolved-packages.tsv"
printf 'sing-box обновлён: %s -> %s\n' "${SING_BOX_VERSION}" "${version}"
