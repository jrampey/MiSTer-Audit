#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; OUT="$ROOT/MiSTer_Audit.sh"; TMP="${TMPDIR:-/tmp}/mister-audit-build.$$"; trap 'rm -f "$TMP"' EXIT
{ printf '%s\n' '#!/bin/bash' '# MiSTer_Audit.sh v1.4' '# Unified MiSTer ROM Library Auditor: read-only audit plus guarded Preview / Apply / Rollback tools.' '# The audit path remains read-only. Library mutation is available only through the explicit Update / Rename menu.' ''; cat "$ROOT/src/audit.sh"; printf '\n'; cat "$ROOT/src/update.sh"; printf '\n'; cat "$ROOT/src/main.sh"; } > "$TMP"
if [[ "${1:-}" == "--check" ]]; then cmp -s "$TMP" "$OUT" || { echo "ERROR: generated runtime drift"; exit 1; }; echo "Generated runtime is synchronized."; else mv "$TMP" "$OUT"; trap - EXIT; chmod +x "$OUT"; fi
