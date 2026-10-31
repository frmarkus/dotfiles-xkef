# Completes the arguments after `agents <command>` as the tool it runs.
function __agents_complete_tool
    set -l args (commandline -xpc)[2..]
    complete -C (string join ' ' -- agent-$args[1] (string escape -- $args[2..]) (commandline -ct))
end

# The subcommands and descriptions come from the @key lines in agents.
function __agents_commands
    awk -F ' :: ' '/^ *# @key agents :: / { print $2 "\t" $3 }' (command -s agents)
end

complete -c agents -f
complete -c agents -n __fish_use_subcommand -xa '(__agents_commands)'
complete -c agents -n __fish_use_subcommand -xa help -d 'Show usage'
complete -c agents -n '__fish_seen_subcommand_from skills trace' -a '(__agents_complete_tool)'

set -l vm_commands claude shell take drop build help
set -l vm_first "__fish_seen_subcommand_from vm; and not __fish_seen_subcommand_from $vm_commands"
complete -c agents -n $vm_first -a claude -d 'Claude Code in the VM'
complete -c agents -n $vm_first -a shell -d 'fish in the VM'
complete -c agents -n $vm_first -a take -d "Show the VM copy's changes, then apply or keep"
complete -c agents -n $vm_first -a drop -d "Discard the VM copy's changes"
complete -c agents -n $vm_first -a build -d 'Rebuild the VM image'
complete -c agents -n $vm_first -a help -d 'Show the help'
complete -c agents -n '__fish_seen_subcommand_from vm; and __fish_seen_subcommand_from claude shell' -l github -d 'Give the session GitHub through the proxy'
