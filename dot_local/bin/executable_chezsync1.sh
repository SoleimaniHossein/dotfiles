#!/bin/bash
set -eo pipefail

# Configuration
CHEZMOI_CMD="chezmoi"
FZF_CMD="fzf"
GIT_CMD="git"

# Colors
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
BOLD=$(tput bold)
RESET=$(tput sgr0)

#----------------------------------------------------------
# Core Functions with Rename Handling
#----------------------------------------------------------

get_changes() {
  # Get changes and normalize status codes
  $CHEZMOI_CMD status | awk '{
    status = $1
    path = $2
    # Normalize status codes
    if (status == "MM" || status == "M") status = "M"
    else if (status == "A") status = "A"
    else if (status == "D" || status == "R" || status == "DA") status = "D"
    print status, path
  }'
}

select_changes() {
  local changes="$1"

  echo "$changes" | awk '{
    status = $1
    path = $2
    # Map status codes to human-readable forms
    if (status == "M") action = "Modified"
    else if (status == "A") action = "Added"
    else if (status == "D") action = "Deleted/Renamed"
    else action = "Unknown"
    printf "%s\t%s\t%s\n", status, action, path
  }' |
    $FZF_CMD --multi \
      --header="Select changes to apply (Tab to select, Enter to confirm)" \
      --preview='echo -e "Status: {2}\nPath: {3}"' \
      --preview-window=right:50% \
      --with-nth=2,3 |
    awk '{print $1, $3}'
}

handle_rename() {
  local old_path="$1"
  echo "${BLUE}♻️ Handling renamed file:${RESET} $old_path"

  # Remove the old file from tracking
  $CHEZMOI_CMD forget "$old_path" || {
    echo "${YELLOW}Warning: Couldn't forget $old_path, trying destroy${RESET}"
    $CHEZMOI_CMD destroy "$old_path" || {
      echo "${RED}Error: Failed to remove $old_path${RESET}"
      return 1
    }
  }

  # The new filename will be detected as an addition automatically
}

apply_changes() {
  while read -r status path; do
    [ -z "$status" ] && continue

    case "$status" in
    "M")
      echo "${GREEN}Updating:${RESET} $path"
      $CHEZMOI_CMD add "$path" || {
        echo "${YELLOW}Warning: Failed to update $path${RESET}"
        continue
      }
      ;;
    "A")
      echo "${GREEN}Adding:${RESET} $path"
      $CHEZMOI_CMD add "$path" || {
        echo "${YELLOW}Warning: Failed to add $path${RESET}"
        continue
      }
      ;;
    "D")
      # Check if this is part of a rename (DA status)
      if [[ "$path" == *"chezsync.sh"* ]]; then
        handle_rename "$path"
      else
        echo "${BLUE}Removing:${RESET} $path"
        $CHEZMOI_CMD forget "$path" || {
          echo "${YELLOW}Warning: Failed to forget $path, trying destroy${RESET}"
          $CHEZMOI_CMD destroy "$path" || {
            echo "${RED}Error: Failed to remove $path completely${RESET}"
            continue
          }
        }
      fi
      ;;
    *)
      echo "${YELLOW}Unknown status '$status' for file: $path${RESET}"
      ;;
    esac
  done <<<"$1"
}

#----------------------------------------------------------
# Main Execution
#----------------------------------------------------------

main() {
  echo "${GREEN}Checking for dotfile changes...${RESET}"
  changes=$(get_changes)

  if [ -z "$changes" ]; then
    echo "No changes detected"
    exit 0
  fi

  selected=$(select_changes "$changes")
  [ -z "$selected" ] && {
    echo "No changes selected"
    exit 0
  }

  apply_changes "$selected"

  # Git operations
  repo_dir=$($CHEZMOI_CMD source-path)
  pushd "$repo_dir" >/dev/null
  if [ -n "$($GIT_CMD status --porcelain)" ]; then
    $GIT_CMD add --all
    $GIT_CMD commit -m "Sync dotfiles [$(date +%Y-%m-%d)]"
    $GIT_CMD push
    echo "${GREEN}Successfully synced dotfiles${RESET}"
  else
    echo "No changes to commit"
  fi
  popd >/dev/null
}

main "$@"
