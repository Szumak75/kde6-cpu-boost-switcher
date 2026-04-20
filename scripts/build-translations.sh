#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOMAIN="plasma_applet_io.github.szumak75.cpu-boost-switcher"
PO_DIR="${ROOT_DIR}/po"
LOCALE_DIR="${ROOT_DIR}/package/contents/locale"

mkdir -p "${LOCALE_DIR}"

for po_file in "${PO_DIR}"/*.po; do
    lang="$(basename "${po_file}" .po)"
    target_dir="${LOCALE_DIR}/${lang}/LC_MESSAGES"
    mkdir -p "${target_dir}"
    msgfmt "${po_file}" -o "${target_dir}/${DOMAIN}.mo"
done
