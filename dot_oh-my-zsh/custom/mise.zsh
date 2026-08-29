# Check if mise is installed and executable before initializing
if [[ -x "$HOME/.local/bin/mise"  ]]; then
  eval "$($HOME/.local/bin/mise activate zsh)"
fi
