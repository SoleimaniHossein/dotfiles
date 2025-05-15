#!/bin/bash

echo "Installing basic tools..."

if command -v apt &>/dev/null; then
  sudo apt update && sudo apt install -y tmux neovim git curl fonts-jetbrains-mono
elif command -v dnf &>/dev/null; then
  sudo dnf install -y tmux neovim git curl jetbrains-mono-fonts
fi

if ! command -v getnf &>/dev/null; then
  echo "Installing getnf..."
  curl -s https://raw.githubusercontent.com/ronniedroid/getnf/main/install.sh | bash
fi

getnf JetBrainsMono FiraCode Hack SourceCodePro
