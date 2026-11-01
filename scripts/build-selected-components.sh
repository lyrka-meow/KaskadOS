#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly COMPONENT_BUILDER="${SCRIPT_DIR}/build-component.sh"

die() {
  printf 'Ошибка: %s\n' "$*" >&2
  exit 1
}

(( $# > 0 )) || die 'не выбрано ни одного компонента'
[[ -x "${COMPONENT_BUILDER}" ]] || die 'не найден сборщик компонентов'

for component in "$@"; do
  case "${component}" in
    calamares|installer-compositor|kaskad-compositor|kaskad-portal|kaskad-shell|regalia) ;;
    *) die "компонент нельзя собрать этой командой: ${component}" ;;
  esac
done

printf 'Выбрано компонентов: %d\n' "$#"
for component in "$@"; do
  printf '\n[%s] Сборка начата.\n' "${component}"
  "${COMPONENT_BUILDER}" "${component}"
done

printf '\nВсе выбранные компоненты собраны. Остальные компоненты не изменялись.\n'
