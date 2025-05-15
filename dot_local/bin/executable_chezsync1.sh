##!/bin/bash
#
#set -euo pipefail
#
#green=$(tput setaf 2)
#yellow=$(tput setaf 3)
#reset=$(tput sgr0)
#
#echo "${green}🔍 Detecting dotfile changes with chezmoi...${reset}"
#
#chezmoi_changes=$(chezmoi status)
#
#if [ -z "$chezmoi_changes" ]; then
#  echo "✅ No changes found."
#  exit 0
#fi
#
#selected=$(echo "$chezmoi_changes" | fzf-tmux --multi --prompt="Select files to sync > ")
#
#if [ -z "$selected" ]; then
#  echo "⚠️ No files selected."
#  exit 1
#fi
#
#echo "$selected" | while read -r line; do
#  status=$(echo "$line" | awk '{print $1}')
#  filepath=$(echo "$line" | awk '{print $2}' | sed "s|^~|$HOME|")
#
#  # فقط دو حرف اول رو چک می‌کنیم (MM, M, A, R)
#  short_status=${status:0:1}
#
#  case "$short_status" in
#  M | A)
#    echo "➕ Adding file: $filepath"
#    chezmoi add "$filepath"
#    ;;
#  R)
#    echo "❌ Removing file: $filepath"
#    chezmoi remove "$filepath"
#    ;;
#  *)
#    echo "${yellow}⚠️ Unknown or unsupported status '$status' for $filepath. Skipping...${reset}"
#    ;;
#  esac
#done
#
#cd "$(chezmoi source-path)"
#
#if [ -n "$(git status --porcelain)" ]; then
#  git add .
#  git commit -m "🔄 Sync dotfiles via chezsync"
#  git push
#  echo "${green}✅ Dotfiles synced and pushed to GitHub.${reset}"
#else
#  echo "✅ Nothing to commit."
#fi

#!/bin/bash
set -euo pipefail

green=$(tput setaf 2)
yellow=$(tput setaf 3)
reset=$(tput sgr0)

echo "${green}🔍 Checking chezmoi status...${reset}"

status=$(chezmoi status)

if [[ -z "$status" ]]; then
  echo "✅ No changes detected."
  exit 0
fi

echo "$status"

echo "${green}❓ Select files to sync (fzf-tmux multi select):${reset}"
selected=$(echo "$status" | fzf-tmux --multi --prompt="Select files > ")

if [[ -z "$selected" ]]; then
  echo "${yellow}⚠️ No files selected.${reset}"
  exit 1
fi

while read -r line; do
  status_char=$(echo "$line" | awk '{print substr($1,1,1)}')
  file=$(echo "$line" | awk '{print $2}')

  case "$status_char" in
  M | A)
    echo "➕ Adding or modifying $file"
    chezmoi add "$file"
    ;;
  D)
    echo "❌ Removing $file"
    chezmoi destroy "$file"
    ;;
  *)
    echo "${yellow}⚠️ Unknown status $status_char for $file, skipping.${reset}"
    ;;
  esac
done <<<"$selected"

cd "$(chezmoi source-path)"
git add .
git commit -m "🔄 Sync dotfiles"
git push
echo "${green}✅ Sync complete and pushed to GitHub.${reset}"
