#!/usr/bin/env bash
set -euo pipefail

source /usr/lib/zeit-build/timing.sh
timing_start_script setup-v3-gaslight

echo "==> Deploying global compiler gaslight wrappers for v3 architecture..."

install_compiler_wrappers() {
    mkdir -p /usr/local/bin

    # 1. C/C++ Compilers (GCC & Clang)
    # Intercepts rogue CMake/Meson scripts that hardcode -march=native
    cat << 'EOF' | tee /usr/local/bin/gcc /usr/local/bin/g++ /usr/local/bin/cc /usr/local/bin/c++ /usr/local/bin/clang /usr/local/bin/clang++ > /dev/null
#!/bin/bash
NEW_ARGS=()
for arg in "$@"; do
    case "$arg" in
        -march=native) NEW_ARGS+=("-march=x86-64-v3") ;;
        -mtune=native) NEW_ARGS+=("-mtune=generic") ;;
        *) NEW_ARGS+=("$arg") ;;
    esac
done
COMPILER_NAME=$(basename "$0")
exec "/usr/bin/$COMPILER_NAME" "${NEW_ARGS[@]}"
EOF

    # 2. Rust Compiler (rustc)
    # Catches both separate and glued target-cpu tokens
    cat << 'EOF' | tee /usr/local/bin/rustc > /dev/null
#!/bin/bash
NEW_ARGS=()
for arg in "$@"; do
    case "$arg" in
        target-cpu=native) NEW_ARGS+=("target-cpu=x86-64-v3") ;;
        -Ctarget-cpu=native) NEW_ARGS+=("-Ctarget-cpu=x86-64-v3") ;;
        *) NEW_ARGS+=("$arg") ;;
    esac
done
exec "/usr/bin/rustc" "${NEW_ARGS[@]}"
EOF

    # 3. Make wrappers executable
    chmod +x /usr/local/bin/gcc /usr/local/bin/g++ /usr/local/bin/cc /usr/local/bin/c++ \
             /usr/local/bin/clang /usr/local/bin/clang++ /usr/local/bin/rustc

    # 4. Go Compiler architecture level
    echo "export GOAMD64=v3" > /etc/profile.d/go-v3-gaslight.sh
}

time_step "builder: install temporary x86-64-v3 compiler wrappers" install_compiler_wrappers

echo "==> Hardware gaslighting active. Compilations will safely target x86-64-v3."
