from pathlib import Path

p = Path("Export_Game_Library.sh")
s = p.read_text()

def rep(old, new, label):
    global s
    if old not in s:
        raise SystemExit(f"Patch anchor not found: {label}")
    s = s.replace(old, new, 1)

rep('FULL_VERIFY_WORKERS=2\nPREHASH_RESULTS="$WORK.prehash_results"', '''FULL_VERIFY_WORKERS=2

# ---------------------------------------------------------------------------
# LIBRARY COMPLETION REGIONS
# ---------------------------------------------------------------------------
# Uncomment the regions you want included in library-completion reporting.
# Default: U.S. retail releases only. World releases count toward USA, Europe,
# and Japan because No-Intro uses World for releases spanning all three major
# territories.
COMPLETION_REGIONS=(
  "USA"
  # "Europe"
  # "Japan"
  # "Canada"
  # "Australia"
  # "Korea"
  # "Brazil"
)
COMPLETION_RETAIL_ONLY=1
COMPLETION_INCLUDE_WORLD=1

PREHASH_RESULTS="$WORK.prehash_results"''', 'completion config')

rep('STAGE_LOCATION_AUDIT="$STAGE_DIR/location_audit.csv"\nSTAGE_BUNDLE="$STAGE_DIR/MiSTer_Library_Audit.txt"', '''STAGE_LOCATION_AUDIT="$STAGE_DIR/location_audit.csv"
STAGE_COMPLETION="$STAGE_DIR/library_completion.csv"
STAGE_MISSING_COMPLETION="$STAGE_DIR/missing_library_titles.csv"
STAGE_BUNDLE="$STAGE_DIR/MiSTer_Library_Audit.txt"''', 'stage paths')

rep('''dat_lookup() {
  local h="${1,,}"
  [ -n "${DAT_NAME_BY_SHA[$h]+x}" ] || return 0
  printf '%s\\t%s\\t%s\\n' "$h" "${DAT_NAME_BY_SHA[$h]}" "${DAT_ROM_BY_SHA[$h]}" "${DAT_SOURCE_BY_SHA[$h]}"
}

load_hash_cache() {''', '''dat_lookup() {
  local h="${1,,}"
  [ -n "${DAT_NAME_BY_SHA[$h]+x}" ] || return 0
  printf '%s\\t%s\\t%s\\n' "$h" "${DAT_NAME_BY_SHA[$h]}" "${DAT_ROM_BY_SHA[$h]}" "${DAT_SOURCE_BY_SHA[$h]}"
}

# Completion is title-based, so revisions, alternate dumps, and duplicate
# hashes do not inflate the percentage.
declare -A COMPLETION_REFERENCE_KEYS COMPLETION_OWNED_KEYS
declare -A COMPLETION_TOTAL_BY_SYSTEM COMPLETION_OWNED_BY_SYSTEM
declare -A COMPLETION_TITLE_REGION COMPLETION_TITLE_RELEASE COMPLETION_TITLE_LICENSE

completion_region_selected() {
  local meta="${1,,}" selected normalized
  normalized="${meta// /}"
  for selected in "${COMPLETION_REGIONS[@]}"; do
    selected="${selected,,}"; selected="${selected// /}"
    case ",$normalized," in *",$selected,"*) return 0 ;; esac
    if [ "$COMPLETION_INCLUDE_WORLD" -eq 1 ] && [ "$normalized" = "world" ]; then
      case "$selected" in usa|europe|japan) return 0 ;; esac
    fi
  done
  return 1
}

completion_release_selected() {
  local release="${1,,}" license="${2,,}"
  if [ "$COMPLETION_RETAIL_ONLY" -eq 1 ]; then
    case "$release" in retail/standard|retail|standard) ;; *) return 1 ;; esac
    case "$license" in *unlicensed*|unl|*homebrew*|*aftermarket*) return 1 ;; esac
  fi
  return 0
}

completion_record_eligible() {
  completion_region_selected "$1" && completion_release_selected "$2" "$3"
}

build_completion_reference() {
  local h sys title region release license key
  for h in "${!DAT_NAME_BY_SHA[@]}"; do
    sys="${DAT_SYSTEM_BY_SHA[$h]:-}"; title="${DAT_NAME_BY_SHA[$h]:-}"
    region="${DAT_REGION_BY_SHA[$h]:-}"; release="${DAT_RELEASE_BY_SHA[$h]:-}"; license="${DAT_LICENSE_BY_SHA[$h]:-}"
    [ -n "$sys" ] && [ -n "$title" ] || continue
    completion_record_eligible "$region" "$release" "$license" || continue
    key="$sys|$title"
    if [ -z "${COMPLETION_REFERENCE_KEYS[$key]+x}" ]; then
      COMPLETION_REFERENCE_KEYS["$key"]=1
      COMPLETION_TOTAL_BY_SYSTEM["$sys"]=$(( ${COMPLETION_TOTAL_BY_SYSTEM["$sys"]:-0} + 1 ))
      COMPLETION_TITLE_REGION["$key"]="$region"; COMPLETION_TITLE_RELEASE["$key"]="$release"; COMPLETION_TITLE_LICENSE["$key"]="$license"
    fi
  done
}

record_completion_owned() {
  local sys="$1" title="$2" region="$3" release="$4" license="$5" key
  [ -n "$sys" ] && [ -n "$title" ] || return 0
  completion_record_eligible "$region" "$release" "$license" || return 0
  key="$sys|$title"
  [ -n "${COMPLETION_REFERENCE_KEYS[$key]+x}" ] || return 0
  if [ -z "${COMPLETION_OWNED_KEYS[$key]+x}" ]; then
    COMPLETION_OWNED_KEYS["$key"]=1
    COMPLETION_OWNED_BY_SYSTEM["$sys"]=$(( ${COMPLETION_OWNED_BY_SYSTEM["$sys"]:-0} + 1 ))
  fi
}

load_hash_cache() {''', 'completion functions')

