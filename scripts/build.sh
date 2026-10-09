#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

if [[ "${1:-}" == "--help" || "$#" -gt 2 ]]; then
  printf 'Usage: %s [all|terminal|pacman|city|neon] [saver|preview]\n' "$0"
  exit 0
fi
selection="${1:-all}"
build_kind="${2:-saver}"
case "$build_kind" in
  saver|preview) ;;
  *) printf 'Build kind must be saver or preview.\n' >&2; exit 2 ;;
esac
select_projects "$selection"
configure_xcode
cd "$repo_root"

for key in "${project_keys[@]}"; do
  configure_project "$key"
  if [[ "$build_kind" == "preview" ]]; then
    scheme="${product_name}Preview"
    configuration="Debug"
    destination="platform=macOS"
    extra_arguments=("ONLY_ACTIVE_ARCH=YES")
    suffix="app"
  else
    scheme="$product_name"
    configuration="Release"
    destination="generic/platform=macOS"
    extra_arguments=("ARCHS=arm64 x86_64" "ONLY_ACTIVE_ARCH=NO")
    suffix="saver"
  fi
  printf 'Building %s (%s)...\n' "$product_name" "$build_kind"
  xcodebuild -quiet -project "$project_file" -scheme "$scheme" \
    -configuration "$configuration" -destination "$destination" \
    -derivedDataPath "$derived_path" "${extra_arguments[@]}" build
  printf 'Built: %s/Build/Products/%s/%s.%s\n' "$derived_path" "$configuration" "$scheme" "$suffix"
done
