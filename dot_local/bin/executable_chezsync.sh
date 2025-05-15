#!/bin/bash
set -eo pipefail

# Configuration - commands and tools
CHEZMOI_CMD="chezmoi"
FZF_CMD="fzf"
GIT_CMD="git"

# Color definitions for terminal output
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
CYAN=$(tput setaf 6)
BOLD=$(tput bold)
RESET=$(tput sgr0)

#----------------------------------------------------------
# Core Functions with Complete Rename Handling
#----------------------------------------------------------

# Get and normalize file changes from chezmoi
get_changes() {
  # Process chezmoi status output and normalize status codes
  $CHEZMOI_CMD status | awk '{
    status = $1
    path = $2
    # Normalize status codes:
    # M = Modified, A = Added, D = Deleted, DA = Renamed (old file)
    if (status == "MM" || status == "M") status = "M"
    else if (status == "A") status = "A"
    else if (status == "D" || status == "R") status = "D"
    else if (status == "DA") status = "DA"  # Keep rename status distinct
    print status, path
  }'
}

# Display changes in fzf interface for user selection
select_changes() {
  local changes="$1"

  echo "$changes" | awk -F'\t' '{
    status = $1
    path = $2
    # Convert status codes to human-readable format
    if (status == "M") action = "Modified"
    else if (status == "A") action = "Added"
    else if (status == "D") action = "Deleted"
    else if (status == "DA") action = "Renamed"
    else action = "Unknown"
    printf "%s\t%s\t%s\n", status, action, path
  }' |
    $FZF_CMD --multi \
      --header="Select changes to apply (Tab to select, Enter to confirm)" \
      --preview='echo -e "Status: {2}\nPath: {3}"' \
      --preview-window=right:50% \
      --with-nth=2,3 |
    awk -F'\t' '{print $1, $3}'
}

# Handle file rename operations
handle_rename() {
  local old_path="$1"
  local new_path

  echo "${CYAN}♻️ Processing renamed file:${RESET} $old_path"

  # Attempt to find the new file path by matching filename
  new_path=$(find ~ -type f -name "$(basename "$old_path")" ! -path "$old_path" 2>/dev/null | head -n 1)

  if [ -z "$new_path" ]; then
    echo "${YELLOW}⚠️ Could not locate new path for renamed file: $old_path${RESET}"
    return 1
  fi

  echo "${CYAN}New path identified: $new_path${RESET}"

  # Remove tracking for old file path
  $CHEZMOI_CMD forget "$old_path" || {
    echo "${YELLOW}⚠️ Failed to forget old file, attempting destroy...${RESET}"
    $CHEZMOI_CMD destroy "$old_path" || {
      echo "${RED}❌ Failed to completely remove old file${RESET}"
      return 1
    }
  }

  # Add tracking for new file path
  echo "${GREEN}➕ Adding new file: $new_path${RESET}"
  $CHEZMOI_CMD add "$new_path" || {
    echo "${RED}❌ Failed to add new file${RESET}"
    return 1
  }
}

# Apply selected changes based on their status
apply_changes() {
  while read -r status path; do
    [ -z "$status" ] && continue

    case "$status" in
    "M")
      echo "${GREEN}🔄 Updating: $path${RESET}"
      $CHEZMOI_CMD add "$path" || {
        echo "${YELLOW}⚠️ Failed to update $path${RESET}"
        continue
      }
      ;;
    "A")
      echo "${GREEN}➕ Adding: $path${RESET}"
      $CHEZMOI_CMD add "$path" || {
        echo "${YELLOW}⚠️ Failed to add $path${RESET}"
        continue
      }
      ;;
    "D")
      echo "${BLUE}🗑️ Removing: $path${RESET}"
      $CHEZMOI_CMD forget "$path" || {
        echo "${YELLOW}⚠️ Failed to forget, attempting destroy...${RESET}"
        $CHEZMOI_CMD destroy "$path" || {
          echo "${RED}❌ Failed to completely remove $path${RESET}"
          continue
        }
      }
      ;;
    "DA")
      handle_rename "$path" || continue
      ;;
    *)
      echo "${YELLOW}⚠️ Unknown status '$status' for file: $path${RESET}"
      ;;
    esac
  done <<<"$1"
}

#----------------------------------------------------------
# Main Execution Flow
#----------------------------------------------------------

main() {
  echo "${GREEN}🔍 Checking for dotfile changes...${RESET}"
  changes=$(get_changes)

  if [ -z "$changes" ]; then
    echo "✅ No changes detected."
    exit 0
  fi

  selected=$(select_changes "$changes")
  [ -z "$selected" ] && {
    echo "⚠️ No changes selected."
    exit 0
  }

  apply_changes "$selected"

  # Git synchronization
  repo_dir=$($CHEZMOI_CMD source-path)
  pushd "$repo_dir" >/dev/null
  if [ -n "$($GIT_CMD status --porcelain)" ]; then
    $GIT_CMD add --all
    $GIT_CMD commit -m "🔄 Dotfiles update [$(date +%Y-%m-%d)]"
    $GIT_CMD push
    echo "${GREEN}✅ Dotfiles successfully synchronized.${RESET}"
  else
    echo "✅ No changes to commit."
  fi
  popd >/dev/null
}

main "$@"
