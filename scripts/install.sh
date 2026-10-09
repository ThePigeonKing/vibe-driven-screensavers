#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

if [[ "${1:-}" == "--help" || "$#" -gt 1 ]]; then
  printf 'Usage: %s [all|terminal|pacman|city|neon]\n' "$0"
  printf 'Copies previously built Release modules to ~/Library/Screen Savers.\n'
  exit 0
fi
if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'Installation requires macOS.\n' >&2
  exit 1
fi
select_projects "${1:-all}"

# Check every input before copying so a missing build cannot cause a partial install.
for key in "${project_keys[@]}"; do
  configure_project "$key"
  bundle="$derived_path/Build/Products/Release/$product_name.saver"
  if [[ ! -d "$bundle" ]]; then
    printf 'Missing %s. Run ./scripts/build.sh %s first.\n' "$bundle" "$key" >&2
    exit 1
  fi
done

install_dir="$HOME/Library/Screen Savers"
mkdir -p "$install_dir"
for key in "${project_keys[@]}"; do
  configure_project "$key"
  ditto "$derived_path/Build/Products/Release/$product_name.saver" "$install_dir/$product_name.saver"
  printf 'Installed: %s/%s.saver\n' "$install_dir" "$product_name"
done
printf 'Reopen System Settings and choose a saver under Wallpaper > Screen Saver > Other.\n'
