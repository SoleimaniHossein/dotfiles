#!/bin/bash
set -euo pipefail

# Configuration
CHEZMOI_CMD="chezmoi"
FZF_TMUX_CMD="fzf-tmux"
GIT_CMD="git"

# Colors
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
CYAN=$(tput setaf 6)
BOLD=$(tput bold)
RESET=$(tput sgr0)

get_changes() {
  $CHEZMOI_CMD status | awk '{
    status = $1
    path = $2
    # Normalize status codes:
    if (status == "MM" || status == "M") status = "M"
    else if (status == "A") status = "A"
    else if (status == "D" || status == "R") status = "D"
    else if (status == "DA") status = "DA"
    print status "\t" path
  }'
}

select_changes() {
  local changes="$1"
  echo "$changes" | awk -F'\t' '{
    status = $1
    path = $2
    if (status == "M") action = "Modified"
    else if (status == "A") action = "Added"
    else if (status == "D") action = "Deleted"
    else if (status == "DA") action = "Renamed"
    else action = "Unknown"
    printf "%s\t%s\t%s\n", status, action, path
  }' |
    $FZF_TMUX_CMD --multi \
      --header="Select changes to apply (Tab to select, Enter to confirm)" \
      --preview='echo -e "Status: {2}\nPath: {3}"' \
      --preview-window=right:50% \
      --with-nth=2,3 |
    awk -F'\t' '{print $1 "\t" $3}'
}

handle_rename() {
  local old_path="$1"
  echo "${CYAN}♻️ Detected rename of file: ${BOLD}$old_path${RESET}${CYAN}"
  echo "Please enter the new file path (relative to home):"
  read -r new_path

  if [ -z "$new_path" ]; then
    echo "${YELLOW}⚠️ No new path entered. Skipping rename for $old_path.${RESET}"
    return 1
  fi

  $CHEZMOI_CMD forget "$old_path" || {
    echo "${YELLOW}⚠️ Failed to forget old file, trying destroy...${RESET}"
    $CHEZMOI_CMD destroy "$old_path" || {
      echo "${RED}❌ Failed to remove old file $old_path${RESET}"
      return 1
    }
  }

  $CHEZMOI_CMD add "$new_path" || {
    echo "${RED}❌ Failed to add new file $new_path${RESET}"
    return 1
  }
  echo "${GREEN}✅ Renamed $old_path to $new_path and synced.${RESET}"
}

apply_changes() {
  while IFS=$'\t' read -r status path; do
    [ -z "$status" ] && continue

    case "$status" in
    "M")
      echo "${GREEN}🔄 Updating: $path${RESET}"
      $CHEZMOI_CMD add "$path" || echo "${YELLOW}⚠️ Failed to update $path${RESET}"
      ;;
    "A")
      echo "${GREEN}➕ Adding: $path${RESET}"
      $CHEZMOI_CMD add "$path" || echo "${YELLOW}⚠️ Failed to add $path${RESET}"
      ;;
    "D")
      echo "${BLUE}🗑️ Removing: $path${RESET}"
      $CHEZMOI_CMD forget "$path" || {
        echo "${YELLOW}⚠️ Failed to forget, trying destroy...${RESET}"
        $CHEZMOI_CMD destroy "$path" || echo "${RED}❌ Failed to remove $path${RESET}"
      }
      ;;
    "DA")
      handle_rename "$path" || echo "${YELLOW}⚠️ Rename skipped for $path${RESET}"
      ;;
    *)
      echo "${YELLOW}⚠️ Unknown status '$status' for file: $path${RESET}"
      ;;
    esac
  done <<<"$1"
}

main() {
  echo "${GREEN}🔍 Checking for dotfile changes...${RESET}"
  changes=$(get_changes)

  if [ -z "$changes" ]; then
    echo "✅ No changes detected."
    exit 0
  fi

  selected=$(select_changes "$changes")
  if [ -z "$selected" ]; then
    echo "${YELLOW}⚠️ No changes selected. Exiting.${RESET}"
    exit 0
  fi

  apply_changes "$selected"

  repo_dir=$($CHEZMOI_CMD source-path)
  pushd "$repo_dir" >/dev/null || {
    echo "${RED}❌ Failed to access chezmoi source directory${RESET}"
    exit 1
  }

  if [ -n "$($GIT_CMD status --porcelain)" ]; then
    $GIT_CMD add --all
    $GIT_CMD commit -m "🔄 Dotfiles update [$(date +%Y-%m-%d)]"
    $GIT_CMD push
    echo "${GREEN}✅ Dotfiles successfully synchronized and pushed to GitHub.${RESET}"
  else
    echo "✅ No changes to commit."
  fi

  popd >/dev/null || true
}

main "$@"
