#!/usr/bin/env bash
# Synthetic long-image assembly or cancellation; never captures the screen.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zbox-scroll-benchmark.XXXXXX")"
trap 'rm -rf "$BENCH_DIR"' EXIT
swiftc -O -swift-version 6 -parse-as-library -module-cache-path "$BENCH_DIR/modules" \
 "$ROOT_DIR/zbox/Plugins/Screenshot/Scrolling/ScreenshotScrollStitcher.swift" \
 "$ROOT_DIR/script/benchmark_screenshot_scroll.swift" -o "$BENCH_DIR/benchmark"
/usr/bin/time -l "$BENCH_DIR/benchmark" "${1:-finish}" "${2:-1}"
