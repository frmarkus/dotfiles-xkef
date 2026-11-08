# ── Podman compatibility ─────────────────────────────
# Docker clients reach podman through the user socket that podman.socket
# listens on in Linux. macOS needs no DOCKER_HOST: podman-mac-helper links
# /var/run/docker.sock.
if test -S "$XDG_RUNTIME_DIR/podman/podman.sock"
    set -gx DOCKER_HOST "unix://$XDG_RUNTIME_DIR/podman/podman.sock"
end
