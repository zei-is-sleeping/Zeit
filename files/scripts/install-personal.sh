#!/usr/bin/env bash
set -euo pipefail

source /usr/lib/zeit-build/timing.sh
timing_start_script install-personal

echo "==> Installing personal AUR packages..."
packages=(
    sgdboop-bin
)

if [ ${#packages[@]} -gt 0 ]; then
    timing_note "packages: yay transaction" "count=${#packages[@]} ${packages[*]}"
    time_step "packages: install AUR package set" sudo -u builder yay -S --noconfirm --needed "${packages[@]}"
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

echo "==> Removing obsolete build-time dependencies from base image..."
obsolete=()
for package in nodejs npm go obs-studio rpm-tools; do
    pacman -Qq "$package" &>/dev/null && obsolete+=("$package")
done

if [ ${#obsolete[@]} -gt 0 ]; then
    time_step "packages: remove obsolete base packages" pacman -Rns --noconfirm "${obsolete[@]}"
fi
