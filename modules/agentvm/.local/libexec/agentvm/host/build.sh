#!/usr/bin/env bash
# `agentvm build`: the image, from the signed Arch Linux ARM rootfs, the
# sandbox's own setup in image/prepare.sh, and a recipe's provision script.
#
# Uses $LIBEXEC, which the agentvm script sets.
# shellcheck disable=SC2154

# Arch Linux ARM serves its rootfs over plain HTTP only, so its signature
# decides. The key is the "builder" entry in the project's keyring, which
# GitHub serves over HTTPS.
readonly ALARM=http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
readonly ALARM_KEYRING=https://raw.githubusercontent.com/archlinuxarm/archlinuxarm-keyring/master/archlinuxarm.gpg
readonly ALARM_KEY=68B3537F39A313B3E574D06777193F152BDBE6A6

# Downloads the Arch Linux ARM rootfs to $1, which only a tarball whose
# signature checks out reaches.
fetch_rootfs() {
  local gnupg
  gnupg=$(mktemp -d)
  mkdir -p "${1%/*}"
  curl -fSL -o "$1.tmp" "$ALARM"
  curl -fSL -o "$1.sig" "$ALARM.sig"
  curl -fsSL "$ALARM_KEYRING" | GNUPGHOME=$gnupg gpg --batch --quiet --import
  if ! GNUPGHOME=$gnupg gpg --batch --status-fd 1 --verify "$1.sig" "$1.tmp" 2>/dev/null |
    grep -q "^\[GNUPG:\] VALIDSIG $ALARM_KEY "; then
    rm -r "$gnupg" "$1.tmp" "$1.sig"
    die "the rootfs signature does not verify"
  fi
  rm -r "$gnupg" "$1.sig"
  mv "$1.tmp" "$1"
}

# The recipe: what the dotfiles put in the image, run after the sandbox's
# own setup.
readonly PROVISION=setup/agentvm/provision

# Builds the image. The build runs downloaded install scripts, so its
# context holds the CA's certificate and the dotfiles' working tree,
# without ignored files, and never the CA's key, the repository copies,
# or a host checkout.
build() {
  local source=${DOTFILES_DIR:?} context
  ensure_ca
  [ -s "$DATA/alarm.tar.gz" ] || fetch_rootfs "$DATA/alarm.tar.gz"
  context=$(mktemp -d)
  cp -c "$DATA/alarm.tar.gz" "$context/alarm.tar.gz"
  cp "$CA_CERT" "$context/ca.pem"
  cp "$LIBEXEC/image/prepare.sh" "$LIBEXEC/guest/session.sh" "$context/"
  git -C "$source" archive -o "$context/source.tar" "$(cd "$source" && snapshot)"
  local rc=0
  # The redrawn tty view flickers the cursor for the whole build.
  container build --progress plain -f "$LIBEXEC/image/Containerfile" -t "$IMAGE" \
    --build-arg GUEST_USER="$USER" --build-arg GUEST_UID="$(id -u)" \
    --build-arg GUEST_GID="$(id -g)" --build-arg PROVISION="$PROVISION" "$context" || rc=$?
  rm -r "$context"
  clean
  return "$rc"
}

# Frees what a build leaves behind. The builder keeps every layer it
# built, tens of GB after a few builds, and the image it replaced stays
# too. Neither helps the next build, which rebuilds the whole image from
# a new snapshot of the source. Both commands act on all of `container`,
# which serves only agentvm here: they stop any other build and remove
# every dangling image.
clean() {
  container builder delete --force >/dev/null 2>&1 || :
  container image prune >/dev/null 2>&1 || :
}
