# Default: list available recipes
default:
    @just --list

# Build release binaries with ReleaseFast optimization
build:
    zig build -Doptimize=ReleaseFast

# Build optimized release binaries with ReleaseSmall (-Oz, best for Apple Silicon L1i cache)
build-small:
    zig build -Doptimize=ReleaseSmall

# Build debug binaries
build-debug:
    zig build

# Run all unit tests
test:
    zig build test

# Install release binaries to ~/.gemini/antigravity-cli/bin
install:
    zig build install-cli -Doptimize=ReleaseFast
    @echo "✓ Successfully installed agy_pure, agy_title, and agy_notify to ~/.gemini/antigravity-cli/bin/"

# Benchmark binaries with hyperfine (< 2.5ms budget target)
bench: build
    hyperfine --warmup 5 \
        ./zig-out/bin/agy_pure \
        ./zig-out/bin/agy_title \
        ./zig-out/bin/agy_notify

# Full quality gate: unit tests + L1i cache verification + latency benchmark
gate: test l1-check bench

# Verify machine code fits within Apple Silicon L1i cache (ReleaseSmall: Target < 140 KB)
l1-check: build-small
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== Apple Silicon L1 Instruction Cache Gate (ReleaseSmall: Target < 140 KB) ==="
    for bin in agy_pure agy_title agy_notify; do
        TEXT_BYTES=$(size -m "zig-out/bin/$bin" | awk '/Section __text/ {print $3}')
        TEXT_KB=$((TEXT_BYTES / 1024))
        if [ "$TEXT_BYTES" -le 143360 ]; then
            echo "✓ $bin: ${TEXT_KB} KB ($TEXT_BYTES bytes) fits inside Apple Silicon L1i"
        else
            echo "✗ $bin: ${TEXT_KB} KB exceeds L1i limit!"
            exit 1
        fi
    done

# Clean build artifacts and timer caches
clean:
    rm -rf zig-out .zig-cache /tmp/agy_pure_*.timer