rep('''build_dat_index
echo "    Hash database source: $HASH_DB_SOURCE"
echo "    Hash records indexed: $HASH_INDEX_COUNT"
load_hash_cache''', '''build_dat_index
echo "    Hash database source: $HASH_DB_SOURCE"
echo "    Hash records indexed: $HASH_INDEX_COUNT"
build_completion_reference
load_hash_cache''', 'reference build')

rep('''      loc_status="$(location_status "$system" "$meta_folder")"
      [ "$dat_status" = "Normalized SHA-1" ] || dat_status="Exact SHA-1"; DAT_MATCHED=$((DAT_MATCHED+1)); SYSTEM_MATCHED["$system"]=$(( ${SYSTEM_MATCHED["$system"]:-0} + 1 ))''', '''      loc_status="$(location_status "$system" "$meta_folder")"
      record_completion_owned "${meta_system:-$system}" "$dat_name" "$meta_region" "$meta_release" "$meta_license"
      [ "$dat_status" = "Normalized SHA-1" ] || dat_status="Exact SHA-1"; DAT_MATCHED=$((DAT_MATCHED+1)); SYSTEM_MATCHED["$system"]=$(( ${SYSTEM_MATCHED["$system"]:-0} + 1 ))''', 'owned recording')

rep('''CACHE_REFRESHED=$HASH_CALCULATED
CACHE_NOT_REUSED=$(( CACHE_ENTRIES_LOADED > HASH_REUSED ? CACHE_ENTRIES_LOADED - HASH_REUSED : 0 ))''', '''# Build title-level regional completion reports.
COMPLETION_REGION_LABEL="$(IFS=', '; echo "${COMPLETION_REGIONS[*]}")"
printf '%s\\n' '"system","owned_titles","reference_titles","missing_titles","completion_percent","regions","scope"' > "$STAGE_COMPLETION"
printf '%s\\n' '"system","canonical_title","region","release_type","license_status"' > "$STAGE_MISSING_COMPLETION"
while IFS= read -r c_sys; do
  [ -n "$c_sys" ] || continue
  c_total="${COMPLETION_TOTAL_BY_SYSTEM[$c_sys]:-0}"; c_owned="${COMPLETION_OWNED_BY_SYSTEM[$c_sys]:-0}"; c_missing=$((c_total-c_owned))
  c_pct="$(awk -v a="$c_owned" -v b="$c_total" 'BEGIN{if(b>0) printf "%.2f", (a*100)/b; else printf "0.00"}')"
  csv_escape "$c_sys" >> "$STAGE_COMPLETION"; printf ',' >> "$STAGE_COMPLETION"; csv_escape "$c_owned" >> "$STAGE_COMPLETION"; printf ',' >> "$STAGE_COMPLETION"
  csv_escape "$c_total" >> "$STAGE_COMPLETION"; printf ',' >> "$STAGE_COMPLETION"; csv_escape "$c_missing" >> "$STAGE_COMPLETION"; printf ',' >> "$STAGE_COMPLETION"
  csv_escape "$c_pct" >> "$STAGE_COMPLETION"; printf ',' >> "$STAGE_COMPLETION"; csv_escape "$COMPLETION_REGION_LABEL" >> "$STAGE_COMPLETION"; printf ',' >> "$STAGE_COMPLETION"
  if [ "$COMPLETION_RETAIL_ONLY" -eq 1 ]; then csv_escape "Retail releases" >> "$STAGE_COMPLETION"; else csv_escape "All release types" >> "$STAGE_COMPLETION"; fi; printf '\\n' >> "$STAGE_COMPLETION"
done < <(printf '%s\\n' "${!COMPLETION_TOTAL_BY_SYSTEM[@]}" | LC_ALL=C sort)

for c_key in "${!COMPLETION_REFERENCE_KEYS[@]}"; do
  [ -n "${COMPLETION_OWNED_KEYS[$c_key]+x}" ] && continue
  c_sys="${c_key%%|*}"; c_title="${c_key#*|}"
  csv_escape "$c_sys" >> "$STAGE_MISSING_COMPLETION"; printf ',' >> "$STAGE_MISSING_COMPLETION"; csv_escape "$c_title" >> "$STAGE_MISSING_COMPLETION"; printf ',' >> "$STAGE_MISSING_COMPLETION"
  csv_escape "${COMPLETION_TITLE_REGION[$c_key]:-}" >> "$STAGE_MISSING_COMPLETION"; printf ',' >> "$STAGE_MISSING_COMPLETION"; csv_escape "${COMPLETION_TITLE_RELEASE[$c_key]:-}" >> "$STAGE_MISSING_COMPLETION"; printf ',' >> "$STAGE_MISSING_COMPLETION"
  csv_escape "${COMPLETION_TITLE_LICENSE[$c_key]:-}" >> "$STAGE_MISSING_COMPLETION"; printf '\\n' >> "$STAGE_MISSING_COMPLETION"
done
{ head -n 1 "$STAGE_MISSING_COMPLETION"; tail -n +2 "$STAGE_MISSING_COMPLETION" | LC_ALL=C sort; } > "$STAGE_MISSING_COMPLETION.tmp" && mv -f "$STAGE_MISSING_COMPLETION.tmp" "$STAGE_MISSING_COMPLETION"

CACHE_REFRESHED=$HASH_CALCULATED
CACHE_NOT_REUSED=$(( CACHE_ENTRIES_LOADED > HASH_REUSED ? CACHE_ENTRIES_LOADED - HASH_REUSED : 0 ))''', 'completion reports')

