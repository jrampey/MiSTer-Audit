from pathlib import Path
p=Path('Export_Game_Library.sh')
s=p.read_text()

def rep(old,new):
    global s
    if old not in s:
        raise SystemExit('expected pattern not found:\n'+old[:200])
    s=s.replace(old,new,1)

rep('  [ -n "${DAT_NAME_BY_SHA[$raw]+x}" ] && { printf \'%s\' "$raw"; return; }', '  [ -n "${DAT_RECORD_BY_SHA[$raw]+x}" ] && { printf \'%s\' "$raw"; return; }')
rep('[ -n "${DAT_NAME_BY_SHA[${alt,,}]+x}" ] && { printf \'%s\' "${alt,,}"; return; }', '[ -n "${DAT_RECORD_BY_SHA[${alt,,}]+x}" ] && { printf \'%s\' "${alt,,}"; return; }')
rep('[ -n "${DAT_NAME_BY_SHA[${alt,,}]+x}" ] && { printf \'%s\' "${alt,,}"; return; }', '[ -n "${DAT_RECORD_BY_SHA[${alt,,}]+x}" ] && { printf \'%s\' "${alt,,}"; return; }')
old='''declare -A DAT_NAME_BY_SHA DAT_ROM_BY_SHA DAT_SOURCE_BY_SHA DAT_SYSTEM_BY_SHA DAT_CORE_BY_SHA DAT_FOLDER_BY_SHA DAT_REGION_BY_SHA DAT_RELEASE_BY_SHA DAT_LICENSE_BY_SHA
build_dat_index() {
  : > "$DAT_INDEX"; HASH_DB_SOURCE="None"; HASH_DB_FINGERPRINT="missing"; HASH_INDEX_COUNT=0
  if [ -f "$HASH_DB_TSV" ]; then
    echo "    Using bundled hash database: $HASH_DB_TSV"
    HASH_DB_SOURCE="mister_hash_database.tsv"; HASH_DB_FINGERPRINT="$(file_signature "$HASH_DB_TSV")"
    while IFS=$'\\t' read -r h title rom source size crc32 md5 meta_system meta_core meta_folder meta_region meta_release meta_license rest; do
      [ "$h" = "sha1" ] && continue; h="${h,,}"; [[ "$h" =~ ^[0-9a-f]{40}$ ]] || continue
      if [ -z "${DAT_NAME_BY_SHA[$h]+x}" ]; then
        DAT_NAME_BY_SHA["$h"]="$title"; DAT_ROM_BY_SHA["$h"]="$rom"; DAT_SOURCE_BY_SHA["$h"]="$source"
        DAT_SYSTEM_BY_SHA["$h"]="$meta_system"; DAT_CORE_BY_SHA["$h"]="$meta_core"; DAT_FOLDER_BY_SHA["$h"]="$meta_folder"
        DAT_REGION_BY_SHA["$h"]="$meta_region"; DAT_RELEASE_BY_SHA["$h"]="$meta_release"; DAT_LICENSE_BY_SHA["$h"]="$meta_license"
        HASH_INDEX_COUNT=$((HASH_INDEX_COUNT+1))
      fi
    done < "$HASH_DB_TSV"
  else
    echo "    WARNING: $HASH_DB_TSV was not found. Hashes will still be calculated, but canonical matching will be unavailable."
  fi
}

dat_lookup() { local h="${1,,}"; [ -n "${DAT_NAME_BY_SHA[$h]+x}" ] || return 0; printf '%s\\t%s\\t%s\\n' "$h" "${DAT_NAME_BY_SHA[$h]}" "${DAT_ROM_BY_SHA[$h]}" "${DAT_SOURCE_BY_SHA[$h]}"; }
'''
new='''declare -A ACTIVE_DAT_SYSTEMS DAT_RECORD_BY_SHA
DAT_SEP=$'\\x1f'
canonical_dat_system() {
  local s="${1,,}"
  case "$s" in
    nes|fds|famicom) printf 'NES' ;;
    snes|sfc|super\\ nintendo*|super\\ famicom*) printf 'SNES' ;;
    n64|nintendo64|nintendo\\ 64) printf 'N64' ;;
    gameboy|game\\ boy|gb) printf 'GAMEBOY' ;;
    gbc|gameboycolor|game\\ boy\\ color) printf 'GBC' ;;
    gba|gameboyadvance|game\\ boy\\ advance) printf 'GBA' ;;
    megadrive|mega\\ drive|genesis) printf 'Genesis' ;;
    s32x|32x) printf 'S32X' ;;
    sms|master\\ system*) printf 'SMS' ;;
    atari2600|atari\\ 2600) printf 'Atari2600' ;;
    intellivision) printf 'Intellivision' ;;
    tgfx16|turbografx16|turbografx\\ 16|pcengine|pc\\ engine) printf 'TGFX16' ;;
    amiga) printf 'Amiga' ;;
    c64|commodore64|commodore\\ 64) printf 'C64' ;;
    archie|archimedes) printf 'ARCHIE' ;;
    *) printf '%s' "$1" ;;
  esac
}
build_active_dat_systems() {
  local p rel system file ext canonical
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    rel="${p#$GAMES/}"; system="${rel%%/*}"; [ "$system" = "$rel" ] && system="Unknown"
    file="${p##*/}"; ext="${file##*.}"
    case "${ext,,}" in md|gen) system="MegaDrive" ;; 32x) system="S32X" ;; esac
    should_hash "$system" "$ext" || continue
    canonical="$(canonical_dat_system "$system")"
    [ -n "$canonical" ] && ACTIVE_DAT_SYSTEMS["${canonical,,}"]=1
  done < "$GAME_LIST"
}
dat_unpack() {
  local record="$1"
  IFS="$DAT_SEP" read -r DAT_TITLE DAT_ROM DAT_SOURCE DAT_SYSTEM DAT_CORE DAT_FOLDER DAT_REGION DAT_RELEASE DAT_LICENSE <<< "$record"
}
build_dat_index() {
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

dat_lookup() { local h="${1,,}"; [ -n "${DAT_RECORD_BY_SHA[$h]+x}" ] || return 0; dat_unpack "${DAT_RECORD_BY_SHA[$h]}"; printf '%s\\t%s\\t%s\\t%s\\n' "$h" "$DAT_TITLE" "$DAT_ROM" "$DAT_SOURCE"; }
'''
rep(old,new)
old='''build_completion_reference() {
  local h sys title region release license key
  for h in "${!DAT_NAME_BY_SHA[@]}"; do
    sys="${DAT_SYSTEM_BY_SHA[$h]:-}"; title="${DAT_NAME_BY_SHA[$h]:-}"; region="${DAT_REGION_BY_SHA[$h]:-}"; release="${DAT_RELEASE_BY_SHA[$h]:-}"; license="${DAT_LICENSE_BY_SHA[$h]:-}"
    [ -n "$sys" ] && [ -n "$title" ] || continue; completion_record_eligible "$region" "$release" "$license" || continue; key="$sys|$title"
    if [ -z "${COMPLETION_REFERENCE_KEYS[$key]+x}" ]; then COMPLETION_REFERENCE_KEYS["$key"]=1; COMPLETION_TOTAL_BY_SYSTEM["$sys"]=$(( ${COMPLETION_TOTAL_BY_SYSTEM["$sys"]:-0} + 1 )); COMPLETION_TITLE_REGION["$key"]="$region"; COMPLETION_TITLE_RELEASE["$key"]="$release"; COMPLETION_TITLE_LICENSE["$key"]="$license"; fi
  done
}'''
new='''build_completion_reference() {
  local h sys title region release license key
  for h in "${!DAT_RECORD_BY_SHA[@]}"; do
    dat_unpack "${DAT_RECORD_BY_SHA[$h]}"; sys="$DAT_SYSTEM"; title="$DAT_TITLE"; region="$DAT_REGION"; release="$DAT_RELEASE"; license="$DAT_LICENSE"
    [ -n "$sys" ] && [ -n "$title" ] || continue; completion_record_eligible "$region" "$release" "$license" || continue; key="$sys|$title"
    if [ -z "${COMPLETION_REFERENCE_KEYS[$key]+x}" ]; then COMPLETION_REFERENCE_KEYS["$key"]=1; COMPLETION_TOTAL_BY_SYSTEM["$sys"]=$(( ${COMPLETION_TOTAL_BY_SYSTEM["$sys"]:-0} + 1 )); COMPLETION_TITLE_REGION["$key"]="$region"; COMPLETION_TITLE_RELEASE["$key"]="$release"; COMPLETION_TITLE_LICENSE["$key"]="$license"; fi
  done
}'''
rep(old,new)
rep('echo "[3/5] Loading hash database..."; build_dat_index;', 'echo "[3/5] Loading hash database..."; build_active_dat_systems; build_dat_index;')
old='''    if [ -n "${DAT_NAME_BY_SHA[$hkey]+x}" ]; then
      dat_name="${DAT_NAME_BY_SHA[$hkey]}"; dat_rom="${DAT_ROM_BY_SHA[$hkey]}"; dat_source="${DAT_SOURCE_BY_SHA[$hkey]}"; meta_system="${DAT_SYSTEM_BY_SHA[$hkey]:-}"; meta_core="${DAT_CORE_BY_SHA[$hkey]:-}"; meta_folder="${DAT_FOLDER_BY_SHA[$hkey]:-}"; meta_region="${DAT_REGION_BY_SHA[$hkey]:-}"; meta_release="${DAT_RELEASE_BY_SHA[$hkey]:-}"; meta_license="${DAT_LICENSE_BY_SHA[$hkey]:-}"'''
