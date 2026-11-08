# Sources a tool's init script, such as `starship init fish`, from a cache
# file instead of spawning the tool on every shell start. The file name
# holds the arguments, so an edited call misses. The first line records
# the resolved binary path. Homebrew installs each version under its own
# Cellar path and keeps the build time as the mtime, so a changed path
# marks an upgrade there. pacman replaces the binary in place, so a binary
# newer than the cache marks an upgrade there.
#
#   __cached_init zoxide init fish --cmd z
function __cached_init
    set -l bin (command -s $argv[1]); or return
    set -l cache $XDG_CACHE_HOME/fish/init/(string join -- ' ' $argv |string escape --style=var).fish
    set -l stamp "# "(path resolve $bin)

    set -l first
    test -s $cache; and read first <$cache
    if test "$first" != "$stamp"; or test $bin -nt $cache
        set -l init ($bin $argv[2..]); or return
        set -q init[1]; or return 1

        mkdir -p (path dirname $cache)
        # Shells that start together after an upgrade each write their
        # own file, so none moves another's partial output into place.
        set -l tmp $cache.$fish_pid.tmp
        printf '%s\n' $stamp $init >$tmp
        command mv -f $tmp $cache
    end

    source $cache
end
