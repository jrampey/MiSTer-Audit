from pathlib import Path

p = Path('Export_Game_Library.sh')
s = p.read_text()

marker = 'METADATA_LAYER_STATUS="${METADATA_LAYER_STATUS:-Unknown}"; EXPORTER_BUILD_SHA1="$(hash_file "$0")"\n'
if 'EXPORTER_BUILD_ID="$(exporter_build_id "$0")"' not in s:
    if marker not in s:
        raise SystemExit('startup marker not found')
    block = marker + '''exporter_build_id() {
  local p="$1" digest="" rest=""
  if command -v md5sum >/dev/null 2>&1; then
    read -r digest rest < <(md5sum "$p" 2>/dev/null)
  elif command -v openssl >/dev/null 2>&1; then
    digest="$(openssl md5 "$p" 2>/dev/null)"
    digest="${digest##* }"
  else
    digest="$EXPORTER_BUILD_SHA1"
  fi
  printf '%.8s' "$digest"
}
EXPORTER_BUILD_ID="$(exporter_build_id "$0")"
'''
    s = s.replace(marker, block, 1)
    old_banner = 'echo "+--------------------------------------------------+"; echo "| MiSTer ROM Library Auditor v1.4                 |"; echo "| Read-only audit - no ROMs or saves are changed  |"; echo "+--------------------------------------------------+"; echo\n'
    new_banner = 'echo "+--------------------------------------------------+"; echo "| MiSTer ROM Library Auditor v1.4                 |"; printf "| Build: %-41s|\\n" "$EXPORTER_BUILD_ID"; echo "| Read-only audit - no ROMs or saves are changed  |"; echo "+--------------------------------------------------+"; echo\n'
    if old_banner not in s:
        raise SystemExit('startup banner not found')
    s = s.replace(old_banner, new_banner, 1)

start = 'if [ "$USE_HASH_CACHE" -eq 0 ]; then : > "$PREHASH_RESULTS"; pv_start=$SECONDS;'
end = 'REPORT_START=$(date +%s)'
if 'Full Verification: hashing $HASH_JOB_TOTAL supported files' not in s:
    a = s.find(start)
    b = s.find(end, a)
    if a < 0 or b < 0:
        raise SystemExit('Full Verification prehash block not found')
    new = '''if [ "$USE_HASH_CACHE" -eq 0 ]; then
  : > "$PREHASH_RESULTS"; pv_start=$SECONDS
  if [ -s "$WORK.hashjobs" ]; then
    HASH_JOB_TOTAL=$(tr -cd '\\0' < "$WORK.hashjobs" | wc -c | tr -d '[:space:]')
    [ -z "$HASH_JOB_TOTAL" ] && HASH_JOB_TOTAL=0
    echo "    Full Verification: hashing $HASH_JOB_TOTAL supported files..."
    XARGS_PARALLEL_ARGS=""
    if xargs --help 2>&1 | grep -q -- '-P'; then XARGS_PARALLEL_ARGS="-P $FULL_VERIFY_WORKERS"; fi
    if command -v sha1sum >/dev/null 2>&1; then
      xargs -0 -n1 $XARGS_PARALLEL_ARGS sh -c 'p="$1"; h=$(sha1sum "$p" 2>/dev/null); h=${h%% *}; printf "%s\\t%s\\n" "$h" "$p"' sh < "$WORK.hashjobs" > "$PREHASH_RESULTS" &
    else
      xargs -0 -n1 $XARGS_PARALLEL_ARGS sh -c 'p="$1"; h=$(openssl sha1 "$p" 2>/dev/null); h=${h##* }; printf "%s\\t%s\\n" "$h" "$p"' sh < "$WORK.hashjobs" > "$PREHASH_RESULTS" &
    fi
    HASH_PID=$!; HASH_LAST=-1
    while kill -0 "$HASH_PID" 2>/dev/null; do
      HASH_DONE=$(wc -l < "$PREHASH_RESULTS" 2>/dev/null | tr -d '[:space:]'); [ -z "$HASH_DONE" ] && HASH_DONE=0
      if [ "$HASH_DONE" != "$HASH_LAST" ]; then
        HASH_PCT=0; [ "$HASH_JOB_TOTAL" -gt 0 ] 2>/dev/null && HASH_PCT=$((HASH_DONE * 100 / HASH_JOB_TOTAL))
        printf "    Hashing: %s / %s (%s%%)\\n" "$HASH_DONE" "$HASH_JOB_TOTAL" "$HASH_PCT"
        HASH_LAST="$HASH_DONE"
      fi
      sleep 5
    done
    wait "$HASH_PID"
    HASH_DONE=$(wc -l < "$PREHASH_RESULTS" 2>/dev/null | tr -d '[:space:]'); [ -z "$HASH_DONE" ] && HASH_DONE=0
    HASH_PCT=0; [ "$HASH_JOB_TOTAL" -gt 0 ] 2>/dev/null && HASH_PCT=$((HASH_DONE * 100 / HASH_JOB_TOTAL))
    echo "    Hashing complete: $HASH_DONE / $HASH_JOB_TOTAL ($HASH_PCT%)"
    [ "$HASH_DONE" -eq "$HASH_JOB_TOTAL" ] || { echo "ERROR: Full Verification hash pass incomplete ($HASH_DONE/$HASH_JOB_TOTAL)."; exit 1; }
    while IFS=$'\\t' read -r ph pp; do [ -n "$pp" ] && PREHASH_SHA_BY_PATH["$pp"]="$ph"; done < "$PREHASH_RESULTS"
  fi
  FULL_VERIFY_PARALLEL_SECONDS=$((SECONDS-pv_start))
fi
'''
    s = s[:a] + new + s[b:]

p.write_text(s)