rep('''  echo "[CACHE HEALTH]"''', '''  echo "[LIBRARY COMPLETION]"
  echo "Regions: $COMPLETION_REGION_LABEL"
  if [ "$COMPLETION_RETAIL_ONLY" -eq 1 ]; then echo "Scope: Retail releases only"; else echo "Scope: All release types"; fi
  echo "World releases count toward USA, Europe, and Japan when COMPLETION_INCLUDE_WORLD=1."
  tail -n +2 "$STAGE_COMPLETION" | while IFS=',' read -r c_sys c_owned c_total c_missing c_pct rest; do
    c_sys="${c_sys#\\\"}"; c_sys="${c_sys%\\\"}"; c_owned="${c_owned#\\\"}"; c_owned="${c_owned%\\\"}"; c_total="${c_total#\\\"}"; c_total="${c_total%\\\"}"; c_missing="${c_missing#\\\"}"; c_missing="${c_missing%\\\"}"; c_pct="${c_pct#\\\"}"; c_pct="${c_pct%\\\"}"
    echo "$c_sys | owned=$c_owned | reference=$c_total | missing=$c_missing | completion=$c_pct%"
  done
  echo "Missing-title detail: missing_library_titles.csv"
  echo
  echo "[CACHE HEALTH]"''', 'bundle completion')

rep('for report in game_library.txt library_catalog.csv dat_matches.csv unmatched_hashes.csv hash_duplicates.csv location_audit.csv proposed_renames.csv proposed_save_renames.csv; do', 'for report in game_library.txt library_catalog.csv dat_matches.csv unmatched_hashes.csv hash_duplicates.csv location_audit.csv library_completion.csv missing_library_titles.csv proposed_renames.csv proposed_save_renames.csv; do', 'bundle reports')
rep('for report in game_library.txt library_catalog.csv proposed_renames.csv proposed_save_renames.csv hash_duplicates.csv dat_matches.csv unmatched_hashes.csv location_audit.csv MiSTer_Library_Audit.txt; do', 'for report in game_library.txt library_catalog.csv proposed_renames.csv proposed_save_renames.csv hash_duplicates.csv dat_matches.csv unmatched_hashes.csv location_audit.csv library_completion.csv missing_library_titles.csv MiSTer_Library_Audit.txt; do', 'publish reports')

# Keep current-version display/cache references synchronized without changing
# legitimate historical comments about when old behavior was removed.
s = s.replace('MiSTer Game Library v1.2', 'MiSTer Game Library v1.3')
s = s.replace('echo "EXPORTER_VERSION=1.2"', 'echo "EXPORTER_VERSION=1.3"')
s = s.replace('MiSTer Game Library Audit Bundle v1.2', 'MiSTer Game Library Audit Bundle v1.3')
s = s.replace(' MiSTer LIBRARY EXPORT v1.2 COMPLETE', ' MiSTer LIBRARY EXPORT v1.3 COMPLETE')

s = s.replace('  unmatched_hashes.csv\n  MiSTer_Library_Audit.txt  (single file to upload for review)', '  unmatched_hashes.csv\n  library_completion.csv\n  missing_library_titles.csv\n  MiSTer_Library_Audit.txt  (single file to upload for review)', 1)
s = s.replace('echo "  unmatched_hashes.csv"\necho "  MiSTer_Library_Audit.txt  <-- upload this one for review"', 'echo "  unmatched_hashes.csv"\necho "  library_completion.csv"\necho "  missing_library_titles.csv"\necho "  MiSTer_Library_Audit.txt  <-- upload this one for review"', 1)

p.write_text(s)
