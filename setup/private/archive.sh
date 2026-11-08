# shellcheck shell=bash disable=SC2034 # The sourcing scripts read the variables.
# What setup/private/decrypt and `mise run encrypt` share. Both source it.

key_ref="op://Dev/dotfiles-age-key/password"

# The archive is public, and anyone can encrypt to the recipients, so its
# signature proves who made it. The namespace keeps a signature that the
# key made for a git commit from passing for the archive's.
signature_namespace=dotfiles-archive
signer=dotfiles

# Returns 0 when $1.sig signs $1 with a key in $2/private/allowed_signers.
verify_archive() {
  ssh-keygen -Y verify -f "$2/private/allowed_signers" -I "$signer" \
    -n "$signature_namespace" -s "$1.sig" <"$1" >/dev/null 2>&1
}
