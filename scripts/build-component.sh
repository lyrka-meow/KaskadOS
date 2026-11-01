#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly BUILD_ROOT="${PROJECT_DIR}/build"
readonly KASKAD_SOURCE="${PROJECT_DIR}/components/kaskad-desktop"
readonly KASKAD_BUILD="${BUILD_ROOT}/kaskad-desktop"
readonly BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"
readonly KASKAD_BUILD_JOBS="${KASKAD_BUILD_JOBS:-8}"
# shellcheck source=/dev/null
source "${PROJECT_DIR}/components/regalia/packaging/sing-box.env"
readonly SING_BOX_ARCHIVE="sing-box-${SING_BOX_VERSION}-linux-amd64.tar.gz"

die() { printf 'Ошибка: %s\n' "$*" >&2; exit 1; }
[[ $# == 1 ]] || die 'использование: build-component.sh КОМПОНЕНТ'
component=$1

case "${component}" in
  calamares)
    command -v cmake >/dev/null || die 'не найден cmake'
    build_dir="${BUILD_ROOT}/calamares"
    env -u LD_LIBRARY_PATH cmake -S "${PROJECT_DIR}/components/calamares" -B "${build_dir}" -G Ninja \
      -DBUILD_SCHEMA_TESTING=OFF -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr -DINSTALL_CONFIG=ON -DWITH_QT6=ON
    env -u LD_LIBRARY_PATH cmake --build "${build_dir}" --parallel "${BUILD_JOBS}"
    ;;
  installer-compositor)
    command -v cmake >/dev/null || die 'не найден cmake'
    build_dir="${BUILD_ROOT}/kaskad-installer-compositor"
    env -u LD_LIBRARY_PATH cmake -S "${KASKAD_SOURCE}/compositor" -B "${build_dir}" -G Ninja \
      -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release -DCMAKE_BUILD_RPATH_USE_ORIGIN=ON \
      -DKASKAD_INSTALLER_MINIMAL=ON -DKWIN_BUILD_ACTIVITIES=OFF \
      -DKWIN_BUILD_DECORATIONS=OFF -DKWIN_BUILD_GLOBALSHORTCUTS=OFF \
      -DKWIN_BUILD_QACCESSIBILITYCLIENT=OFF -DKWIN_BUILD_SCREENLOCKER=OFF -DKWIN_BUILD_X11=OFF
    env -u LD_LIBRARY_PATH cmake --build "${build_dir}" --target kaskad-installer --parallel "${BUILD_JOBS}"
    ;;
  kaskad-compositor)
    command -v cmake >/dev/null || die 'не найден cmake'
    build_dir="${KASKAD_BUILD}/compositor"
    shortcuts_sysroot="${BUILD_ROOT}/repository-bootstrap/global-shortcuts-sysroot"
    shortcuts_cmake="${shortcuts_sysroot}/usr/lib/cmake/KGlobalAccelD"
    [[ -f "${shortcuts_cmake}/KGlobalAccelDConfig.cmake" ]] \
      || die 'не подготовлен kaskados-globalacceld; сначала подготовьте локальные компоненты'
    env -u LD_LIBRARY_PATH cmake -S "${KASKAD_SOURCE}/compositor" -B "${build_dir}" -G Ninja \
      -DBUILD_TESTING=OFF -DKWIN_BUILD_ACTIVITIES=OFF -DKWIN_BUILD_SCREENLOCKER=OFF \
      -DKGlobalAccelD_DIR="${shortcuts_cmake}" -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_BUILD_RPATH_USE_ORIGIN=ON \
      -DCMAKE_INSTALL_RPATH='$ORIGIN' -DCMAKE_INSTALL_PREFIX=/opt/kaskad-desktop
    env -u LD_LIBRARY_PATH cmake --build "${build_dir}" --target kaskad-compositor \
      --parallel "${KASKAD_BUILD_JOBS}"
    KASKAD_BUILD_ROOT="${build_dir}" \
    KASKAD_EXTRA_LIBRARY_PATH="${shortcuts_sysroot}/usr/lib" \
      "${KASKAD_SOURCE}/scripts/smoke-virtual.sh"
    ;;
  kaskad-portal)
    command -v cmake >/dev/null || die 'не найден cmake'
    build_dir="${KASKAD_BUILD}/portal"
    env -u LD_LIBRARY_PATH cmake -S "${KASKAD_SOURCE}/portal" -B "${build_dir}" -G Ninja \
      -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
      -DCMAKE_BUILD_RPATH_USE_ORIGIN=ON -DCMAKE_INSTALL_RPATH='$ORIGIN' \
      -DCMAKE_INSTALL_PREFIX=/opt/kaskad-desktop
    env -u LD_LIBRARY_PATH cmake --build "${build_dir}" --parallel "${KASKAD_BUILD_JOBS}"
    rm -f -- "${build_dir}/bin/notificationportaltest" \
      "${build_dir}/bin/xdgshortcuttest" "${build_dir}/bin/inputcapturebarriertest"
    ;;
  kaskad-shell)
    command -v cmake >/dev/null || die 'не найден cmake'
    module_build="${KASKAD_BUILD}/quickshell-kaskad"
    shell_build="${KASKAD_BUILD}/shell-source"
    env -u LD_LIBRARY_PATH cmake -S "${KASKAD_SOURCE}/quickshell/kaskad-module" \
      -B "${module_build}" -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_BUILD_RPATH_USE_ORIGIN=ON \
      -DCMAKE_INSTALL_RPATH='$ORIGIN' -DCMAKE_INSTALL_PREFIX=/opt/kaskad-desktop
    env -u LD_LIBRARY_PATH cmake --build "${module_build}" --parallel "${KASKAD_BUILD_JOBS}"
    rm -rf -- "${shell_build}"
    mkdir -p -- "${shell_build}"
    cp -a -- "${KASKAD_SOURCE}/shell/KaskadShell/." "${shell_build}/"
    env GOPROXY=off GOSUMDB=off \
      make -C "${shell_build}/core" VERSION="$(tr -d '\n' < "${KASKAD_SOURCE}/VERSION")" \
        COMMIT=kaskados build
    ;;
  regalia)
    command -v go >/dev/null || die 'не найден go'
    regalia_source="${PROJECT_DIR}/components/regalia"
    regalia_bin="${BUILD_ROOT}/regalia/bin"
    mkdir -p -- "${regalia_bin}"
    rm -f -- "${regalia_bin}/regalia" "${regalia_bin}/regaliad" \
      "${regalia_bin}/regalia-engine"
    (
      cd -- "${regalia_source}"
      env GOPROXY=off GOSUMDB=off CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
        go build -trimpath -ldflags '-s -w' -o "${regalia_bin}/regalia" ./cmd/regalia
      env GOPROXY=off GOSUMDB=off CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
        go build -trimpath -ldflags '-s -w' -o "${regalia_bin}/regaliad" ./cmd/regaliad
      env GOPROXY=off GOSUMDB=off CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
        go build -trimpath -ldflags '-s -w' -o "${regalia_bin}/regalia-engine" ./cmd/regalia-engine
    )
    ;;
  sing-box)
    command -v curl >/dev/null || die 'не найден curl'
    command -v tar >/dev/null || die 'не найден tar'
    source_cache="${BUILD_ROOT}/source-cache"
    regalia_build="${BUILD_ROOT}/regalia"
    archive="${source_cache}/${SING_BOX_ARCHIVE}"
    mkdir -p -- "${source_cache}" "${regalia_build}/bin"
    curl --fail --location --retry 5 --output "${archive}.part" \
      "https://github.com/${SING_BOX_REPOSITORY}/releases/download/v${SING_BOX_VERSION}/${SING_BOX_ARCHIVE}"
    printf '%s  %s\n' "${SING_BOX_SHA256}" "${archive}.part" | sha256sum --check --status \
      || die 'контрольная сумма sing-box не совпала'
    mv -- "${archive}.part" "${archive}"
    rm -rf -- "${regalia_build}/sing-box-${SING_BOX_VERSION}-linux-amd64"
    tar -xzf "${archive}" -C "${regalia_build}"
    install -m 0755 \
      "${regalia_build}/sing-box-${SING_BOX_VERSION}-linux-amd64/sing-box" \
      "${regalia_build}/bin/sing-box"
    ;;
  *) die "неизвестный компонент: ${component}" ;;
esac

# The built component has changed, but the packaged ISO payload has not yet
# been regenerated. Never allow an older completeness marker to enable ISO.
rm -f -- \
  "${BUILD_ROOT}/iso-profile.ready" \
  "${BUILD_ROOT}/iso-offline.ready" \
  "${BUILD_ROOT}/iso-resolved-packages.tsv"
printf 'Компонент %s собран заново.\n' "${component}"
