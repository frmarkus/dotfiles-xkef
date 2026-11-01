#!/usr/bin/env bash
# Prepares the Arch Linux ARM rootfs for the sandbox, then runs the
# recipe's packages script. The Containerfile runs it as root during
# `agentvm build`, in the layer the builder caches. BUILD holds the
# proxy's CA as ca.pem and the recipe's base as base.tar, which holds
# setup/agentvm/packages and the files it reads. packages gets the base's
# directory and the user's name, and runs as root after the user exists.
#
# Usage: prepare BUILD USER UID GID
set -euxo pipefail

build=$1 user=$2 uid=$3 gid=$4
home=/home/$user

# pacman's download sandbox needs Landlock, which the VM's kernel lacks.
sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
pacman-key --init
pacman-key --populate archlinuxarm
# The session needs git for the copy, socat for the proxy, and flock for
# its lock.
pacman -Syu --noconfirm --needed git socat sudo util-linux

install -m 644 "$build/ca.pem" /etc/ca-certificates/trust-source/anchors/agentvm.pem
update-ca-trust
# Marks the guest for the tools that behave differently inside it.
touch /etc/agentvm

# git asks the proxy without credentials first, and the proxy closes the
# connection on its 407 before git retries. Every repository in the VM
# belongs to its one user, but a shared folder reports root as its owner
# for a moment after boot, which git refuses.
git config --system http.proxyAuthMethod basic
git config --system safe.directory '*'

# The guest user shares the host's IDs, so files in the shared folders
# keep their owner on both sides. macOS gives users group 20, which Arch
# already names.
getent group "$gid" >/dev/null || groupadd -g "$gid" "$user"
userdel -r alarm 2>/dev/null || :
useradd -m -d "$home" -u "$uid" -g "$gid" "$user"
echo "$user ALL=(ALL) NOPASSWD: ALL" >"/etc/sudoers.d/$user"
chmod 440 "/etc/sudoers.d/$user"

mkdir "$build/base"
tar -xf "$build/base.tar" -C "$build/base"
bash "$build/base/setup/agentvm/packages" "$build/base" "$user"
rm -r "$build"
pacman -Scc --noconfirm
