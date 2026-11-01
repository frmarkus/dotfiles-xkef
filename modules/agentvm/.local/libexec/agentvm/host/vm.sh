#!/usr/bin/env bash
# One VM: what it shares with the host, and how it boots.
#
# Uses the session's state that the agentvm script sets: $session, $folder,
# $clipboard, $root, $workdir, $snap, $env, and $persist.
# shellcheck disable=SC2154

readonly CPUS=4
readonly MEMORY=8G
# Paths under the guest's home that every session keeps per repository.
readonly CACHES=(.cache .local/share/mise .local/share/cargo .local/share/go)

# Prints the shares of a VM whose exchange directory is $1, one per line,
# as SOURCE:TARGET or SOURCE:TARGET:ro.
shares() {
  local path
  echo "$1:$GUEST_DIR/session"
  echo "$clipboard:$clipboard:ro"
  for path in "${CACHES[@]}" ${persist[@]+"${persist[@]}"}; do
    mkdir -p "$folder/home/$path"
    echo "$folder/home/$path:$GUEST_HOME/$path"
  done
  [ -n "$root" ] || return 0
  echo "$folder/copy:$root"
  echo "$(cd "$root" && git rev-parse --path-format=absolute --git-common-dir):$GUEST_DIR/git:ro"
}

# Runs the guest session in a VM with $1 as its mode and the rest as its
# arguments, and leaves the copy's changes as $session/vm.bundle, with
# their base commit in $session/base.
#
# The guest writes to the directory it shares with the host, so each VM
# gets a new one inside the private $session. Nothing an earlier VM left
# there, such as a link, can redirect the host's next write or read.
guest() {
  local exchange rc=0 args=() share source target mount
  exchange=$(mktemp -d "$session/vm.XXXXXX")
  while IFS=: read -r source target mount; do
    args+=(--mount "type=bind,source=$source,target=$target${mount:+,readonly}")
  done < <(shares "$exchange")
  for share in ${env[@]+"${env[@]}"}; do
    args+=(--env "$share")
  done
  [ ! -t 0 ] || args+=(--tty)
  # container sets TERM=xterm otherwise, and nvim then scrolls a split with
  # left and right margins, which tmux ignores, so the scroll smears the
  # neighboring windows.
  for share in TERM COLORTERM; do
    [ -z "${!share:-}" ] || args+=(--env "$share=${!share}")
  done

  start_bridge "$session/proxy.sock"
  (umask 077 && printf 'nono:%s' "$proxy_pass" >"$exchange/proxy")
  start_status "$exchange"
  # Linux refuses a nested /proc mount, which podman in the VM needs, while
  # parts of /proc are masked. The masks guard a kernel shared with the
  # host, and the VM's kernel is its own.
  container run --rm --interactive --network none --progress none \
    --masked-path NONE --read-only-path NONE \
    --name "$HOST-$$-$RANDOM" --uid "$(id -u)" --gid "$(id -g)" --cpus "$CPUS" --memory "$MEMORY" \
    "${args[@]}" --volume "$session/proxy.sock:$GUEST_DIR/proxy.sock" \
    --env "HOME=$GUEST_HOME" --env "USER=$USER" \
    --env "AGENTVM_ROOT=$root" --env "AGENTVM_WORKDIR=$workdir" \
    --env "AGENTVM_SNAPSHOT=${snap:-}" \
    --env "AGENTVM_NAME=$(git config user.name || echo "$USER")" \
    --env "AGENTVM_EMAIL=$(git config user.email || echo "$USER@localhost")" \
    "$IMAGE" bash /usr/local/libexec/agentvm/session.sh "$@" || rc=$?
  stop_status
  kill "$bridge_pid" 2>/dev/null || :

  # The VM has stopped, so the files can't change between the check and
  # the copy.
  local file
  for file in vm.bundle base; do
    rm -f "${session:?}/$file"
    if [ -f "$exchange/$file" ] && [ ! -L "$exchange/$file" ]; then
      cp "$exchange/$file" "$session/$file"
    fi
  done
  return "$rc"
}
