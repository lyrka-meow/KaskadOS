#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

rm -f -- \
  "${PROJECT_DIR}/build/iso-offline.ready" \
  "${PROJECT_DIR}/build/iso-resolved-packages.tsv"
KASKADOS_REUSE_COMPONENTS=1 "${SCRIPT_DIR}/prepare-live-profile.sh"

printf 'Готовые компоненты упакованы в профиль ISO.\n'
printf 'Теперь обновите локальный кэш пакетов перед сборкой образа.\n'
