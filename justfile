# TransmissionSwift — common tasks.
# Run `just --list` to see recipes. Assumes Xcode + `xcbeautify` installed.
# Package tests must run under the full Xcode toolchain (the CLT `swift`
# lacks the `Testing` module), so every `swift test` is prefixed with
# DEVELOPER_DIR — see AGENTS.md.

set shell := ["sh", "-cu"]

project := "TransmissionSwift.xcodeproj"
scheme := "TransmissionSwift"
xcode_toolchain := "/Applications/Xcode.app/Contents/Developer"
snapshot_fixture := "TransmissionSwiftUITests/Fixtures/snapshot-10-torrents.json"

# List available recipes.
default:
    @just --list

# Format all Swift sources in place.
format:
    swift format --in-place --recursive .

# Check formatting without writing (CI-style).
lint:
    swift format lint --strict --recursive .

# Fast package tests (TransmissionRPC + TransmissionCore).
test-packages: test-rpc test-core

# Test TransmissionRPC package.
test-rpc:
    cd Packages/TransmissionRPC && DEVELOPER_DIR="{{ xcode_toolchain }}" swift test

# Test TransmissionCore package.
test-core:
    cd Packages/TransmissionCore && DEVELOPER_DIR="{{ xcode_toolchain }}" swift test

# Package tests with -warnings-as-errors (matches CI).
test-packages-strict:
    cd Packages/TransmissionRPC && DEVELOPER_DIR="{{ xcode_toolchain }}" swift test --enable-code-coverage -Xswiftc -warnings-as-errors
    cd ../TransmissionCore && DEVELOPER_DIR="{{ xcode_toolchain }}" swift test --enable-code-coverage -Xswiftc -warnings-as-errors

# Build the macOS app (Debug).
build:
    set -o pipefail; xcodebuild -project {{ project }} -scheme {{ scheme }} -configuration Debug -destination 'platform=macOS' build | (command -v xcbeautify >/dev/null && xcbeautify || cat)

# Run the full app test suite (unit + UI, sandboxed test container).
test-app:
    set -o pipefail; xcodebuild -project {{ project }} -scheme {{ scheme }} -destination 'platform=macOS' test | (command -v xcbeautify >/dev/null && xcbeautify || cat)

# Alias for the full local test pass: packages + app.
test: test-packages test-app

# Run only the daemon-free snapshot UI test (no credentials, no daemon).
test-snapshot:
    set -o pipefail; xcodebuild -project {{ project }} -scheme {{ scheme }} -destination 'platform=macOS' test -only-testing:TransmissionSwiftUITests/TransmissionSwiftUITests/testSnapshotMainWindow | (command -v xcbeautify >/dev/null && xcbeautify || cat)

# Start the local dev daemon (needs `brew install transmission-cli`).
daemon:
    transmission-daemon -g ~/.transmission-dev -t -u dev -v devpass -p 9091 -w /tmp/transmission-dev-downloads

# Run the opt-in E2E UI test against a local daemon (start `just daemon` first).
test-e2e:
    set -o pipefail; TEST_RUNNER_TRANSMISSION_E2E=1 xcodebuild -project {{ project }} -scheme {{ scheme }} -destination 'platform=macOS' test -only-testing:TransmissionSwiftUITests | (command -v xcbeautify >/dev/null && xcbeautify || cat)

# Launch a Debug build showing the committed snapshot fixture (read-only, no daemon).
run-snapshot snapshot="{{ snapshot_fixture }}":
    open Build/Products/Debug/TransmissionSwift.app --args --snapshot {{ snapshot }}

# Fast verification: formatting + package tests.
check: lint test-packages

# Mirror CI locally: hooks + strict package tests + build + app tests.
ci: test-packages-strict build test-app
    prek run --all-files
