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
  # Changes from chezmoi status
  local chezmoi_changes
  chezmoi_changes=$($CHEZMOI_CMD status | awk '{
    status = $1
    path = $2
    if (status == "MM" || status == "M") status = "M"
    else if (status == "A") status = "A"
    else if (status == "D" || status == "R") status = "D"
    else if (status == "DA") status = "DA"
    print status "\t" path
  }')

  # Changes from git status (in chezmoi source directory)
  local repo_dir=$($CHEZMOI_CMD source-path)
  local git_changes
  cd "$repo_dir" || exit 1
  git_changes=$($GIT_CMD status --porcelain | awk '
    {
      status_code = substr($0,1,2)
      file = substr($0,4)
      if (status_code ~ /^[?A]/) {
        print "A\t" file
      } else if (status_code ~ /^[ D]/) {
        print "D\t" file
      } else if (status_code ~ /^[ M]/) {
        print "M\t" file
      }
    }')

  # Combine and unique
  echo -e "$chezmoi_changes\n$git_changes" | sort -u
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

  # Ask new path or new name via fzf-tmux prompt
  new_path=$(echo "" | $FZF_TMUX_CMD --print-query \
    --header="♻️ Renaming: ${BOLD}$old_path${RESET}
Enter new path (relative to home):" \
    --prompt="New path > " | head -n1)

  if [ -z "$new_path" ]; then
    echo "${YELLOW}⚠️ No new path entered. Removing old file $old_path.${RESET}"
    $CHEZMOI_CMD forget "$old_path" || {
      echo "${YELLOW}⚠️ Failed to forget, trying destroy...${RESET}"
      $CHEZMOI_CMD destroy "$old_path" || {
        echo "${RED}❌ Failed to remove old file $old_path${RESET}"
        return 1
      }
    }
    return 0
  fi

  echo "${CYAN}♻️ Renaming $old_path to $new_path${RESET}"

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

  echo "${GREEN}✅ Successfully renamed $old_path to $new_path${RESET}"
  return 0
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
      handle_rename "$path" || echo "${RED}❌ Rename failed for $path${RESET}"
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

# finished
