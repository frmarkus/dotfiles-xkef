# Agent launchers. Each function installs its agent on first use, then runs
# it. `command <agent>` skips both.

function claude --wraps claude --description "Claude Code"
    if not command -q claude
        printf '  Installing claude...\n'
        curl -fsSL https://claude.ai/install.sh | bash -s -- latest; or return
    end
    ~/.local/libexec/agents/agent-skills ensure claude
    command claude $argv
    set -l rc $status

    # The agent may exit without removing its agent-state entry: a crash or
    # a killed process.
    ~/.local/libexec/agents/agent-state clear
    return $rc
end

function pi --wraps pi --description "pi.dev coding agent"
    if not command -q pi
        printf '  Installing pi...\n'
        # The version the extensions type-check against.
        set -l pi_version (jq -r '.devDependencies["@earendil-works/pi-coding-agent"]' $DOTFILES_DIR/.mise/pi/package.json)
        npm install -g @earendil-works/pi-coding-agent@$pi_version; or return
    end

    # pi picks its theme by name from a file the pi hook of `theme` renders.
    # A machine that has never switched themes has no file yet, and pi falls
    # back to its built-in dark theme without reporting it. Render the
    # current theme once.
    set -l pi_agent_dir (set -q PI_CODING_AGENT_DIR && echo $PI_CODING_AGENT_DIR || echo $HOME/.pi/agent)
    if command -q theme; and not test -f $pi_agent_dir/themes/dots.json
        theme --apply >/dev/null
    end

    ~/.local/libexec/agents/agent-skills ensure pi
    command pi $argv
    set -l rc $status

    # The agent may exit without removing its agent-state entry: a crash or
    # a killed process.
    ~/.local/libexec/agents/agent-state clear
    return $rc
end
