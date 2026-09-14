from pathlib import Path
p=Path('Export_Game_Library.sh')
s=p.read_text()
def rep(a,b):
    global s
    if a not in s: raise SystemExit('pattern missing: '+a[:140])
    s=s.replace(a,b,1)

rep('CLASS_CACHE_NEW="$WORK.classification_cache_new"\nCACHE_META=', 'CLASS_CACHE_NEW="$WORK.classification_cache_new"\nDISCOVERY_SNAPSHOT="$AUDIT/discovery_snapshot.tsv"\nDISCOVERY_SNAPSHOT_NEW="$WORK.discovery_snapshot_new"\nDISCOVERY_CHANGED="$WORK.discovery_changed"\nDISCOVERY_FORMAT="1"\nCACHE_META=')
rep('"$HASH_CACHE_NEW" "$CLASS_CACHE_NEW" "$PREHASH_RESULTS"', '"$HASH_CACHE_NEW" "$CLASS_CACHE_NEW" "$DISCOVERY_SNAPSHOT_NEW" "$DISCOVERY_CHANGED" "$PREHASH_RESULTS"')

anchor='file_signature() {\n  local p="$1" sig\n  sig="$(stat -c \'%s|%Y\' "$p" 2>/dev/null)"\n  [ -z "$sig" ] && sig="$(stat -f \'%z|%m\' "$p" 2>/dev/null)"\n  printf \'%s\' "$sig"\n}\n'
insert=anchor+r'''
# Conservative incremental discovery: the full tree is still walked every audit.
# Fast Audit compares cheap path+size+mtime state so later stages can distinguish
# unchanged files from additions/modifications/removals without trusting directory mtimes.
declare -A DISCOVERY_OLD_SIG DISCOVERY_CURRENT_PATH
DISCOVERY_UNCHANGED=0; DISCOVERY_CHANGED_COUNT=0; DISCOVERY_ADDED=0; DISCOVERY_REMOVED=0
load_discovery_snapshot() {
  local fmt="" p sig
  [ "$USE_HASH_CACHE" -eq 1 ] || return 0
  [ -s "$DISCOVERY_SNAPSHOT" ] || return 0
  while IFS=$'\t' read -r p sig; do
    if [ "$p" = "format" ]; then fmt="$sig"; continue; fi
    [ "$fmt" = "$DISCOVERY_FORMAT" ] || { DISCOVERY_OLD_SIG=(); return 0; }
    [ -n "$p" ] && DISCOVERY_OLD_SIG["$p"]="$sig"
  done < "$DISCOVERY_SNAPSHOT"
}
build_discovery_snapshot() {
  local p sig old
  printf 'format\t%s\n' "$DISCOVERY_FORMAT" > "$DISCOVERY_SNAPSHOT_NEW"
  : > "$DISCOVERY_CHANGED"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    sig="$(file_signature "$p")"
    printf '%s\t%s\n' "$p" "$sig" >> "$DISCOVERY_SNAPSHOT_NEW"
    DISCOVERY_CURRENT_PATH["$p"]=1
    old="${DISCOVERY_OLD_SIG[$p]:-}"
    if [ "$USE_HASH_CACHE" -eq 1 ] && [ -n "$old" ] && [ "$old" = "$sig" ]; then
      DISCOVERY_UNCHANGED=$((DISCOVERY_UNCHANGED+1))
    else
      printf '%s\n' "$p" >> "$DISCOVERY_CHANGED"
      DISCOVERY_CHANGED_COUNT=$((DISCOVERY_CHANGED_COUNT+1))
      [ -z "$old" ] && DISCOVERY_ADDED=$((DISCOVERY_ADDED+1))
    fi
  done < "$GAME_LIST"
  if [ "$USE_HASH_CACHE" -eq 1 ]; then
    for p in "${!DISCOVERY_OLD_SIG[@]}"; do
      [ -n "${DISCOVERY_CURRENT_PATH[$p]+x}" ] || DISCOVERY_REMOVED=$((DISCOVERY_REMOVED+1))
    done
  fi
}
'''
rep(anchor,insert)

old='GAME_SCAN_COUNT=$(wc -l < "$GAME_LIST" | tr -d "[:space:]"); echo "    Files discovered: $GAME_SCAN_COUNT"; DISCOVERY_END=$(date +%s); SAVE_START=$DISCOVERY_END'
new='GAME_SCAN_COUNT=$(wc -l < "$GAME_LIST" | tr -d "[:space:]"); load_discovery_snapshot; build_discovery_snapshot; echo "    Files discovered: $GAME_SCAN_COUNT"; if [ "$USE_HASH_CACHE" -eq 1 ]; then echo "    Unchanged: $DISCOVERY_UNCHANGED | Added: $DISCOVERY_ADDED | Changed: $((DISCOVERY_CHANGED_COUNT-DISCOVERY_ADDED)) | Removed: $DISCOVERY_REMOVED"; else echo "    Full Verification: incremental discovery state ignored"; fi; DISCOVERY_END=$(date +%s); SAVE_START=$DISCOVERY_END'
rep(old,new)

# Reuse the discovery signature instead of stat'ing every ROM again during classification.
rep('sig="$(file_signature "$p")"; class_key="$p|$sig"', 'sig=""; if [ -s "$DISCOVERY_SNAPSHOT_NEW" ]; then sig="${CLASS_DISCOVERY_SIG[$p]:-}"; fi; [ -n "$sig" ] || sig="$(file_signature "$p")"; class_key="$p|$sig"')
# Populate a path->signature map once from the new snapshot before classification.
rep('echo "[4/5] Classifying titles and collisions..."; : > "$PLAN";', 'declare -A CLASS_DISCOVERY_SIG; while IFS=$\'\\t\' read -r dp ds; do [ "$dp" = "format" ] && continue; [ -n "$dp" ] && CLASS_DISCOVERY_SIG["$dp"]="$ds"; done < "$DISCOVERY_SNAPSHOT_NEW"\necho "[4/5] Classifying titles and collisions..."; : > "$PLAN";')

# Publish snapshot only after reports have successfully reached the existing publish section.
# Insert immediately before the existing classification cache publication would be unsafe;
# discovery snapshot is derived and may be safely published after classification for Fast mode.
rep('if [ -s "$CLASS_CACHE_NEW" ]; then mv -f "$CLASS_CACHE_NEW" "$CLASS_CACHE"; fi\nCLASSIFY_END=', 'if [ -s "$CLASS_CACHE_NEW" ]; then mv -f "$CLASS_CACHE_NEW" "$CLASS_CACHE"; fi\nif [ -s "$DISCOVERY_SNAPSHOT_NEW" ]; then mv -f "$DISCOVERY_SNAPSHOT_NEW" "$DISCOVERY_SNAPSHOT"; fi\nCLASSIFY_END=')

assert 'Export_Game_Library_v1.3.sh' in s
assert 'FULL_VERIFY_WORKERS=2' in s
assert 'DISCOVERY_SNAPSHOT' in s
assert 'Full Verification: incremental discovery state ignored' in s
p.write_text(s)
