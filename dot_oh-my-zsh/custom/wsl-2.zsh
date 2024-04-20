# Setup X server access
# Source: https://wiki.ubuntu.com/WSL#Running_Graphical_Applications
export DISPLAY=$(ip route|awk '/^default/{print $3}'):0.0
