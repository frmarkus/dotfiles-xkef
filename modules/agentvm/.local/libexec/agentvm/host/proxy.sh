#!/usr/bin/env bash
# The VM's only way out: a nono credential proxy on the host's loopback,
# and a Unix socket that `container` relays into the VM.
#
# Uses $session, the session's private folder, and $extends, the profiles
# that the agentvm script stacks.
# shellcheck disable=SC2154
# vm.sh uses $proxy_pass and $bridge_pid.
# shellcheck disable=SC2034

# A machine adds its own hosts or credentials in this untracked profile.
readonly LOCAL_PROFILE=agentvm-local

# Starts this session's proxy, which stops when the script exits, and
# sets $proxy_pid, $proxy_port, and $proxy_pass.
start_proxy() {
  local log profiles=(-p agentvm) profile
  [ ! -f "$HOME/.config/nono/profiles/$LOCAL_PROFILE.json" ] || profiles+=(--extends "$LOCAL_PROFILE")
  for profile in ${extends[@]+"${extends[@]}"}; do
    profiles+=(--extends "$profile")
  done
  log=$(mktemp "$session/proxy-log.XXXXXX")
  proxy_pass=$("$OPENSSL" rand -hex 16)
  NONO_PROXY_PASS=$proxy_pass nono proxy "${profiles[@]}" \
    --proxy-ca-cert "$CA_CERT" --proxy-ca-key "$CA_KEY" </dev/null >"$log" 2>&1 &
  proxy_pid=$!
  # The cleanup stops the proxy, which bash would otherwise report.
  disown "$proxy_pid"

  # The keychain may ask for access first.
  until proxy_port=$(sed -n 's/.*listening on 127\.0\.0\.1:\([0-9]*\).*/\1/p' "$log") && [ -n "$proxy_port" ]; do
    kill -0 "$proxy_pid" 2>/dev/null || die "the proxy did not start: $(cat "$log")"
    sleep 0.2
  done
  rm "$log"
}

# Starts a bridge from a Unix socket at $1 to the proxy, and sets
# $bridge_pid. The proxy listens on TCP, and `container` relays only Unix
# sockets into the VM, with the host socket's mode. The socket sits in the
# private $session, so the mode lets no other host user in.
start_bridge() {
  rm -f "$1"
  socat "UNIX-LISTEN:$1,fork,mode=0666" "TCP:127.0.0.1:$proxy_port" 2>/dev/null &
  bridge_pid=$!
  disown "$bridge_pid"
  until [ -e "$1" ]; do
    kill -0 "$bridge_pid" 2>/dev/null || die "the proxy bridge did not start"
    sleep 0.05
  done
}
