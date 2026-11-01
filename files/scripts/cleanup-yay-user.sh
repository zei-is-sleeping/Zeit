#!/usr/bin/env bash
set -euo pipefail

source /usr/lib/zeit-build/timing.sh
timing_start_script cleanup-yay-user

echo "==> Nuke from orbit: Commencing final system cleanup..."

cleanup_builder() {
    pkill -u builder || true
    userdel -r builder || true
    rm -f /etc/sudoers.d/builder-nopasswd
}
time_step "cleanup: remove temporary AUR builder" cleanup_builder

cleanup_compiler_wrappers() {
    rm -f /usr/local/bin/gcc /usr/local/bin/g++ /usr/local/bin/cc /usr/local/bin/c++ \
        /usr/local/bin/clang /usr/local/bin/clang++ /usr/local/bin/rustc \
        /etc/profile.d/go-v3-gaslight.sh
}
time_step "cleanup: remove x86-64-v3 compiler wrappers" cleanup_compiler_wrappers

echo "==> Clearing build logs..."
clear_build_journals() {
    rm -rf /var/log/journal/* /run/log/journal/*
}
time_step "cleanup: clear build journals" clear_build_journals

cleanup_pacman_cache() {
rm -rf /var/cache/pacman/pkg/* /var/tmp/* /tmp/*
}
time_step "cleanup: clear package caches" cleanup_pacman_cache

echo "==> Cleanup complete. Your atomic image is mathematically pristine."
