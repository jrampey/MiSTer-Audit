from pathlib import Path
p=Path('Export_Game_Library.sh')
s=p.read_text()
def rep(a,b):
 global s
 if a not in s: raise SystemExit('pattern missing: '+a[:120])
 s=s.replace(a,b,1)
rep('CACHE_META="$AUDIT/hash_cache.meta"\nCACHE_FORMAT="5"', 'CACHE_META="$AUDIT/hash_cache.meta"\nDAT_CACHE_DIR="$AUDIT/dat_cache"\nDAT_CACHE_META="$DAT_CACHE_DIR/.database_signature"\nCACHE_FORMAT="5"')
old='''build_dat_index() {
  : > "$DAT_INDEX"; HASH_DB_SOURCE="None"; HASH_DB_FINGERPRINT="missing"; HASH_INDEX_COUNT=0; HASH_DB_SKIPPED_SYSTEM_RECORDS=0
  if [ -f "$HASH_DB_TSV" ]; then
    echo "    Using bundled hash database: $HASH_DB_TSV"
    HASH_DB_SOURCE="mister_hash_database.tsv"; HASH_DB_FINGERPRINT="$(file_signature "$HASH_DB_TSV")"
    while IFS=$'\\t' read -r h title rom source size crc32 md5 meta_system meta_core meta_folder meta_region meta_release meta_license rest; do
      [ "$h" = "sha1" ] && continue; h="${h,,}"; [[ "$h" =~ ^[0-9a-f]{40}$ ]] || continue
      if [ -z "${ACTIVE_DAT_SYSTEMS[${meta_system,,}]+x}" ]; then HASH_DB_SKIPPED_SYSTEM_RECORDS=$((HASH_DB_SKIPPED_SYSTEM_RECORDS+1)); continue; fi
      if [ -z "${DAT_RECORD_BY_SHA[$h]+x}" ]; then
        DAT_RECORD_BY_SHA["$h"]="$title$DAT_SEP$rom$DAT_SEP$source$DAT_SEP$meta_system$DAT_SEP$meta_core$DAT_SEP$meta_folder$DAT_SEP$meta_region$DAT_SEP$meta_release$DAT_SEP$meta_license"
        HASH_INDEX_COUNT=$((HASH_INDEX_COUNT+1))
      fi
    done < "$HASH_DB_TSV"
  else
    echo "    WARNING: $HASH_DB_TSV was not found. Hashes will still be calculated, but canonical matching will be unavailable."
  fi
}
'''
new='''dat_cache_file() {
  local sys="$1" safe
  safe="${sys//[^A-Za-z0-9._-]/_}"
  printf '%s/%s.tsv' "$DAT_CACHE_DIR" "$safe"
}
rebuild_dat_cache() {
  local tmp="$DAT_CACHE_DIR/.build.$$" h title rom source size crc32 md5 meta_system meta_core meta_folder meta_region meta_release meta_license rest out
  rm -rf "$tmp"; mkdir -p "$tmp" || return 1
  while IFS=$'\\t' read -r h title rom source size crc32 md5 meta_system meta_core meta_folder meta_region meta_release meta_license rest; do
    [ "$h" = "sha1" ] && continue; h="${h,,}"; [[ "$h" =~ ^[0-9a-f]{40}$ ]] || continue; [ -n "$meta_system" ] || continue
    out="$tmp/${meta_system//[^A-Za-z0-9._-]/_}.tsv"
    printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "$h" "$title" "$rom" "$source" "$meta_system" "$meta_core" "$meta_folder" "$meta_region" "$meta_release" "$meta_license" >> "$out"
  done < "$HASH_DB_TSV"
  find "$DAT_CACHE_DIR" -maxdepth 1 -type f -name '*.tsv' -delete 2>/dev/null || true
  for out in "$tmp"/*.tsv; do [ -f "$out" ] || continue; mv "$out" "$DAT_CACHE_DIR/" || { rm -rf "$tmp"; return 1; }; done
  rm -rf "$tmp"
  printf '%s\\n' "$HASH_DB_FINGERPRINT" > "$DAT_CACHE_META"
}
load_dat_cache_file() {
  local f="$1" h title rom source meta_system meta_core meta_folder meta_region meta_release meta_license
  [ -f "$f" ] || return 0
  while IFS=$'\\t' read -r h title rom source meta_system meta_core meta_folder meta_region meta_release meta_license rest; do
    [[ "$h" =~ ^[0-9a-f]{40}$ ]] || continue
    if [ -z "${DAT_RECORD_BY_SHA[$h]+x}" ]; then DAT_RECORD_BY_SHA["$h"]="$title$DAT_SEP$rom$DAT_SEP$source$DAT_SEP$meta_system$DAT_SEP$meta_core$DAT_SEP$meta_folder$DAT_SEP$meta_region$DAT_SEP$meta_release$DAT_SEP$meta_license"; HASH_INDEX_COUNT=$((HASH_INDEX_COUNT+1)); fi
  done < "$f"
}
build_dat_index() {
  : > "$DAT_INDEX"; HASH_DB_SOURCE="None"; HASH_DB_FINGERPRINT="missing"; HASH_INDEX_COUNT=0; HASH_DB_SKIPPED_SYSTEM_RECORDS=0; DAT_CACHE_STATUS="Unavailable"
  if [ -f "$HASH_DB_TSV" ]; then
    echo "    Using bundled hash database: $HASH_DB_TSV"
    HASH_DB_SOURCE="mister_hash_database.tsv"; HASH_DB_FINGERPRINT="$(file_signature "$HASH_DB_TSV")"
    mkdir -p "$DAT_CACHE_DIR" || true
    local cached_sig="" sys cache_file
    [ -f "$DAT_CACHE_META" ] && IFS= read -r cached_sig < "$DAT_CACHE_META"
    if [ "$cached_sig" != "$HASH_DB_FINGERPRINT" ]; then
      echo "    Rebuilding persistent per-system DAT index..."
      if rebuild_dat_cache; then DAT_CACHE_STATUS="Rebuilt"; else DAT_CACHE_STATUS="Fallback"; fi
    else DAT_CACHE_STATUS="Hit"; fi
    if [ "$DAT_CACHE_STATUS" != "Fallback" ]; then
      for sys in "${!ACTIVE_DAT_SYSTEMS[@]}"; do
        cache_file="$(dat_cache_file "$sys")"; load_dat_cache_file "$cache_file"
      done
    else
      while IFS=$'\\t' read -r h title rom source size crc32 md5 meta_system meta_core meta_folder meta_region meta_release meta_license rest; do
        [ "$h" = "sha1" ] && continue; h="${h,,}"; [[ "$h" =~ ^[0-9a-f]{40}$ ]] || continue
        [ -n "${ACTIVE_DAT_SYSTEMS[${meta_system,,}]+x}" ] || { HASH_DB_SKIPPED_SYSTEM_RECORDS=$((HASH_DB_SKIPPED_SYSTEM_RECORDS+1)); continue; }
        [ -n "${DAT_RECORD_BY_SHA[$h]+x}" ] || { DAT_RECORD_BY_SHA["$h"]="$title$DAT_SEP$rom$DAT_SEP$source$DAT_SEP$meta_system$DAT_SEP$meta_core$DAT_SEP$meta_folder$DAT_SEP$meta_region$DAT_SEP$meta_release$DAT_SEP$meta_license"; HASH_INDEX_COUNT=$((HASH_INDEX_COUNT+1)); }
      done < "$HASH_DB_TSV"
    fi
  else
    echo "    WARNING: $HASH_DB_TSV was not found. Hashes will still be calculated, but canonical matching will be unavailable."
  fi
}
'''
rep(old,new)
rep('echo "Hash records indexed: $HASH_INDEX_COUNT"; echo "Hash records skipped for absent systems: ${HASH_DB_SKIPPED_SYSTEM_RECORDS:-0}";', 'echo "Hash records indexed: $HASH_INDEX_COUNT"; echo "Persistent DAT index: ${DAT_CACHE_STATUS:-Unavailable}"; echo "Hash records skipped for absent systems: ${HASH_DB_SKIPPED_SYSTEM_RECORDS:-0}";')
# Preserve release and worker setting.
assert 'Export_Game_Library_v1.3.sh' in s
assert 'FULL_VERIFY_WORKERS=2' in s
p.write_text(s)
