#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sources=(UsageBarCLI/ClaudeNativeMessage.swift UsageBarCLI/NativeMessage.swift UsageBarCLI/ProviderExecutable.swift)
swiftc UsageBar/Core/BrandPaths.swift "${sources[@]}" tests/native-message/main.swift -o "$work/checks"
"$work/checks"
printf '%s\n' 'import Foundation' 'exit(runNativeMessage(args: Array(CommandLine.arguments.dropFirst())))' > "$work/main.swift"
swiftc UsageBar/Core/BrandPaths.swift "${sources[@]}" "$work/main.swift" -o "$work/message"
python3 tests/native-message/integration.py "$work/message"
