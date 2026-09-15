from pathlib import Path

p = Path('Export_Game_Library.sh')
s = p.read_text()

old = '''    HASH_PID=$!; HASH_LAST=-1
    while kill -0 "$HASH_PID" 2>/dev/null; do
      HASH_DONE=$(wc -l < "$PREHASH_RESULTS" 2>/dev/null | tr -d '[:space:]'); [ -z "$HASH_DONE" ] && HASH_DONE=0
      if [ "$HASH_DONE" != "$HASH_LAST" ]; then
        HASH_PCT=0; [ "$HASH_JOB_TOTAL" -gt 0 ] 2>/dev/null && HASH_PCT=$((HASH_DONE * 100 / HASH_JOB_TOTAL))
        printf "    Hashing: %s / %s (%s%%)\\n" "$HASH_DONE" "$HASH_JOB_TOTAL" "$HASH_PCT"
        HASH_LAST="$HASH_DONE"
      fi
      sleep 5
    done
'''

new = '''    HASH_PID=$!; HASH_NEXT_STATUS=500
    while kill -0 "$HASH_PID" 2>/dev/null; do
      HASH_DONE=$(wc -l < "$PREHASH_RESULTS" 2>/dev/null | tr -d '[:space:]'); [ -z "$HASH_DONE" ] && HASH_DONE=0
      if [ "$HASH_DONE" -ge "$HASH_NEXT_STATUS" ] 2>/dev/null; then
        HASH_PCT=0; [ "$HASH_JOB_TOTAL" -gt 0 ] 2>/dev/null && HASH_PCT=$((HASH_DONE * 100 / HASH_JOB_TOTAL))
        printf "    Hashing: %s / %s (%s%%)\\n" "$HASH_DONE" "$HASH_JOB_TOTAL" "$HASH_PCT"
        HASH_NEXT_STATUS=$(( (HASH_DONE / 500 + 1) * 500 ))
      fi
      sleep 5
    done
'''

if old in s:
    s = s.replace(old, new, 1)
elif 'HASH_NEXT_STATUS=500' in s:
    print('500-file hash status cadence already applied.')
else:
    raise SystemExit('current hash progress block not found')

p.write_text(s)
