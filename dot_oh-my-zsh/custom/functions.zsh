pong() {
  local target="$1"
  ping -W 1 $target | while read pong; do echo "$(date): $pong"; done
}
