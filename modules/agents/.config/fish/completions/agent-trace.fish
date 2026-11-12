# Session ids of the current repository, from the transcript file names on
# this machine. `agent-trace list` reads every transcript, which takes
# seconds.
function __agent_trace_sessions
    set -l root (git rev-parse --show-toplevel 2>/dev/null); or return
    set -l prefix (string replace -ra '[^[:alnum:]]' - -- $root)
    set -l transcripts ~/.claude/projects/$prefix*/*.jsonl
    path basename -E -- $transcripts
end

set -l commands list errors denials prompts corrections
complete -c agent-trace -f
complete -c agent-trace -n "not __fish_seen_subcommand_from $commands" -l all -d 'Every session, not only this repository'
complete -c agent-trace -n "not __fish_seen_subcommand_from $commands" -l since -x -d 'Drop what happened before an ISO 8601 date'
complete -c agent-trace -n "not __fish_seen_subcommand_from $commands" -a list -d 'Sessions with their error and denial counts'
complete -c agent-trace -n "not __fish_seen_subcommand_from $commands" -a errors -d 'Failed tool calls'
complete -c agent-trace -n "not __fish_seen_subcommand_from $commands" -a denials -d 'Failed tool calls that read like denials'
complete -c agent-trace -n "not __fish_seen_subcommand_from $commands" -a prompts -d 'Prompts the user typed, after the reply they answer'
complete -c agent-trace -n "not __fish_seen_subcommand_from $commands" -a corrections -d 'Prompts that read like corrections'
complete -c agent-trace -n '__fish_seen_subcommand_from errors denials prompts corrections' -a '(__agent_trace_sessions)'
