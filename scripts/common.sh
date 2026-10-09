#!/bin/bash

# Sourced by the command-line helpers; compatible with macOS Bash 3.2.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

configure_project() {
  saver_key="$1"
  case "$saver_key" in
    terminal) project_file="Terminal/AlarmTerminal.xcodeproj"; product_name="AlarmTerminal" ;;
    pacman) project_file="Pacman/Pacman.xcodeproj"; product_name="AutoPacman" ;;
    city) project_file="City/PixelCity.xcodeproj"; product_name="PixelCity" ;;
    neon) project_file="Neon/NeonDistrict.xcodeproj"; product_name="NeonDistrict" ;;
    *) printf 'Unknown project: %s. Choose terminal, pacman, city, neon or all.\n' "$saver_key" >&2; return 2 ;;
  esac
  derived_path="$repo_root/build/$saver_key"
}

select_projects() {
  if [[ "$1" == "all" ]]; then
    project_keys=(terminal pacman city neon)
  else
    configure_project "$1"
    project_keys=("$1")
  fi
}

configure_xcode() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'These projects require macOS and the full Xcode application.\n' >&2
    return 1
  fi
  task_developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
  if [[ "$task_developer_dir" == */CommandLineTools && -d /Applications/Xcode.app/Contents/Developer ]]; then
    task_developer_dir="/Applications/Xcode.app/Contents/Developer"
  fi
  if [[ ! -x "$task_developer_dir/usr/bin/xcodebuild" ]]; then
    printf 'Install full Xcode, or set DEVELOPER_DIR to Xcode.app/Contents/Developer.\n' >&2
    return 1
  fi
  export DEVELOPER_DIR="$task_developer_dir"
}
