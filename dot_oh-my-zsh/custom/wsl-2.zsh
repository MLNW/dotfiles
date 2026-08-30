# X server access: VcXsrv on the Windows host, over TCP.
# Which address reaches the host depends on WSL's networking mode: mirrored shares
# the host's netns, so it answers on loopback; NAT puts it on the default gateway.
# Source: https://wiki.ubuntu.com/WSL#Running_Graphical_Applications
case "$(wslinfo --networking-mode 2>/dev/null)" in
  mirrored) export DISPLAY=127.0.0.1:0.0 ;;
  *) export DISPLAY=$(ip route | awk '/^default/{print $3}'):0.0 ;;  # nat, or wslinfo too old to ask
esac
