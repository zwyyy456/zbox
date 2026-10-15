#!/usr/bin/env bash
# Real filesystem fixture only; never scans user-selected or personal directories.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zbox-search-lifecycle.XXXXXX")"
trap 'rm -rf "$BENCH_DIR"' EXIT
swiftc -D FILE_INDEX_BENCHMARK -O -swift-version 6 -parse-as-library \
  -module-cache-path "$BENCH_DIR/modules" \
  "$ROOT_DIR/zbox/Plugins/FileSearch/FileIndexStore.swift" \
  "$ROOT_DIR/zbox/Plugins/FileSearch/FileMappedIndex.swift" \
  "$ROOT_DIR/zbox/Plugins/FileSearch/FileIndexScanner.swift" \
  "$ROOT_DIR/zbox/Plugins/FileSearch/FileIndexWatcher.swift" \
  "$ROOT_DIR/zbox/Plugins/FileSearch/FileSearchQuery.swift" \
  "$ROOT_DIR/zbox/Plugins/FileSearch/FileSearchSettings.swift" \
  "$ROOT_DIR/script/benchmark_file_search_lifecycle.swift" -o "$BENCH_DIR/benchmark"
"$BENCH_DIR/benchmark" prepare "$BENCH_DIR" "${1:-30000}"
"$BENCH_DIR/benchmark" scan "$BENCH_DIR" "${2:-30}"
"$BENCH_DIR/benchmark" load "$BENCH_DIR"
