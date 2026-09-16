#!/usr/bin/env bash
set -euo pipefail

source /usr/lib/zeit-build/timing.sh
timing_start_script install-personal

echo "==> Preparing builder environment for personal packages..."

prepare_package_environment() {
    if [ ! -d "/var/home/builder" ]; then
        echo "==> /var/home/builder missing. Recreating due to OCI VOLUME purge..."
        mkdir -p /var/home/builder
        chown builder:builder /var/home/builder
    fi

    if [ -L "/opt" ]; then
        echo "==> Removing /opt symlink to allow proprietary AUR installations..."
        rm -f /opt
        mkdir -p /opt
    fi
}
time_step "packages: prepare builder home and /opt" prepare_package_environment

echo "==> Installing personal packages..."

packages=(
  sgdboop-bin
)

if [ ${#packages[@]} -gt 0 ]; then
    timing_note "packages: yay transaction" "count=${#packages[@]} ${packages[*]}"
    time_step "packages: install AUR package set" sudo -u builder yay -S --noconfirm --needed "${packages[@]}"
else
    timing_note "packages: yay transaction" "count=0 skipped"
fi

echo "==> Relocating /opt to /usr/lib/opt for OSTree persistence..."
relocate_opt() {
    mkdir -p /usr/lib/opt
    if [ -n "$(fd --max-depth 1 --min-depth 1 . /opt)" ]; then
        cp -a /opt/. /usr/lib/opt/
    fi
    rm -rf /opt
    mkdir -p /opt
}
time_step "packages: relocate /opt into immutable image" relocate_opt

echo "==> Personal packages installed."

echo "==> Removing obsolete packages from the base image..."
time_shell "packages: remove global openclaw installation" 'npm uninstall -g openclaw 2>/dev/null || true'

obsolete=()
for package in nodejs npm go obs-studio rpm-tools; do
    pacman -Qq "$package" &>/dev/null && obsolete+=("$package")
done

if [ ${#obsolete[@]} -gt 0 ]; then
    time_step "packages: remove obsolete base packages" pacman -Rns --noconfirm "${obsolete[@]}"
fi
