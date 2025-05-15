#!/bin/bash
set -euo pipefail

CHEZMOI_CMD="chezmoi"
FZF_TMUX_CMD="fzf-tmux"
GIT_CMD="git"

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

# این تابع فقط آدرس‌های rename شده رو از کاربر میگیره
prompt_renames() {
  local rename_paths=()
  while IFS=$'\t' read -r status path; do
    if [ "$status" == "DA" ]; then
      echo -e "${CYAN}♻️ Rename detected: $path${RESET}"
      echo "Enter new path or new name (relative to home). Leave empty to keep original basename."
      read -r new_path

      if [ -z "$new_path" ]; then
        # اگر خالی بود فقط basename رو می‌پذیریم
        base=$(basename "$path")
        echo "No path given. Using original basename: $base"
        new_path="$(dirname "$path")/$base"
      else
        # اگر فقط اسم داده شده (بدون /) با dirname ادغام کن
        if [[ "$new_path" != */* ]]; then
          new_path="$(dirname "$path")/$new_path"
        fi
      fi

      rename_paths+=("$path"$'\t'"$new_path")
    fi
  done <<<"$1"

  # رشته خروجی: قدیمی \t جدید
  printf "%s\n" "${rename_paths[@]}"
}

handle_rename() {
  local old_path="$1"
  local new_path="$2"

  $CHEZMOI_CMD forget "$old_path" || {
    echo "${YELLOW}⚠️ Failed to forget old path, trying destroy...${RESET}"
    $CHEZMOI_CMD destroy "$old_path" || {
      echo "${RED}❌ Failed to remove old path $old_path${RESET}"
      return 1
    }
  }

  $CHEZMOI_CMD add "$new_path" || {
    echo "${RED}❌ Failed to add new path $new_path${RESET}"
    return 1
  }

  echo "${GREEN}✅ Renamed $old_path to $new_path and synced.${RESET}"
}

apply_changes() {
  local renames="$1"
  # اول rename هارو از قبل آماده شده اعمال کن
  if [ -n "$renames" ]; then
    while IFS=$'\t' read -r old_path new_path; do
      handle_rename "$old_path" "$new_path" || echo "${YELLOW}⚠️ Rename failed: $old_path -> $new_path${RESET}"
    done <<<"$renames"
  fi
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

  # از کاربر مسیر جدید rename ها رو بگیر
  rename_map=$(prompt_renames "$selected")

  # حذف تمام خطوط rename از selected چون جدا اعمال میشه
  filtered_selected=$(echo "$selected" | grep -v "^DA")

  # تغییرات غیر rename رو اعمال کن
  while IFS=$'\t' read -r status path; do
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
    *)
      echo "${YELLOW}⚠️ Unknown status '$status' for file: $path${RESET}"
      ;;
    esac
  done <<<"$filtered_selected"

  # حالا rename ها رو اعمال کن
  apply_changes "$rename_map"

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
