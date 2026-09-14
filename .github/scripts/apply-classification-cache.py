from pathlib import Path
p=Path('Export_Game_Library.sh')
s=p.read_text()
def rep(a,b):
    global s
    if a not in s: raise SystemExit('pattern missing: '+a[:140])
    s=s.replace(a,b,1)
rep('HASH_CACHE_NEW="$WORK.hashcache_new"\nCACHE_META="$AUDIT/hash_cache.meta"', 'HASH_CACHE_NEW="$WORK.hashcache_new"\nCLASS_CACHE="$AUDIT/classification_cache.tsv"\nCLASS_CACHE_NEW="$WORK.classification_cache_new"\nCACHE_META="$AUDIT/hash_cache.meta"')
rep('CACHE_FORMAT="5"\nAUDIT_SCHEMA_VERSION="4"', 'CACHE_FORMAT="5"\nCLASS_CACHE_FORMAT="1"\nAUDIT_SCHEMA_VERSION="4"')
rep('cleanup() { rm -f "$GAME_LIST" "$SAVE_LIST" "$SAVE_INDEX" "$PLAN" "$DAT_INDEX" "$HASH_ROWS" "$COLLISION_ROWS" "$HASH_CACHE_NEW" "$PREHASH_RESULTS"', 'cleanup() { rm -f "$GAME_LIST" "$SAVE_LIST" "$SAVE_INDEX" "$PLAN" "$DAT_INDEX" "$HASH_ROWS" "$COLLISION_ROWS" "$HASH_CACHE_NEW" "$CLASS_CACHE_NEW" "$PREHASH_RESULTS"')
anchor='''declare -A CACHE_SHA CACHE_NORMALIZED_SHA CACHE_DAT_STATUS CACHE_DAT_NAME CACHE_DAT_ROM CACHE_DAT_SOURCE
CACHE_ENTRIES_LOADED=0
cache_lookup() { local p="$1" sig="$2" k="$p|$sig"; printf '%s' "${CACHE_SHA[$k]:-}"; }
'''
replacement=anchor+'''declare -A CLASS_SYSTEM CLASS_FILE CLASS_EXT CLASS_STEM CLASS_CLEAN CLASS_REGION CLASS_KIND CLASS_PROPOSED
CLASS_CACHE_ENTRIES_LOADED=0; CLASS_CACHE_HITS=0; CLASS_CACHE_MISSES=0
load_classification_cache() {
  local fmt p sig system file ext stem clean region kind proposed k
  [ -s "$CLASS_CACHE" ] || return 0
  while IFS=$'\\t' read -r p sig system file ext stem clean region kind proposed; do
    if [ "$p" = "format" ]; then fmt="$sig"; continue; fi
    [ "$fmt" = "$CLASS_CACHE_FORMAT" ] || { CLASS_CACHE_ENTRIES_LOADED=0; return 0; }
    k="$p|$sig"; CLASS_SYSTEM["$k"]="$system"; CLASS_FILE["$k"]="$file"; CLASS_EXT["$k"]="$ext"; CLASS_STEM["$k"]="$stem"; CLASS_CLEAN["$k"]="$clean"; CLASS_REGION["$k"]="$region"; CLASS_KIND["$k"]="$kind"; CLASS_PROPOSED["$k"]="$proposed"; CLASS_CACHE_ENTRIES_LOADED=$((CLASS_CACHE_ENTRIES_LOADED+1))
  done < "$CLASS_CACHE"
}
'''
rep(anchor,replacement)
rep('echo "[3/5] Loading hash database..."; build_active_dat_systems; build_dat_index; echo "    Hash database source: $HASH_DB_SOURCE"; echo "    Hash records indexed: $HASH_INDEX_COUNT"; build_completion_reference; load_hash_cache;', 'echo "[3/5] Loading hash database..."; build_active_dat_systems; build_dat_index; echo "    Hash database source: $HASH_DB_SOURCE"; echo "    Hash records indexed: $HASH_INDEX_COUNT"; build_completion_reference; load_hash_cache; load_classification_cache;')
old='''echo "[4/5] Classifying titles and collisions..."; : > "$PLAN"; : > "$WORK.hashjobs"; declare -A NAME_COUNTS; SKIPPED=0; CLASSIFIED=0
while IFS= read -r p; do [ -z "$p" ] && continue; rel="${p#$GAMES/}"; system="${rel%%/*}"; [ "$system" = "$rel" ] && system="Unknown"; file="${p##*/}"; ext="${file##*.}"; stem="${file%.*}"; case "${ext,,}" in md|gen) system="MegaDrive" ;; 32x) system="S32X" ;; esac; if is_support_file "$p" "$file"; then SKIPPED=$((SKIPPED+1)); continue; fi; region="$(region_of "$stem")"; kind="$(kind_of "$stem")"; clean="$(clean_title "$stem")"; suffix="$(suffix_for "$region" "$kind")"; proposed="$clean$suffix.$ext"; key="${system,,}|${proposed,,}"; NAME_COUNTS["$key"]=$(( ${NAME_COUNTS["$key"]:-0} + 1 )); sig=""; if should_hash "$system" "$ext"; then sig="$(file_signature "$p")"; [ "$USE_HASH_CACHE" -eq 0 ] && printf '%s\\0' "$p" >> "$WORK.hashjobs"; fi; printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "$system" "$p" "$file" "$ext" "$stem" "$clean" "$region" "$kind" "$sig" >> "$PLAN"; CLASSIFIED=$((CLASSIFIED+1)); progress_check "Classifying titles" "$CLASSIFIED" "$GAME_SCAN_COUNT"; done < "$GAME_LIST"
'''
new='''echo "[4/5] Classifying titles and collisions..."; : > "$PLAN"; : > "$WORK.hashjobs"; declare -A NAME_COUNTS; SKIPPED=0; CLASSIFIED=0
printf 'format\\t%s\\n' "$CLASS_CACHE_FORMAT" > "$CLASS_CACHE_NEW"
while IFS= read -r p; do
  [ -z "$p" ] && continue
  rel="${p#$GAMES/}"; system="${rel%%/*}"; [ "$system" = "$rel" ] && system="Unknown"; file="${p##*/}"; ext="${file##*.}"; stem="${file%.*}"; case "${ext,,}" in md|gen) system="MegaDrive" ;; 32x) system="S32X" ;; esac
  if is_support_file "$p" "$file"; then SKIPPED=$((SKIPPED+1)); continue; fi
  sig="$(file_signature "$p")"; class_key="$p|$sig"
  if [ -n "${CLASS_CLEAN[$class_key]+x}" ]; then
    system="${CLASS_SYSTEM[$class_key]}"; file="${CLASS_FILE[$class_key]}"; ext="${CLASS_EXT[$class_key]}"; stem="${CLASS_STEM[$class_key]}"; clean="${CLASS_CLEAN[$class_key]}"; region="${CLASS_REGION[$class_key]}"; kind="${CLASS_KIND[$class_key]}"; proposed="${CLASS_PROPOSED[$class_key]}"; CLASS_CACHE_HITS=$((CLASS_CACHE_HITS+1))
  else
    region="$(region_of "$stem")"; kind="$(kind_of "$stem")"; clean="$(clean_title "$stem")"; suffix="$(suffix_for "$region" "$kind")"; proposed="$clean$suffix.$ext"; CLASS_CACHE_MISSES=$((CLASS_CACHE_MISSES+1))
  fi
  printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "$p" "$sig" "$system" "$file" "$ext" "$stem" "$clean" "$region" "$kind" "$proposed" >> "$CLASS_CACHE_NEW"
  key="${system,,}|${proposed,,}"; NAME_COUNTS["$key"]=$(( ${NAME_COUNTS["$key"]:-0} + 1 )); if should_hash "$system" "$ext"; then [ "$USE_HASH_CACHE" -eq 0 ] && printf '%s\\0' "$p" >> "$WORK.hashjobs"; fi
  printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "$system" "$p" "$file" "$ext" "$stem" "$clean" "$region" "$kind" "$sig" "$proposed" >> "$PLAN"; CLASSIFIED=$((CLASSIFIED+1)); progress_check "Classifying titles" "$CLASSIFIED" "$GAME_SCAN_COUNT"
done < "$GAME_LIST"
if [ -s "$CLASS_CACHE_NEW" ]; then mv -f "$CLASS_CACHE_NEW" "$CLASS_CACHE"; fi
'''
rep(old,new)
rep("while IFS=$'\\t' read -r -u 3 system p file ext stem clean region kind sig; do", "while IFS=$'\\t' read -r -u 3 system p file ext stem clean region kind sig fallback_proposed; do")
rep('suffix="$(suffix_for "$region" "$kind")"; base="$clean$suffix"; proposed="$base.$ext";', 'proposed="${fallback_proposed:-}"; if [ -z "$proposed" ]; then suffix="$(suffix_for "$region" "$kind")"; proposed="$clean$suffix.$ext"; fi; base="${proposed%.$ext}";')
rep('echo "Entries loaded: $CACHE_ENTRIES_LOADED"; echo "Entries reused: $HASH_REUSED";', 'echo "Entries loaded: $CACHE_ENTRIES_LOADED"; echo "Entries reused: $HASH_REUSED"; echo "Classification entries loaded: $CLASS_CACHE_ENTRIES_LOADED"; echo "Classification hits: $CLASS_CACHE_HITS"; echo "Classification misses/refreshed: $CLASS_CACHE_MISSES";')
assert 'Export_Game_Library_v1.3.sh' in s
assert 'FULL_VERIFY_WORKERS=2' in s
p.write_text(s)
