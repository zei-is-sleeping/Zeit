#!/usr/bin/env bash
set -euo pipefail

source /usr/lib/zeit-build/timing.sh
timing_start_script setup-yay-user

echo "==> Configuring makepkg.conf for x86-64-v3 builds..."
configure_makepkg() {
    cat >> /etc/makepkg.conf <<'EOF'

# Zeit image-build overrides
OPTIONS=(strip docs !libtool !staticlibs emptydirs zipman purge !debug !lto)
CFLAGS="-march=x86-64-v3 -mtune=generic -O2 -pipe -fno-plt -fexceptions -Wp,-D_FORTIFY_SOURCE=3 -Wformat -Werror=format-security"
CXXFLAGS="$CFLAGS -Wp,-D_GLIBCXX_ASSERTIONS"
LDFLAGS="-Wl,-O1 -Wl,--sort-common -Wl,--as-needed -Wl,-z,relro -Wl,-z,now -fuse-ld=mold"
RUSTFLAGS="-C opt-level=2 -C target-cpu=x86-64-v3 -C link-arg=-fuse-ld=mold"
MAKEFLAGS="-j$(nproc)"
EOF
}
time_step "builder: configure makepkg" configure_makepkg

echo "==> Creating temporary builder user for AUR..."
create_builder() {
    useradd -m -G wheel builder
    printf 'builder ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/builder-nopasswd
    chmod 0440 /etc/sudoers.d/builder-nopasswd
}
time_step "builder: create temporary AUR user" create_builder

echo "==> AUR builder environment ready."
