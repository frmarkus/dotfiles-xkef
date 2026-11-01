#!/usr/bin/env bash
# Runs in the guest as the user, started by agentvm. It joins the proxy,
# brings the repository copy up to date, runs the session in the user's
# login shell, and leaves the copy's changes as a git bundle in the
# session directory.
#
# Usage: session run CMD [ARGS...] | shell | pane DIR | bundle | reset
#
# The environment names the repository (AGENTVM_ROOT, empty outside one),
# the snapshot to copy (AGENTVM_SNAPSHOT), and the directory to start in
# (AGENTVM_WORKDIR).
#
# Before the session, it sources every ~/.config/agentvm/guest.d/*.sh,
# where other tools set up the guest. A hook may write one-line status
# files to $AGENTVM_STATUS, which agentvm passes to the host's --on-status
# command.
set -eu

dir=/opt/agentvm
session=$dir/session
host_ref=refs/agentvm/host
base_ref=refs/agentvm/base
shell=$(getent passwd "$(id -u)" | cut -d: -f7)

# The only way out of the VM: the relayed socket, behind a loopback port
# that every proxy-aware tool can use. socat writes to the session's
# terminal, and the proxy resets every connection it refuses.
proxy=$(cat "$session/proxy")
rm "$session/proxy"
socat TCP-LISTEN:3128,bind=127.0.0.1,fork,reuseaddr UNIX-CONNECT:$dir/proxy.sock 2>/dev/null &
export HTTPS_PROXY="http://$proxy@127.0.0.1:3128" HTTP_PROXY="http://$proxy@127.0.0.1:3128"
export NO_PROXY=localhost,127.0.0.1,::1
# Some tools, such as curl for HTTP and busybox, read only the lowercase
# names.
export https_proxy=$HTTPS_PROXY http_proxy=$HTTP_PROXY no_proxy=$NO_PROXY
export NODE_EXTRA_CA_CERTS=/etc/ca-certificates/trust-source/anchors/agentvm.pem
# Node's fetch ignores the proxy variables without it.
export NODE_USE_ENV_PROXY=1
export AGENTVM_STATUS=$session/status
mkdir -p "$AGENTVM_STATUS"

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

# The copy is a colocated jj repository, so jj shows what happened in the
# VM. It commits under the host's name without signing, since the guest
# has no signing key.
repository() {
  cd "$AGENTVM_ROOT"
  if [ ! -d .git ]; then
    git init -q
    git config user.name "$AGENTVM_NAME"
    git config user.email "$AGENTVM_EMAIL"
    git config commit.gpgsign false
  fi
  [ ! -d .jj ] || return 0
  jj --config "user.name=$AGENTVM_NAME" --config "user.email=$AGENTVM_EMAIL" \
    git init --colocate >/dev/null 2>&1
  jj config set --repo user.name "$AGENTVM_NAME" 2>/dev/null
  jj config set --repo user.email "$AGENTVM_EMAIL" 2>/dev/null
  jj config set --repo signing.behavior drop
}

# Hands the copy's changes to the host as a git bundle, a file of plain
# objects: the commits from the base to the working-copy commit, which
# jj snapshots first, and the base, which the host diffs against. A copy
# without changes leaves no bundle.
handoff() {
  local rev
  repository
  rev=$(jj log --no-graph -r @ -T commit_id 2>/dev/null) || rev=$(git rev-parse HEAD)
  ! git diff --quiet $base_ref "$rev" || return 0
  git update-ref refs/agentvm/vm "$rev"
  git bundle create -q "$session/vm.bundle" refs/agentvm/vm "^$base_ref"
  git rev-parse $base_ref >"$session/base"
}

mode=$1
shift
case $mode in
pane)
  cd "$1"
  hooks
  exec "$shell" -l
  ;;
reset)
  repository
  exec jj new "$(git rev-parse $base_ref)" >/dev/null 2>&1
  ;;
bundle)
  handoff
  exit
  ;;
esac

if [ -n "${AGENTVM_ROOT:-}" ]; then
  repository
  git fetch -q "$dir/git" "+$AGENTVM_SNAPSHOT:$host_ref"
  # Replaces the copy while it holds nothing since the last copy.
  if [ -z "$(git status --porcelain)" ] &&
    [ "$(git rev-parse -q --verify HEAD)" = "$(git rev-parse -q --verify $base_ref)" ]; then
    git reset -q --hard $host_ref
    git update-ref $base_ref $host_ref
  else
    echo "agentvm: the VM copy keeps changes from an earlier session: agents vm take shows them and asks, drop discards them" >&2
  fi
  cd "$AGENTVM_WORKDIR"
else
  cd
fi
hooks

rc=0
login "$@" || rc=$?
[ -z "${AGENTVM_ROOT:-}" ] || handoff
exit $rc
