#!/bin/bash

set -euo pipefail

# Initialize colors
init_colors() {
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  RED=$(tput setaf 1)
  BLUE=$(tput setaf 4)
  BOLD=$(tput bold)
  RESET=$(tput sgr0)
}

# Check for required commands
check_dependencies() {
  local missing=()
  for cmd in chezmoi fzf-tmux git tput; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    echo "${RED}خطا: دستورات ضروری وجود ندارند: ${missing[*]}${RESET}" >&2
    exit 1
  fi
}

# Function to handle renamed files
handle_renamed_file() {
  local filepath="$1"
  echo "${BLUE}♻️ فایل تغییر نام داده شده شناسایی شد: $filepath${RESET}"

  # First forget the old file
  chezmoi forget "$filepath" || {
    echo "${YELLOW}⚠️ خطا در حذف فایل قدیمی، از destroy استفاده می‌کنم...${RESET}"
    chezmoi destroy "$filepath"
  }

  # The new filename should be tracked automatically by chezmoi
}

# Main processing function
process_selected_files() {
  local selected="$1"
  local filepath status

  while IFS= read -r line; do
    [ -z "$line" ] && continue

    status=$(echo "$line" | awk '{print $1}')
    filepath=$(echo "$line" | awk '{print $2}' | sed "s|^~|$HOME|")

    case "$status" in
    M | A | AM)
      echo "➕ افزودن/ویرایش فایل: $filepath"
      chezmoi add "$filepath"
      ;;
    R | D)
      echo "❌ حذف فایل: $filepath"
      chezmoi forget "$filepath" || chezmoi destroy "$filepath"
      ;;
    DA | AD)
      handle_renamed_file "$filepath"
      ;;
    *)
      echo "${YELLOW}⚠️ وضعیت ناشناخته '$status' برای $filepath. نادیده گرفته می‌شود...${RESET}" >&2
      ;;
    esac
  done <<<"$selected"
}

# Rest of the script remains the same...
