#!/usr/bin/env bash
# Paths and settings that every part of agentvm shares, and the helpers
# they all use. the agentvm script sources it first.
# shellcheck disable=SC2034

readonly DATA="${XDG_DATA_HOME:-$HOME/.local/share}/agentvm"
readonly STATE="${XDG_STATE_HOME:-$HOME/.local/state}/agentvm"
readonly IMAGE=agentvm:latest
readonly CA_CERT="$STATE/ca.pem"
readonly CA_KEY="$STATE/ca.key"
readonly GUEST_HOME="/home/$USER"
# The guest side of the shared directories, as the guest session expects
# them.
readonly GUEST_DIR=/opt/agentvm
# The prefix of the VM's host name, which `container` takes from the
# container's name. WezTerm reads it from OSC 7.
readonly HOST=agentvm
# nono rejects LibreSSL's EC keys, and Homebrew keeps openssl@3 keg-only.
OPENSSL="${HOMEBREW_PREFIX:-/opt/homebrew}/opt/openssl@3/bin/openssl"
[ -x "$OPENSSL" ] || OPENSSL=openssl
readonly OPENSSL

die() {
  echo "agentvm: $*" >&2
  exit 1
}

# Creates the proxy's CA once. The image trusts it, so a new CA needs
# `agentvm build`.
ensure_ca() {
  [ ! -s "$CA_CERT" ] || return 0
  mkdir -p "$STATE"
  (umask 077 && "$OPENSSL" req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
    -keyout "$CA_KEY" -out "$CA_CERT" -days 3650 -subj "/CN=agentvm proxy" \
    -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign 2>/dev/null)
}

# Commits the working tree of the repository in $PWD through a temporary
# index, so its index and history stay untouched. A repository without
# commits gets a root commit.
snapshot() {
  local tree dir parent=()
  dir=$(mktemp -d)
  cp "$(git rev-parse --git-path index)" "$dir/index" 2>/dev/null || :
  GIT_INDEX_FILE="$dir/index" git add -A :/
  tree=$(GIT_INDEX_FILE="$dir/index" git write-tree)
  rm -r "$dir"
  if git rev-parse -q --verify HEAD >/dev/null; then
    parent=(-p HEAD)
  fi
  git commit-tree --no-gpg-sign ${parent[@]+"${parent[@]}"} -m "agentvm: host working tree" "$tree"
}
