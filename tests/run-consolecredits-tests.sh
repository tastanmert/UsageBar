#!/bin/bash
# Anthropic Console organization credits, read path only: tolerant parsing of the Console's JSON
# (prepaid balance, promo tranches, month spend, the tier limit in cents), how an HTTP answer is
# classified (401/403 reconnect versus Cloudflare HTML versus read failed), the cookie header, the
# fetch sequence, and the state machine (not connected, reconnect, stale, real zero). No network
# and no WebKit store: the cookie jar and the transport are injected.
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
swiftc -o "$build_dir/run" \
    tests/consolecredits/main.swift \
    UsageBar/Core/ConsoleCredits.swift UsageBar/Core/ConsoleCreditsFetch.swift \
    UsageBar/Stores/ConsoleCreditsStore.swift UsageBar/Core/BrandPaths.swift
"$build_dir/run"
