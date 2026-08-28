if [[ -d "$HOME/.proto/shims" ]]; then
  typeset -U path
  path=("$HOME/.proto/shims" $path)
fi