new='''    if [ -n "${DAT_RECORD_BY_SHA[$hkey]+x}" ]; then
      dat_unpack "${DAT_RECORD_BY_SHA[$hkey]}"; dat_name="$DAT_TITLE"; dat_rom="$DAT_ROM"; dat_source="$DAT_SOURCE"; meta_system="$DAT_SYSTEM"; meta_core="$DAT_CORE"; meta_folder="$DAT_FOLDER"; meta_region="$DAT_REGION"; meta_release="$DAT_RELEASE"; meta_license="$DAT_LICENSE"'''
rep(old,new)
# Remaining report hot-path CSV loops: one assembled write per row.
old='''while IFS= read -r c_sys; do [ -n "$c_sys" ] || continue; c_total="${COMPLETION_TOTAL_BY_SYSTEM[$c_sys]:-0}"; c_owned="${COMPLETION_OWNED_BY_SYSTEM[$c_sys]:-0}"; c_missing=$((c_total-c_owned)); c_pct="$(awk -v a="$c_owned" -v b="$c_total" 'BEGIN{if(b>0) printf "%.2f", (a*100)/b; else printf "0.00"}')"; csv_escape "$c_sys" >> "$STAGE_COMPLETION"; printf ',' >> "$STAGE_COMPLETION"; csv_escape "$c_owned" >> "$STAGE_COMPLETION"; printf ',' >> "$STAGE_COMPLETION"; csv_escape "$c_total" >> "$STAGE_COMPLETION"; printf ',' >> "$STAGE_COMPLETION"; csv_escape "$c_missing" >> "$STAGE_COMPLETION"; printf ',' >> "$STAGE_COMPLETION"; csv_escape "$c_pct" >> "$STAGE_COMPLETION"; printf ',' >> "$STAGE_COMPLETION"; csv_escape "$COMPLETION_REGION_LABEL" >> "$STAGE_COMPLETION"; printf ',' >> "$STAGE_COMPLETION"; if [ "$COMPLETION_RETAIL_ONLY" -eq 1 ]; then csv_escape "Retail releases" >> "$STAGE_COMPLETION"; else csv_escape "All release types" >> "$STAGE_COMPLETION"; fi; printf '\\n' >> "$STAGE_COMPLETION"; done < <(printf '%s\\n' "${!COMPLETION_TOTAL_BY_SYSTEM[@]}" | LC_ALL=C sort)'''
new='''while IFS= read -r c_sys; do [ -n "$c_sys" ] || continue; c_total="${COMPLETION_TOTAL_BY_SYSTEM[$c_sys]:-0}"; c_owned="${COMPLETION_OWNED_BY_SYSTEM[$c_sys]:-0}"; c_missing=$((c_total-c_owned)); c_pct="$(awk -v a="$c_owned" -v b="$c_total" 'BEGIN{if(b>0) printf "%.2f", (a*100)/b; else printf "0.00"}')"; if [ "$COMPLETION_RETAIL_ONLY" -eq 1 ]; then c_scope="Retail releases"; else c_scope="All release types"; fi; csv_row "$STAGE_COMPLETION" "$c_sys" "$c_owned" "$c_total" "$c_missing" "$c_pct" "$COMPLETION_REGION_LABEL" "$c_scope"; done < <(printf '%s\\n' "${!COMPLETION_TOTAL_BY_SYSTEM[@]}" | LC_ALL=C sort)'''
rep(old,new)
old='''for c_key in "${!COMPLETION_REFERENCE_KEYS[@]}"; do [ -n "${COMPLETION_OWNED_KEYS[$c_key]+x}" ] && continue; c_sys="${c_key%%|*}"; c_title="${c_key#*|}"; csv_escape "$c_sys" >> "$STAGE_MISSING_COMPLETION"; printf ',' >> "$STAGE_MISSING_COMPLETION"; csv_escape "$c_title" >> "$STAGE_MISSING_COMPLETION"; printf ',' >> "$STAGE_MISSING_COMPLETION"; csv_escape "${COMPLETION_TITLE_REGION[$c_key]:-}" >> "$STAGE_MISSING_COMPLETION"; printf ',' >> "$STAGE_MISSING_COMPLETION"; csv_escape "${COMPLETION_TITLE_RELEASE[$c_key]:-}" >> "$STAGE_MISSING_COMPLETION"; printf ',' >> "$STAGE_MISSING_COMPLETION"; csv_escape "${COMPLETION_TITLE_LICENSE[$c_key]:-}" >> "$STAGE_MISSING_COMPLETION"; printf '\\n' >> "$STAGE_MISSING_COMPLETION"; done'''
new='''for c_key in "${!COMPLETION_REFERENCE_KEYS[@]}"; do [ -n "${COMPLETION_OWNED_KEYS[$c_key]+x}" ] && continue; c_sys="${c_key%%|*}"; c_title="${c_key#*|}"; csv_row "$STAGE_MISSING_COMPLETION" "$c_sys" "$c_title" "${COMPLETION_TITLE_REGION[$c_key]:-}" "${COMPLETION_TITLE_RELEASE[$c_key]:-}" "${COMPLETION_TITLE_LICENSE[$c_key]:-}"; done'''
rep(old,new)
# Make filtering visible in audit telemetry.
rep('echo "Hash records indexed: $HASH_INDEX_COUNT";', 'echo "Hash records indexed: $HASH_INDEX_COUNT"; echo "Hash records skipped for absent systems: ${HASH_DB_SKIPPED_SYSTEM_RECORDS:-0}";')
# Ensure old nine-array references are completely gone.
for token in ('DAT_NAME_BY_SHA','DAT_ROM_BY_SHA','DAT_SOURCE_BY_SHA','DAT_SYSTEM_BY_SHA','DAT_CORE_BY_SHA','DAT_FOLDER_BY_SHA','DAT_REGION_BY_SHA','DAT_RELEASE_BY_SHA','DAT_LICENSE_BY_SHA'):
    if token in s:
        raise SystemExit('legacy DAT array reference remains: '+token)
p.write_text(s)
