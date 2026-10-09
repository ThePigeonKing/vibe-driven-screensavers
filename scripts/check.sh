#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

if [[ "${1:-}" == "--help" || "$#" -gt 1 ]]; then
  printf 'Usage: %s [all|terminal|pacman|city|neon]\n' "$0"
  printf 'Runs model checks and loads Release .saver bundles if they have been built.\n'
  exit 0
fi
select_projects "${1:-all}"
configure_xcode
cd "$repo_root"
mkdir -p build/checks
compiler_arguments=(-parse-as-library -O -module-cache-path "$repo_root/build/checks/module-cache")

for key in "${project_keys[@]}"; do
  case "$key" in
    terminal) sources=(Terminal/Shared/TelemetryModel.swift Terminal/Tools/TestTelemetry.swift) ;;
    pacman) sources=(Pacman/Shared/MazeGame.swift Pacman/Tools/TestMazeGame.swift) ;;
    city) sources=(City/Shared/CitySceneModel.swift City/Tools/TestCityScene.swift) ;;
    neon) sources=(Neon/Shared/NeonAnimationModel.swift Neon/Tools/TestNeonAnimation.swift) ;;
  esac
  printf 'Checking %s model...\n' "$key"
  xcrun swiftc "${compiler_arguments[@]}" "${sources[@]}" -o "build/checks/test-$key"
  "build/checks/test-$key"
done

xcrun swiftc "${compiler_arguments[@]}" -framework ScreenSaver \
  Tools/VerifySaverBundle.swift -o build/checks/verify-saver
for key in "${project_keys[@]}"; do
  configure_project "$key"
  bundle="$derived_path/Build/Products/Release/$product_name.saver"
  if [[ -d "$bundle" ]]; then
    build/checks/verify-saver "$bundle"
  else
    printf 'Bundle load skipped: build %s with ./scripts/build.sh %s.\n' "$product_name" "$key"
  fi
done
