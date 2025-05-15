#!/bin/bash

# Best practices:
# 1. Use consistent quoting
# 2. Add more error handling
# 3. Better variable naming
# 4. Add comments for clarity
# 5. Handle edge cases
# 6. Use functions for better organization
# 7. Validate dependencies

set -euo pipefail

# Initialize colors
init_colors() {
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  RED=$(tput setaf 1)
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
    echo "${RED}Error: Missing required commands: ${missing[*]}${RESET}" >&2
    exit 1
  fi
}

# Main function to handle chezmoi operations
handle_chezmoi_changes() {
  echo "${GREEN}${BOLD}🔍 Detecting dotfile changes with chezmoi...${RESET}"

  local chezmoi_changes
  chezmoi_changes=$(chezmoi status || {
    echo "${RED}Error: Failed to get chezmoi status${RESET}" >&2
    exit 1
  })

  if [ -z "$chezmoi_changes" ]; then
    echo "✅ No changes found."
    return 0
  fi

  local selected
  selected=$(echo "$chezmoi_changes" | fzf-tmux --multi --prompt="Select files to sync > " || true)

  if [ -z "$selected" ]; then
    echo "⚠️ No files selected."
    return 1
  fi

  process_selected_files "$selected"
}

# Process each selected file based on its status
process_selected_files() {
  local selected="$1"
  local filepath status short_status

  echo "$selected" | while read -r line; do
    # Skip empty lines
    [ -z "$line" ] && continue

    status=$(echo "$line" | awk '{print $1}')
    filepath=$(echo "$line" | awk '{print $2}' | sed "s|^~|$HOME|")
    short_status=${status:0:1} # First character of status

    case "$short_status" in
    M | A)
      echo "➕ Adding/modifying file: $filepath"
      chezmoi add "$filepath" || {
        echo "${YELLOW}Warning: Failed to add $filepath${RESET}" >&2
        continue
      }
      ;;
    R | D)
      # Handle both R (removed) and D (deleted)
      echo "❌ Removing file: $filepath"
      chezmoi remove "$filepath" || {
        echo "${YELLOW}Warning: Failed to remove $filepath${RESET}" >&2
        continue
      }
      ;;
    DA)
      # Handle renamed files (deleted in working tree)
      echo "🔄 Detected renamed file: $filepath (will be removed)"
      chezmoi remove "$filepath" || {
        echo "${YELLOW}Warning: Failed to remove renamed file $filepath${RESET}" >&2
        continue
      }
      ;;
    *)
      echo "${YELLOW}⚠️ Unknown or unsupported status '$status' for $filepath. Skipping...${RESET}" >&2
      ;;
    esac
  done
}

# Commit and push changes to git
sync_git_repo() {
  local repo_dir
  repo_dir=$(chezmoi source-path) || {
    echo "${RED}Error: Failed to get chezmoi source path${RESET}" >&2
    return 1
  }

  cd "$repo_dir" || {
    echo "${RED}Error: Failed to enter chezmoi source directory${RESET}" >&2
    return 1
  }

  if [ -n "$(git status --porcelain)" ]; then
    git add . || {
      echo "${RED}Error: Failed to git add changes${RESET}" >&2
      return 1
    }

    git commit -m "🔄 Sync dotfiles via chezsync" || {
      echo "${YELLOW}Warning: Failed to create commit (empty commit?)${RESET}" >&2
      return 0
    }

    git push || {
      echo "${RED}Error: Failed to push changes${RESET}" >&2
      return 1
    }

    echo "${GREEN}✅ Dotfiles synced and pushed to GitHub.${RESET}"
  else
    echo "✅ Nothing to commit."
  fi
}

main() {
  init_colors
  check_dependencies
  handle_chezmoi_changes
  sync_git_repo
}

main "$@"
