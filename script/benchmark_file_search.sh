#!/usr/bin/env bash
# Synthetic metadata benchmark; never enumerates user files. Second argument: repeated, unique, chinese or mixed.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zbox-search-benchmark.XXXXXX")"
trap 'rm -rf "$BENCH_DIR"' EXIT
swiftc -D FILE_INDEX_BENCHMARK -O -swift-version 6 -parse-as-library \
  -module-cache-path "$BENCH_DIR/modules" \
  "$ROOT_DIR/zbox/Plugins/FileSearch/FileIndexStore.swift" \
  "$ROOT_DIR/zbox/Plugins/FileSearch/FileMappedIndex.swift" \
  "$ROOT_DIR/zbox/Plugins/FileSearch/FileSearchQuery.swift" \
  "$ROOT_DIR/zbox/Plugins/FileSearch/FileSearchSettings.swift" \
  "$ROOT_DIR/script/benchmark_file_search.swift" \
  -o "$BENCH_DIR/benchmark"
/usr/bin/time -l "$BENCH_DIR/benchmark" "${1:-100000}" "${2:-repeated}"
