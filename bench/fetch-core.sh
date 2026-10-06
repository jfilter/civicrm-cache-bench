#!/usr/bin/env bash
# Runs on the benchmark host: stores a CiviCRM Standalone tarball as image/core/<name>.tar.gz
# and its resolved URL and sha256 as image/core/<name>.txt.
# Usage: bench/fetch-core.sh master https://download.civicrm.org/latest/civicrm-NIGHTLY-standalone.tar.gz
set -euo pipefail
cd "$(dirname "$0")/.."
name=${1:?usage: bench/fetch-core.sh <name> <url>} url=${2:?usage: bench/fetch-core.sh <name> <url>}
[[ $name != stable ]] || { echo "\"stable\" is the civikitchen core" >&2; exit 2; }
resolved=$(curl -fsSL -o "image/core/$name.tar.gz" -w '%{url_effective}' "$url")
printf '%s %s\n' "${resolved%%\?*}" "$(sha256sum "image/core/$name.tar.gz" | cut -d' ' -f1)" > "image/core/$name.txt"
cat "image/core/$name.txt"
