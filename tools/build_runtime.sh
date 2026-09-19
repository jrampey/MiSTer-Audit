#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; OUT="$ROOT/MiSTer_Audit.sh"; TMP="${TMPDIR:-/tmp}/mister-audit-build.$$"; trap 'rm -f "$TMP"' EXIT
{ printf '%s\n' '#!/bin/bash' '# MiSTer_Audit.sh v1.4' '# Unified MiSTer ROM Library Auditor: read-only audit plus guarded Preview / Apply / Rollback tools.' '# The audit path remains read-only. Library mutation is available only through the explicit Update / Rename menu.' ''; cat "$ROOT/src/audit.sh"; printf '\n'; cat "$ROOT/src/update.sh"; printf '\n'; cat "$ROOT/src/main.sh"; } > "$TMP"
if [[ "${1:-}" == "--check" ]]; then
  cmp -s "$TMP" "$OUT" || { echo "ERROR: generated runtime drift"; exit 1; }
  bash -n "$TMP" || { echo "ERROR: generated runtime has invalid Bash syntax"; exit 1; }
  dispatch_count="$(grep -c '^case "${1:-}" in mv "$TMP" "$OUT"; trap - EXIT; chmod +x "$OUT"; fi
 "$TMP" || true)"
  [[ "$dispatch_count" -eq 1 ]] || { echo "ERROR: expected exactly one final runtime dispatch block, found $dispatch_count"; exit 1; }
  for fn in run_audit run_update_tools main_menu; do
    count="$(grep -c "^${fn}() {" "$TMP" || true)"
    [[ "$count" -eq 1 ]] || { echo "ERROR: expected exactly one ${fn} definition, found $count"; exit 1; }
  done
  last_nonblank="$(awk 'NF{line=$0} END{print line}' "$TMP")"
  [[ "$last_nonblank" == "esac" ]] || { echo "ERROR: executable or stray content exists after final dispatch"; exit 1; }
  echo "Generated runtime is synchronized, syntactically valid, and structurally sound."
else mv "$TMP" "$OUT"; trap - EXIT; chmod +x "$OUT"; fi
