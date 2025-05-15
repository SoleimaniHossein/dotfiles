##!/bin/bash
#
#set -euo pipefail
#
#green=$(tput setaf 2)
#reset=$(tput sgr0)
#
#echo "${green}🔍 Finding changed files managed by chezmoi...${reset}"
#
#changed_files=$(chezmoi status | awk '{print $2}')
#
#if [ -z "$changed_files" ]; then
#  echo "✅ No modified files found."
#  exit 0
#fi
#
#selected_files=$(echo "$changed_files" | fzf-tmux --multi --prompt="Select files to sync > ")
#
#if [ -z "$selected_files" ]; then
#  echo "⚠️ No files selected."
#  exit 1
#fi
#
#echo "$selected_files" | while read -r file; do
#  echo "➕ Adding: $file"
#  chezmoi add "$file"
#done
#
#cd "$(chezmoi source-path)"
#
#if [ -n "$(git status --porcelain)" ]; then
#  git add .
#  git commit -m "🔄 Sync dotfiles with chezsync-fzf"
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

echo "${green}🔍 Detecting dotfile changes with chezmoi...${reset}"

chezmoi_changes=$(chezmoi status)

if [ -z "$chezmoi_changes" ]; then
  echo "✅ No changes found."
  exit 0
fi

selected=$(echo "$chezmoi_changes" | fzf-tmux --multi --prompt="Select files to sync > ")

if [ -z "$selected" ]; then
  echo "⚠️ No files selected."
  exit 1
fi

echo "$selected" | while read -r line; do
  status=$(echo "$line" | awk '{print $1}')
  filepath=$(echo "$line" | awk '{print $2}' | sed "s|^~|$HOME|")

  # فقط دو حرف اول رو چک می‌کنیم (MM, M, A, R)
  short_status=${status:0:1}

  case "$short_status" in
  M | A)
    echo "➕ Adding file: $filepath"
    chezmoi add "$filepath"
    ;;
  R)
    echo "❌ Removing file: $filepath"
    chezmoi remove "$filepath"
    ;;
  *)
    echo "${yellow}⚠️ Unknown or unsupported status '$status' for $filepath. Skipping...${reset}"
    ;;
  esac
done

cd "$(chezmoi source-path)"

if [ -n "$(git status --porcelain)" ]; then
  git add .
  git commit -m "🔄 Sync dotfiles via chezsync"
  git push
  echo "${green}✅ Dotfiles synced and pushed to GitHub.${reset}"
else
  echo "✅ Nothing to commit."
fi
