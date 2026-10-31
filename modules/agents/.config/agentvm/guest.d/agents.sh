# shellcheck shell=sh
# Sourced in the agent VM by agentvm's guest session, before the session
# starts.

# The host's picker shows this VM's agent. Its hooks write through
# agent-state, which keys entries by pane, so the guest takes the fixed
# key that the host's vm-status reads, and keeps its entries in the
# status folder that agentvm passes to the host.
state=$HOME/.local/state
mkdir -p "$state"
[ ! -e "$state/agents" ] && [ ! -L "$state/agents" ] || rm -r "$state/agents"
ln -s "$AGENTVM_STATUS" "$state/agents"
export WEZTERM_PANE=0

# First-run onboarding asks for a login even with a token set, and the VM
# replaces the folder trust prompt. The image starts without this file.
cfg=$HOME/.claude.json
[ -f "$cfg" ] || echo "{}" >"$cfg"
tmp=$(mktemp)
jq --arg dir "$PWD" '.hasCompletedOnboarding = true | .projects[$dir].hasTrustDialogAccepted = true' "$cfg" >"$tmp"
mv "$tmp" "$cfg"
