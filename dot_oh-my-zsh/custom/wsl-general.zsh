# Tell zsh not to use nice while running application in background
# Source: https://github.com/microsoft/WSL/issues/1887
unsetopt BG_NICE

# https://wiki.ubuntu.com/WSL#Running_Graphical_Applications
export LIBGL_ALWAYS_INDIRECT=1
