function sb -d "Run a command inside a nono sandbox"
    # The agent launchers in conf.d/agents.fish route through here, so every
    # interactive launch runs sandboxed. Use `command <tool>` to skip it.
    if test (count $argv) -eq 0
        echo "Usage: sb <command> [args...]" >&2
        echo "Runs <command> in a nono sandbox using a matching profile." >&2
        echo "Known profiles: claude, pi" >&2
        return 1
    end

    set -l cmd $argv[1]
    set -l rest $argv[2..-1]
    set -l libexec ~/.local/libexec/agents

    # The agent VM's image holds the skills, and an install there would
    # land on a disk that the VM throws away.
    switch $cmd
        case claude pi
            if test -x $libexec/agent-skills; and not __sb_in_vm
                $libexec/agent-skills ensure $cmd
            end
    end

    set -l cmd_args
    switch $cmd
        case claude
            # The repo settings override the keys they name in the settings
            # file Claude Code rewrites. nono is the OS-level sandbox, and
            # macOS can't nest Seatbelt, so Claude Code's own bash sandbox
            # stays off. With it on, every Bash command fails with
            # "sandbox_apply: Operation not permitted".
            touch $HOME/.claude.json.lock $HOME/.claude.lock
            set -a cmd_args --settings (jq -c '.sandbox.enabled = false' $HOME/.claude/settings.dotfiles.json)
    end

    # The agent VM is the sandbox there, so the agent runs without nono, and
    # Claude Code without permission prompts.
    if __sb_in_vm
        test $cmd = claude; and set -p cmd_args --dangerously-skip-permissions
        command $cmd $cmd_args $rest
        return $status
    end

    if not command -q nono
        printf '\033[33mNo sandbox available (install nono)\033[0m\n' >&2
        read -P "Continue without sandbox? [y/N] " reply
        string match -qi y -- $reply; or return 1
        command $cmd $rest
        return $status
    end

    # The profiles point the toolchain homes here, since the host runs what
    # its own homes hold. nono skips a grant whose path doesn't exist.
    mkdir -p $XDG_CACHE_HOME/agents-sandbox

    # --strict-broker-path refuses a grant that lets the agent write a PATH
    # directory, where it could plant a binary that runs later outside the
    # sandbox.
    set -l nono_args --silent --log-file /dev/null --allow-cwd --read $DOTFILES_DIR --profile $cmd --strict-broker-path
    test "$SB_ALLOW_LAUNCH_SERVICES" = 1; and set -a nono_args --allow-launch-services
    # gh, a Go program, checks certificates only against the macOS trust
    # store, so the proxy's CA must sit there for gh to reach GitHub
    # through the credential proxy.
    test (uname) = Darwin; and set -a nono_args --trust-proxy-ca
    # The proxy CA lives one day by default, and sessions share the
    # keychain copy, so a session that starts on a day-old CA fails TLS
    # with "certificate has expired" within hours. A week outlasts any
    # session.
    set -a nono_args --proxy-ca-validity 7

    # macOS logs the sandbox denials where only an unsandboxed process may
    # read them, so a recorder streams them while the agent runs, and
    # `agents trace collect` caches them for `agents trace sandbox`.
    set -l recorder
    if test -x $libexec/agent-trace
        $libexec/agent-trace record &
        set recorder $last_pid
        disown
    end

    # Not exec: the launchers call this function and clear the agent state
    # after the agent exits.
    nono run $nono_args -- $cmd $cmd_args $rest
    set -l rc $status

    if set -q recorder[1]
        kill $recorder 2>/dev/null
        $libexec/agent-trace collect >/dev/null 2>&1 &
        disown
    end
    return $rc
end

# agentvm marks every agent VM image with this file, as agent-trace
# checks too.
function __sb_in_vm
    test -e /etc/agentvm
end
