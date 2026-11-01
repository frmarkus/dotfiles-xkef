#!/usr/bin/env bash
# Runs in the guest as the user, started by agentvm. `serve` keeps the VM
# up and bridges the proxy. The other modes run through `container exec`:
# a session joins the proxy, brings the repository copy up to date, and
# runs in the user's login shell. `bundle` prints the copy's changes as a
# git bundle for the host, and `reset` discards them.
#
# Usage: session serve | run CMD [ARGS...] | shell | pane DIR | bundle | reset
#
# The environment names the repository (AGENTVM_ROOT, empty outside one),
# the snapshot to copy (AGENTVM_SNAPSHOT), the directory to start in
# (AGENTVM_WORKDIR), the ports to serve (AGENTVM_PORTS), and the
# session's status folder (AGENTVM_STATUS_ID).
#
# Before a session, it sources every ~/.config/agentvm/guest.d/*.sh,
# where other tools set up the guest. A hook may write one-line status
# files to $AGENTVM_STATUS, which agentvm passes to the host's --on-status
# command.
set -eu

dir=/opt/agentvm
session=$dir/session
host_ref=refs/agentvm/host
base_ref=refs/agentvm/base
proxy_port=3128
ports=$HOME/.local/state/agentvm/ports
shell=$(getent passwd "$(id -u)" | cut -d: -f7)

# The only way out of the VM: the relayed socket, behind a loopback port
# that every proxy-aware tool can use. socat writes to the VM's log, and
# the proxy resets every connection it refuses. A published port gets a
# socket that `container` relays to the host, on the VM's own disk, since
# a shared directory takes no Unix socket.
serve() {
  local port
  mkdir -p "$ports"
  for port in ${AGENTVM_PORTS:-}; do
    socat "UNIX-LISTEN:$ports/$port,fork" "TCP:127.0.0.1:$port" &
  done
  exec socat "TCP-LISTEN:$proxy_port,bind=127.0.0.1,fork,reuseaddr" "UNIX-CONNECT:$dir/proxy.sock" 2>/dev/null
}

join_proxy() {
  local proxy
  proxy=$(cat "$session/proxy")
  export HTTPS_PROXY="http://$proxy@127.0.0.1:$proxy_port" HTTP_PROXY="http://$proxy@127.0.0.1:$proxy_port"
  export NO_PROXY=localhost,127.0.0.1,::1
  # Some tools, such as curl for HTTP and busybox, read only the lowercase
  # names.
  export https_proxy=$HTTPS_PROXY http_proxy=$HTTP_PROXY no_proxy=$NO_PROXY
  export NODE_EXTRA_CA_CERTS=/etc/ca-certificates/trust-source/anchors/agentvm.pem
  # Node's fetch ignores the proxy variables without it.
  export NODE_USE_ENV_PROXY=1
  export AGENTVM_STATUS=$session/status/${AGENTVM_STATUS_ID:?}
  mkdir -p "$AGENTVM_STATUS"
}

hooks() {
  for hook in "$HOME"/.config/agentvm/guest.d/*.sh; do
    # shellcheck source=/dev/null
    [ ! -r "$hook" ] || . "$hook"
  done
}

# Runs the session in the login shell: CMD and its arguments, or the
# shell itself. fish takes the command from its arguments, a POSIX shell
# from "$@".
login() {
  case "${1:-}:${shell##*/}" in
  :*) "$shell" -l ;;
  *:fish) "$shell" -lc '$argv' "$@" ;;
  *) "$shell" -lc '"$@"' "$shell" "$@" ;;
  esac
}

# Sessions share the copy, so each holds the lock while it changes the
# copy's state.
lock() {
  exec 9>"$session/lock"
  flock 9
}

unlock() {
  exec 9>&-
}

# The copy is a colocated jj repository, so jj shows what happened in the
# VM. It commits under the host's name without signing, since the guest
# has no signing key.
repository() {
  local out
  cd "$AGENTVM_ROOT"
  if [ ! -d .git ]; then
    git init -q
    git config user.name "$AGENTVM_NAME"
    git config user.email "$AGENTVM_EMAIL"
    git config commit.gpgsign false
  fi
  if [ ! -d .jj ]; then
    out=$(jj --config "user.name=$AGENTVM_NAME" --config "user.email=$AGENTVM_EMAIL" \
      git init --colocate 2>&1) || {
      printf '%s\n' "$out" >&2
      exit 1
    }
  fi
  # A copy from before this check may lack the identity.
  [ -n "$(jj config get user.name 2>/dev/null)" ] || {
    jj config set --repo user.name "$AGENTVM_NAME"
    jj config set --repo user.email "$AGENTVM_EMAIL"
    jj config set --repo signing.behavior drop
  }
}

# Replaces the copy with the host's snapshot while the copy holds nothing
# since the last one.
update() {
  lock
  repository
  git fetch -q "$dir/git" "+${AGENTVM_SNAPSHOT:?}:$host_ref"
  if [ -z "$(git status --porcelain)" ] &&
    [ "$(git rev-parse -q --verify HEAD)" = "$(git rev-parse -q --verify $base_ref)" ]; then
    git reset -q --hard $host_ref
    git update-ref $base_ref $host_ref
  else
    echo "agentvm: the VM copy keeps changes from an earlier session: agents vm take shows them and asks, drop discards them" >&2
  fi
  unlock
}

# Prints the copy's changes for the host: the base commit on the first
# line, then a git bundle of the commits from the base to the
# working-copy commit, which jj snapshots first. The bundle holds plain
# objects, which host git checks. A copy without changes prints nothing.
handoff() {
  local rev
  lock
  repository
  rev=$(jj log --no-graph -r @ -T commit_id 2>/dev/null) || rev=$(git rev-parse HEAD)
  ! git diff --quiet $base_ref "$rev" || return 0
  git update-ref refs/agentvm/vm "$rev"
  git rev-parse $base_ref
  git bundle create -q - refs/agentvm/vm "^$base_ref"
}

mode=$1
shift
case $mode in
serve) serve ;;
bundle)
  handoff
  exit
  ;;
reset)
  lock
  repository
  exec jj --quiet new "$(git rev-parse $base_ref)"
  ;;
esac

join_proxy
if [ "$mode" = pane ]; then
  cd "$1"
  hooks
  exec "$shell" -l
fi

if [ -n "${AGENTVM_ROOT:-}" ]; then
  update
  cd "$AGENTVM_WORKDIR"
else
  cd
fi
hooks
login "$@"
