#!/usr/bin/env bash
set -euo pipefail

source /usr/lib/zeit-build/timing.sh
timing_start_script preset-cachyos

# Step 1: Configure baseline pacman performance and container sandbox settings.
# Sets up Parallel Downloads because github pays for the internet~
# Disables Sandbox to prevent permission errors in the container.
echo "==> Configuring baseline pacman settings..."
configure_pacman_baseline() {
    sed -i 's/^#*ParallelDownloads.*/ParallelDownloads = 15/' /etc/pacman.conf
    if ! grep -q '^DisableSandbox$' /etc/pacman.conf; then
        sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
    fi
}
time_step "preset: configure pacman baseline" configure_pacman_baseline

# Step 2: Initialize and populate Arch keyring.
echo "==> Initializing Arch keyring..."
time_step "preset: initialize pacman keyring" pacman-key --init
time_step "preset: populate Arch keyring" pacman-key --populate archlinux

# Step 3: Batch-import and locally sign third-party keys.
# - F3B607488DB35A47: CachyOS repository signing key
# - 3056513887B78AEB: Chaotic-AUR repository signing key
echo "==> Importing third-party signing keys..."
setup_third_party_keys() {
    pacman-key --recv-keys F3B607488DB35A47 3056513887B78AEB --keyserver keyserver.ubuntu.com
    pacman-key --lsign-key F3B607488DB35A47 3056513887B78AEB
}
time_step "preset: import third-party keys" setup_third_party_keys

# Step 4: Dynamically bootstrap CachyOS without hardcoded version strings.
# The generic [cachyos] repo is standard x86_64, so stock Arch pacman can read it.
# We point directly to CachyOS's Cloudflare geo-routed CDN, sync cachyos.db, and let
# pacman resolve the newest mirrorlists, keyrings, and patched pacman binary dynamically.
# Yes all of this because CachyOS literally does not have a syslinked url without versions.
echo "==> Bootstrapping CachyOS repositories dynamically..."
bootstrap_cachyos() {
    printf '\n[cachyos]\nServer = https://cdn.cachyos.org/repo/$arch/$repo\n' >> /etc/pacman.conf

    pacman -Sy --noconfirm cachyos-keyring cachyos-mirrorlist cachyos-v3-mirrorlist cachyos/pacman

    # Clean up the temporary bootstrap block so configure_repositories can set final priority
    sed -i '/^\[cachyos\]/,/^Server = /d' /etc/pacman.conf
}
time_step "preset: bootstrap CachyOS" bootstrap_cachyos

# Step 5: Install Chaotic-AUR keyring and mirrorlist.
# Chaotic-AUR maintains static, unversioned symlinks at the root of their CDN.
echo "==> Installing Chaotic-AUR keyring and mirrorlist..."
install_chaotic_keyring_and_mirrorlist() {
    local chaotic_url="https://cdn-mirror.chaotic.cx/chaotic-aur"
    pacman -U --noconfirm \
        "${chaotic_url}/chaotic-keyring.pkg.tar.zst" \
        "${chaotic_url}/chaotic-mirrorlist.pkg.tar.zst"
}
time_step "preset: install Chaotic-AUR mirrorlist" install_chaotic_keyring_and_mirrorlist

# Step 6: Prefer CachyOS rerouted CDN.
# We swap cdn77 for cdn.cachyos.org (CachyOS Cloudflare/geo-routed proxy) to prevent exit code 1.
echo "==> Switching CachyOS mirrorlists to rerouted CDN..."
prefer_cachyos_rerouted_cdn() {
    local mirrorlist
    for mirrorlist in /etc/pacman.d/cachyos-mirrorlist /etc/pacman.d/cachyos-v3-mirrorlist; do
        sed -i '\|^Server = https://cdn77\.cachyos\.org/|s|^|# Disabled in CI: |' "$mirrorlist"
        sed -i '\|^# Server = https://cdn\.cachyos\.org/|s|^# ||' "$mirrorlist"
    done
}
time_step "preset: prefer CachyOS rerouted CDN" prefer_cachyos_rerouted_cdn

# Step 7: Inject repository blocks into /etc/pacman.conf with strict priority.
# Priority order:
# 1. CachyOS v3 repos sit ABOVE [core] so AVX2-optimized binaries override stock Arch.
# 2. Official Arch repos ([core], [extra], [multilib]) sit in the middle.
# 3. Chaotic-AUR sits at the BOTTOM so prebuilts only supply missing packages.
echo "==> Configuring repository priority in pacman.conf..."
configure_repositories() {
    local tmp_conf
    tmp_conf=$(mktemp)

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^\[core\] ]] && ! grep -q '\[cachyos-v3\]' "$tmp_conf"; then
            cat << 'EOF' >> "$tmp_conf"
[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-core-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-extra-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist

EOF
        fi
        printf '%s\n' "$line" >> "$tmp_conf"
    done < /etc/pacman.conf

    mv "$tmp_conf" /etc/pacman.conf

    # Enable multilib
    if grep -q '^#\[multilib\]' /etc/pacman.conf; then
        sed -i '/^#\[multilib\]/,/^#Include =/ s/^#//' /etc/pacman.conf
    elif ! grep -q '^\[multilib\]' /etc/pacman.conf; then
        printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf
    fi

    # Append Chaotic-AUR to the bottom
    if ! grep -q '^\[chaotic-aur\]' /etc/pacman.conf; then
        cat << 'EOF' >> /etc/pacman.conf

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
    fi
}
time_step "preset: configure repository priority" configure_repositories

# Step 8: Single full system upgrade to CachyOS v3.
echo "==> Upgrading system packages to CachyOS v3..."
time_step "preset: upgrade system to CachyOS v3" pacman -Syu --noconfirm

# Step 9: Install base system tools.
echo "==> Installing base toolset..."
time_step "preset: install base tools and utilities" pacman -S --noconfirm --needed \
    base-devel expac git curl sudo mold \
    yazi nvim unzip libarchive \
    ripgrep sd fd fzf bat eza \
    scx-scheds scx-tools composefs podman \
    yay

# Step 10: Install CachyOS BORE kernel and NVIDIA drivers.
echo "==> Installing CachyOS BORE kernel and NVIDIA modules..."
time_step "preset: install CachyOS BORE kernel and NVIDIA modules" pacman -S --noconfirm --needed \
    cachyos-v3/linux-cachyos-bore \
    cachyos-v3/linux-cachyos-bore-headers \
    cachyos-v3/linux-cachyos-bore-nvidia-open \
    nvidia-utils

# Step 11: Cleanly remove stock kernel and wipe orphaned modules.
echo "==> Purging stock Linux kernel..."
remove_stock_kernel() {
    pacman -Rdd --noconfirm linux || true
    find /usr/lib/modules -mindepth 1 -maxdepth 1 ! -name '*cachyos*' -exec rm -rf {} +
}
time_step "preset: remove stock kernel" remove_stock_kernel

echo "==> CachyOS Presets applied successfully."
