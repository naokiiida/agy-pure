# Default: list available recipes
default:
    @just --list

# Build release binaries with ReleaseFast optimization
build:
    zig build -Doptimize=ReleaseFast

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

# Clean build artifacts and timer caches
clean:
    rm -rf zig-out .zig-cache /tmp/agy_pure_*.timer
