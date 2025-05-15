#!/bin/bash

set -e

green=$(tput setaf 2)
reset=$(tput sgr0)

echo "${green}🔍 Finding modified files managed by chezmoi...${reset}"

changed_files=$(chezmoi diff | grep '^files/' | sed 's/^files\///')

if [ -z "$changed_files" ]; then
  echo "✅ No modified files found."
  exit 0
fi

selected_files=$(echo "$changed_files" | fzf-tmux --multi --prompt="Select files to sync > ")

if [ -z "$selected_files" ]; then
  echo "⚠️ No files selected."
  exit 1
fi

echo "$selected_files" | while read -r file; do
  echo "➕ Adding: $file"
  chezmoi add "$HOME/$file"
done

cd "$(chezmoi source-path)"

if [ -n "$(git status --porcelain)" ]; then
  git add .
  git commit -m "🔄 Sync dotfiles with chezsync-fzf"
  git push
  echo "${green}✅ Dotfiles synced and pushed to GitHub.${reset}"
else
  echo "✅ Nothing to commit."
fi
