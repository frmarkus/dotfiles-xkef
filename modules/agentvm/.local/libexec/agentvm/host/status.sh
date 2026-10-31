#!/usr/bin/env bash
# The status channel: one-line files the guest writes, which the host
# passes to the --on-status command. The guest picks only the names and
# values, which the host checks, and the command decides what they mean.
#
# Uses $session, the session's private folder, and $on_status, the
# command the agentvm script got.
# shellcheck disable=SC2154

# The status files the guest may write, and how much of each the host
# reads.
readonly STATUS_NAME='^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$'
readonly STATUS_FILES=16
readonly STATUS_BYTES=512

status_pid=

# Prints the first line of the guest-written file $1, as printable ASCII
# only, so no escape sequence reaches a terminal. A link or a pipe the
# guest left in its place reads as nothing.
guest_line() {
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  head -c "$STATUS_BYTES" "$1" | head -n 1 | LC_ALL=C tr -cd '[:print:]\t'
}

# Passes the changes in the exchange directory $1's status folder to
# $on_status, once a second, until stop_status. The last values sit in
# the private $session.
watch_status() {
  local dir="$1/status" seen="$session/status" file name value count
  mkdir -p "$seen"
  while sleep 1; do
    count=0
    for file in "$dir"/*; do
      name=${file##*/}
      [[ "$name" =~ $STATUS_NAME ]] || continue
      count=$((count + 1))
      [ "$count" -le "$STATUS_FILES" ] || break
      value=$(guest_line "$file") || continue
      [ "$value" != "$(cat "$seen/$name" 2>/dev/null)" ] || continue
      printf '%s' "$value" >"$seen/$name"
      "$on_status" "$name" "$value"
    done
    for file in "$seen"/*; do
      name=${file##*/}
      [ -e "$file" ] && [ ! -f "$dir/$name" ] || continue
      rm "$file"
      "$on_status" "$name" ""
    done
  done
}

start_status() {
  [ -n "$on_status" ] || return 0
  # bash reports the sleep that stop_status ends.
  watch_status "$1" 2>/dev/null &
  status_pid=$!
  disown "$status_pid"
}

# A read of a pipe the guest swapped in after the check blocks, so the
# children go too.
stop_status() {
  [ -n "$status_pid" ] || return 0
  pkill -P "$status_pid" 2>/dev/null || :
  kill "$status_pid" 2>/dev/null || :
  status_pid=
  "$on_status"
}
