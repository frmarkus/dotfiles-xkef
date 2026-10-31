#!/usr/bin/env bash
# The gate back to the host: the copy's changes come back as commits in a
# git bundle, which the repository fetches as agentvm/vm, jj's vm@agentvm.
# The diff from them applies only after you read it.
#
# Uses $session and $root, which the agentvm script sets.
# shellcheck disable=SC2154

# Prints stdin with every control character turned into visible text: ^X
# for the C0 characters and DEL, <U+0080> and so on for the C1 ones, which
# terminals read as escape sequences too. Tabs, newlines, and UTF-8 text
# stay.
visible() {
  LC_ALL=C perl -pe 's/([\x00-\x08\x0b-\x1f\x7f])/"^" . chr(ord($1) ^ 64)/ge;
    s/\xc2([\x80-\x9f])/sprintf("<U+%04X>", ord($1))/ge'
}

# Pages the patch $1 through delta, the diff pager jj uses, or less
# without it. The guest wrote the patch, so it passes through visible
# first, and no sequence in it reaches the terminal. delta asks the
# terminal for its colors, and less reads the late answer as keystrokes,
# so it scrolls and redraws on its own.
page() {
  if command -v delta >/dev/null; then
    visible <"$1" | delta --paging always --detect-dark-light never
  else
    visible <"$1" | LESS='' less
  fi
}

# Fetches the VM's bundle into the repository as agentvm/vm and writes the
# diff of its changes to $session/patch. Git checks every object, and the
# bundle must build on a commit the repository has, which the guest names
# in $session/base. Host git computes the diff, not the guest.
fetch_changes() {
  local base
  base=$(head -c 64 "$session/base" 2>/dev/null | LC_ALL=C tr -cd '0-9a-f')
  case ${#base} in
  40 | 64) ;;
  *) die "the VM named no base for its changes" ;;
  esac
  git -C "$root" cat-file -e "$base^{commit}" 2>/dev/null || die "the VM's changes build on an unknown commit"
  git -C "$root" -c fetch.fsckObjects=true fetch -q --no-tags --no-write-fetch-head \
    "$session/vm.bundle" "+refs/agentvm/vm:refs/remotes/agentvm/vm"
  git -C "$root" diff --binary "$base" refs/remotes/agentvm/vm >"$session/patch"
}

drop() {
  guest reset
}

# Shows the copy's changes and asks whether to take, drop, or keep them.
# The summary lists new links, mode changes, and binary files, whose
# content the pager can't show. Keeping leaves the changes in the copy
# for a later take.
review() {
  local patch="$session/patch" answer
  if [ ! -s "$session/vm.bundle" ]; then
    echo "agentvm: the VM copy has no changes"
    return
  fi
  fetch_changes

  if [ -t 0 ] && [ -t 1 ]; then
    page "$patch"
  fi
  git apply --stat --summary "$patch"
  git apply --numstat "$patch" | awk -F'\t' '$1 == "-" { print "binary: " $3 }'
  echo "agentvm: the VM's commits are agentvm/vm, in jj vm@agentvm"
  read -rp "Take, drop, or keep the VM changes? [t/d/K] " answer || answer=k
  case "$answer" in
  t*)
    if ! git -C "$root" apply "$patch"; then
      cp "$patch" "$STATE/rejected.patch"
      die "the patch does not apply, see $STATE/rejected.patch"
    fi
    drop
    ;;
  d*) drop ;;
  esac
}
