# Ghostty locks keyboard input when its own pty turns echo off for a
# password prompt. tmux keeps that pty raw, so under tmux this wrapper
# asks Ghostty for secure input around the sudo prompt. The action is
# a global toggle, and fish skips the rest of a function on Ctrl-C, so
# a fish_postexec handler turns it off however the prompt ends.
if not set -q TMUX; or not set -q GHOSTTY_RESOURCES_DIR; or not command -q osascript
    return
end

function __ghostty_secure_input
    osascript -e 'tell application "Ghostty" to perform action "toggle_secure_input" on focused terminal of selected tab of front window' >/dev/null
end

function __sudo_secure_input_off --on-event fish_postexec
    if not set -qg __sudo_secure_input
        return
    end

    set -eg __sudo_secure_input
    __ghostty_secure_input
end

function sudo --wraps sudo
    if command sudo -n true 2>/dev/null
        command sudo $argv
        return
    end

    set -g __sudo_secure_input
    __ghostty_secure_input
    command sudo -v; or return
    __sudo_secure_input_off
    command sudo $argv
end
