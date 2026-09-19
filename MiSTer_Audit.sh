#!/bin/bash
# MiSTer_Audit.sh v1.4
# Unified MiSTer ROM Library Auditor: read-only audit plus guarded Preview / Apply / Rollback tools.
# The audit path remains read-only. Library mutation is available only through the explicit Update / Rename menu.

run_audit() {
# Audit engine (v1.4)
# MiSTer library audit/export. READ ONLY: never renames, moves, or deletes games/saves.
# v1.2 improves region/version parsing, BIOS/support filtering, title normalization,
# collision-safe proposals, ROM hashing, bundled TSV hash matching, full-library incremental caching, in-memory indexes, atomic report publishing, timing telemetry, and Fast/Full Verification audit modes.

ROOT="/media/fat"
GAMES="$ROOT/games"
SAVES="$ROOT/saves"
AUDIT="$ROOT/GameLibraryAudit"
OUT="$AUDIT/game_library.txt"
CSV="$AUDIT/library_catalog.csv"
REN="$AUDIT/proposed_renames.csv"
SAVE_REN="$AUDIT/proposed_save_renames.csv"
HASH_DUP="$AUDIT/hash_duplicates.csv"
DAT_MATCH="$AUDIT/dat_matches.csv"
DAT_UNMATCHED="$AUDIT/unmatched_hashes.csv"
LOCATION_AUDIT="$AUDIT/location_audit.csv"
BUNDLE="$AUDIT/MiSTer_Library_Audit.txt"
HASH_DB_SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
HASH_DB_TSV="$HASH_DB_SCRIPT_DIR/mister_hash_database.tsv"
WORK="/tmp/mister_library_v11.$$"
GAME_LIST="$WORK.games"
SAVE_LIST="$WORK.saves"
SAVE_INDEX="$WORK.saveindex"
PLAN="$WORK.plan"
DAT_INDEX="$WORK.datindex"
HASH_ROWS="$WORK.hashrows"
COLLISION_ROWS="$WORK.collisionrows"
HASH_CACHE="$AUDIT/hash_cache.tsv"
HASH_CACHE_NEW="$WORK.hashcache_new"
CLASS_CACHE="$AUDIT/classification_cache.tsv"
CLASS_CACHE_NEW="$WORK.classification_cache_new"
DISCOVERY_SNAPSHOT="$AUDIT/discovery_snapshot.tsv"
DISCOVERY_SNAPSHOT_NEW="$WORK.discovery_snapshot_new"
DISCOVERY_CHANGED="$WORK.discovery_changed"
DISCOVERY_FORMAT="1"
CACHE_META="$AUDIT/hash_cache.meta"
DAT_CACHE_DIR="$AUDIT/dat_cache"
DAT_CACHE_META="$DAT_CACHE_DIR/.database_signature"
CACHE_FORMAT="7"
CLASS_CACHE_FORMAT="1"
AUDIT_SCHEMA_VERSION="4"
FULL_VERIFY_WORKERS=2

# ---------------------------------------------------------------------------
# AUDIT POLICY
# ---------------------------------------------------------------------------
# Defaults intentionally preserve v1.4 behavior. AUDIT_POLICY.conf is optional;
# if absent or invalid, these defaults remain in effect. The policy parser does
# not source/execute the file.
AUDIT_POLICY_FILE="$HASH_DB_SCRIPT_DIR/AUDIT_POLICY.conf"
COMPLETION_REGIONS=("USA")
COMPLETION_RETAIL_ONLY=1
COMPLETION_INCLUDE_WORLD=1
COMPLETION_INCLUDE_PROTOTYPES=0
COMPLETION_INCLUDE_BETA=0
COMPLETION_INCLUDE_DEMOS=0

trim_policy_value() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  printf '%s' "$v"
}

load_audit_policy() {
  local line key value region rest
  local -a parsed_regions=()
  [ -r "$AUDIT_POLICY_FILE" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(trim_policy_value "$line")"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    case "$line" in *=*) ;; *) continue ;; esac
    key="$(trim_policy_value "${line%%=*}")"
    value="$(trim_policy_value "${line#*=}")"
    case "$key" in
      COMPLETION_REGIONS)
        parsed_regions=()
        rest="$value"
        while :; do
          case "$rest" in
            *,*) region="${rest%%,*}"; rest="${rest#*,}" ;;
            *) region="$rest"; rest="" ;;
          esac
          region="$(trim_policy_value "$region")"
          [ -n "$region" ] && parsed_regions+=("$region")
          [ -n "$rest" ] || break
        done
        [ "${#parsed_regions[@]}" -gt 0 ] && COMPLETION_REGIONS=("${parsed_regions[@]}")
        ;;
      COMPLETION_RETAIL_ONLY|COMPLETION_INCLUDE_WORLD|COMPLETION_INCLUDE_PROTOTYPES|COMPLETION_INCLUDE_BETA|COMPLETION_INCLUDE_DEMOS)
        case "$value" in
          0|1) printf -v "$key" '%s' "$value" ;;
        esac
        ;;
    esac
  done < "$AUDIT_POLICY_FILE"
}

load_audit_policy

PREHASH_RESULTS="$WORK.prehash_results"
STAGE_DIR="$AUDIT/.staging.$$"
STAGE_OUT="$STAGE_DIR/game_library.txt"
STAGE_CSV="$STAGE_DIR/library_catalog.csv"
STAGE_REN="$STAGE_DIR/proposed_renames.csv"
STAGE_SAVE_REN="$STAGE_DIR/proposed_save_renames.csv"
STAGE_HASH_DUP="$STAGE_DIR/hash_duplicates.csv"
STAGE_DAT_MATCH="$STAGE_DIR/dat_matches.csv"
STAGE_DAT_UNMATCHED="$STAGE_DIR/unmatched_hashes.csv"
STAGE_LOCATION_AUDIT="$STAGE_DIR/location_audit.csv"
STAGE_COMPLETION="$STAGE_DIR/library_completion.csv"
STAGE_MISSING_COMPLETION="$STAGE_DIR/missing_library_titles.csv"
STAGE_BUNDLE="$STAGE_DIR/MiSTer_Library_Audit.txt"

cleanup() { rm -f "$GAME_LIST" "$SAVE_LIST" "$SAVE_INDEX" "$PLAN" "$DAT_INDEX" "$HASH_ROWS" "$COLLISION_ROWS" "$HASH_CACHE_NEW" "$CLASS_CACHE_NEW" "$DISCOVERY_SNAPSHOT_NEW" "$DISCOVERY_CHANGED" "$PREHASH_RESULTS" "$WORK.duphashes" "$WORK.hashjobs"; rm -rf "$STAGE_DIR"; }

if [ ! -d "$GAMES" ]; then
  echo "ERROR: $GAMES was not found."
  read -p "Press Enter to exit..."
  exit 1
fi
mkdir -p "$AUDIT" || exit 1
mkdir -p "$STAGE_DIR" || exit 1

hash_file() {
  local p="$1"
  if command -v sha1sum >/dev/null 2>&1; then
    set -- $(sha1sum "$p" 2>/dev/null); printf '%s' "$1"
  elif command -v openssl >/dev/null 2>&1; then
    set -- $(openssl sha1 "$p" 2>/dev/null); eval 'printf %s \"\${'$'#}\"'
  else
    printf 'UNAVAILABLE'
  fi
}

hash_stream_skip() {
  local p="$1" block="$2"
  if command -v sha1sum >/dev/null 2>&1; then
    local digest rest; read -r digest rest < <(dd if="$p" bs="$block" skip=1 2>/dev/null | sha1sum 2>/dev/null); printf '%s' "$digest"
  elif command -v openssl >/dev/null 2>&1; then
    local line digest; IFS= read -r line < <(dd if="$p" bs="$block" skip=1 2>/dev/null | openssl sha1 2>/dev/null); digest="${line##* }"; printf '%s' "$digest"
  else
    printf 'UNAVAILABLE'
  fi
}

normalized_dat_hash() {
  local p="$1" ext="${2,,}" raw="${3,,}" size="${4:-}" alt=""
  [ -n "${DAT_RECORD_BY_SHA[$raw]+x}" ] && { printf '%s' "$raw"; return; }
  if [ -z "$size" ]; then size=$(stat -c '%s' "$p" 2>/dev/null); [ -z "$size" ] && size=$(stat -f '%z' "$p" 2>/dev/null); fi
  case "$ext" in
    nes)
      if [ "${size:-0}" -gt 16 ] 2>/dev/null; then
        alt="$(hash_stream_skip "$p" 16)"
        [ -n "${DAT_RECORD_BY_SHA[${alt,,}]+x}" ] && { printf '%s' "${alt,,}"; return; }
      fi
      ;;
    sfc|smc)
      if [ "${size:-0}" -gt 512 ] 2>/dev/null && [ $((size % 32768)) -eq 512 ]; then
        alt="$(hash_stream_skip "$p" 512)"
        [ -n "${DAT_RECORD_BY_SHA[${alt,,}]+x}" ] && { printf '%s' "${alt,,}"; return; }
      fi
      ;;
    z64|v64) ;;
    n64) ;;
  esac
  printf '%s' "$raw"
}

file_signature() {
  local p="$1" sig
  sig="$(stat -c '%s|%Y' "$p" 2>/dev/null)"
  [ -z "$sig" ] && sig="$(stat -f '%z|%m' "$p" 2>/dev/null)"
  printf '%s' "$sig"
}

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
  exec 22>>"$DISCOVERY_SNAPSHOT_NEW" 23>>"$DISCOVERY_CHANGED"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    sig="$(file_signature "$p")"
    printf '%s\t%s\n' "$p" "$sig" >&22
    DISCOVERY_CURRENT_PATH["$p"]=1
    old="${DISCOVERY_OLD_SIG[$p]:-}"
    if [ "$USE_HASH_CACHE" -eq 1 ] && [ -n "$old" ] && [ "$old" = "$sig" ]; then
      DISCOVERY_UNCHANGED=$((DISCOVERY_UNCHANGED+1))
    else
      printf '%s\n' "$p" >&23
      DISCOVERY_CHANGED_COUNT=$((DISCOVERY_CHANGED_COUNT+1))
      [ -z "$old" ] && DISCOVERY_ADDED=$((DISCOVERY_ADDED+1))
    fi
  done < "$GAME_LIST"
  exec 22>&- 23>&-
  if [ "$USE_HASH_CACHE" -eq 1 ]; then
    for p in "${!DISCOVERY_OLD_SIG[@]}"; do
      [ -n "${DISCOVERY_CURRENT_PATH[$p]+x}" ] || DISCOVERY_REMOVED=$((DISCOVERY_REMOVED+1))
    done
  fi
}

declare -A CACHE_SHA CACHE_NORMALIZED_SHA CACHE_DAT_STATUS CACHE_DAT_NAME CACHE_DAT_ROM CACHE_DAT_SOURCE CACHE_META_SYSTEM CACHE_META_CORE CACHE_META_FOLDER CACHE_META_REGION CACHE_META_RELEASE CACHE_META_LICENSE CACHE_RESOLVED_CLEAN CACHE_RESOLVED_REGION CACHE_RESOLVED_KIND CACHE_RESOLVED_PROPOSED CACHE_LOCATION_STATUS
CACHE_ENTRIES_LOADED=0
cache_lookup() { local p="$1" sig="$2" k="$p|$sig"; printf '%s' "${CACHE_SHA[$k]:-}"; }
declare -A CLASS_SYSTEM CLASS_FILE CLASS_EXT CLASS_STEM CLASS_CLEAN CLASS_REGION CLASS_KIND CLASS_PROPOSED
CLASS_CACHE_ENTRIES_LOADED=0; CLASS_CACHE_HITS=0; CLASS_CACHE_MISSES=0
load_classification_cache() {
  local fmt p sig system file ext stem clean region kind proposed k
  [ -s "$CLASS_CACHE" ] || return 0
  while IFS=$'\t' read -r p sig system file ext stem clean region kind proposed; do
    if [ "$p" = "format" ]; then fmt="$sig"; continue; fi
    [ "$fmt" = "$CLASS_CACHE_FORMAT" ] || { CLASS_CACHE_ENTRIES_LOADED=0; return 0; }
    k="$p|$sig"; CLASS_SYSTEM["$k"]="$system"; CLASS_FILE["$k"]="$file"; CLASS_EXT["$k"]="$ext"; CLASS_STEM["$k"]="$stem"; CLASS_CLEAN["$k"]="$clean"; CLASS_REGION["$k"]="$region"; CLASS_KIND["$k"]="$kind"; CLASS_PROPOSED["$k"]="$proposed"; CLASS_CACHE_ENTRIES_LOADED=$((CLASS_CACHE_ENTRIES_LOADED+1))
  done < "$CLASS_CACHE"
}

should_hash() {
  local system="${1,,}" ext="${2,,}"
  case "$system" in
    nes|*nintendo*entertainment*|famicom|fds|*family*computer*) case "$ext" in nes|fds) return 0;; esac ;;
    snes|sfc|*super*nintendo*|*super*famicom*) case "$ext" in sfc|smc) return 0;; esac ;;
    gameboy|game\ boy|gb) [ "$ext" = "gb" ] && return 0 ;;
    gbc|*game*boy*color*) [ "$ext" = "gbc" ] && return 0 ;;
    gba|*game*boy*advance*) [ "$ext" = "gba" ] && return 0 ;;
    n64|*nintendo*64*) case "$ext" in n64|z64|v64|rom) return 0;; esac ;;
    megadrive|mega\ drive|genesis|*sega*mega*drive*|*sega*genesis*) case "$ext" in md|gen|bin) return 0;; esac ;;
    s32x|32x|*sega*32x*) case "$ext" in 32x|bin) return 0;; esac ;;
    sms|*master*system*|mark\ iii) case "$ext" in sms|bin) return 0;; esac ;;
    atari2600|*atari*2600*) case "$ext" in a26|bin|rom) return 0;; esac ;;
    intellivision|*mattel*intellivision*) case "$ext" in int|bin|rom) return 0;; esac ;;
    tgfx16|turbografx16|*turbo*grafx*|*pc*engine*) case "$ext" in pce|sgx|bin) return 0;; esac ;;
    amiga) case "$ext" in adf|adz|ipf|rom) return 0;; esac ;;
    c64|commodore\ 64) case "$ext" in crt|prg|d64|g64|tap|t64|bin|rom) return 0;; esac ;;
    archie|archimedes) case "$ext" in adf|jfd|rom) return 0;; esac ;;
  esac
  case "$ext" in nes|fds|sfc|smc|gb|gbc|gba|n64|z64|v64|md|gen|32x|sms|a26|int|pce|sgx) return 0;; esac
  return 1
}

declare -A ACTIVE_DAT_SYSTEMS DAT_RECORD_BY_SHA
DAT_SEP=$'\x1f'
canonical_dat_system() {
  local s="${1,,}"
  case "$s" in
    nes|fds|famicom) printf 'NES' ;;
    snes|sfc|super\ nintendo*|super\ famicom*) printf 'SNES' ;;
    n64|nintendo64|nintendo\ 64) printf 'N64' ;;
    gameboy|game\ boy|gb) printf 'GAMEBOY' ;;
    gbc|gameboycolor|game\ boy\ color) printf 'GBC' ;;
    gba|gameboyadvance|game\ boy\ advance) printf 'GBA' ;;
    megadrive|mega\ drive|genesis) printf 'MegaDrive' ;;
    s32x|32x) printf 'S32X' ;;
    sms|master\ system*) printf 'SMS' ;;
    atari2600|atari\ 2600) printf 'Atari2600' ;;
    intellivision) printf 'Intellivision' ;;
    tgfx16|turbografx16|turbografx\ 16|pcengine|pc\ engine) printf 'TGFX16' ;;
    amiga) printf 'Amiga' ;;
    c64|commodore64|commodore\ 64) printf 'C64' ;;
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
dat_cache_file() {
  local sys="$1" safe
  sys="${sys,,}"
  safe="${sys//[^A-Za-z0-9._-]/_}"
  printf '%s/%s.tsv' "$DAT_CACHE_DIR" "$safe"
}
rebuild_dat_cache() {
  local tmp="$DAT_CACHE_DIR/.build.$$" h title rom source size crc32 md5 meta_system meta_core meta_folder meta_region meta_release meta_license rest out cache_system
  rm -rf "$tmp"; mkdir -p "$tmp" || return 1
  while IFS=$'\t' read -r h title rom source size crc32 md5 meta_system meta_core meta_folder meta_region meta_release meta_license rest; do
    [ "$h" = "sha1" ] && continue; h="${h,,}"; [[ "$h" =~ ^[0-9a-f]{40}$ ]] || continue; [ -n "$meta_system" ] || continue
    cache_system="$(canonical_dat_system "$meta_system")"
    cache_system="${cache_system,,}"
    out="$tmp/${cache_system//[^A-Za-z0-9._-]/_}.tsv"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$h" "$title" "$rom" "$source" "$meta_system" "$meta_core" "$meta_folder" "$meta_region" "$meta_release" "$meta_license" >> "$out"
  done < "$HASH_DB_TSV"
  local old_cache
  for old_cache in "$DAT_CACHE_DIR"/*.tsv; do [ -f "$old_cache" ] && rm -f "$old_cache"; done
  for out in "$tmp"/*.tsv; do [ -f "$out" ] || continue; mv "$out" "$DAT_CACHE_DIR/" || { rm -rf "$tmp"; return 1; }; done
  rm -rf "$tmp"
  printf '%s\n' "$HASH_DB_FINGERPRINT" > "$DAT_CACHE_META"
}
load_dat_cache_file() {
  local f="$1" h title rom source meta_system meta_core meta_folder meta_region meta_release meta_license
  [ -f "$f" ] || return 0
  while IFS=$'\t' read -r h title rom source meta_system meta_core meta_folder meta_region meta_release meta_license rest; do
    [[ "$h" =~ ^[0-9a-f]{40}$ ]] || continue
    if [ -z "${DAT_RECORD_BY_SHA[$h]+x}" ]; then DAT_RECORD_BY_SHA["$h"]="$title$DAT_SEP$rom$DAT_SEP$source$DAT_SEP$meta_system$DAT_SEP$meta_core$DAT_SEP$meta_folder$DAT_SEP$meta_region$DAT_SEP$meta_release$DAT_SEP$meta_license"; HASH_INDEX_COUNT=$((HASH_INDEX_COUNT+1)); fi
  done < "$f"
}
build_dat_index() {
  : > "$DAT_INDEX"; HASH_DB_SOURCE="None"; HASH_DB_FINGERPRINT="missing"; HASH_INDEX_COUNT=0; HASH_DB_SKIPPED_SYSTEM_RECORDS=0; DAT_CACHE_STATUS="Unavailable"
  if [ -f "$HASH_DB_TSV" ]; then
    echo "    Using bundled hash database: $HASH_DB_TSV"
    HASH_DB_SOURCE="mister_hash_database.tsv"; HASH_DB_FINGERPRINT="$(hash_file "$HASH_DB_TSV")"
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
      while IFS=$'\t' read -r h title rom source size crc32 md5 meta_system meta_core meta_folder meta_region meta_release meta_license rest; do
        [ "$h" = "sha1" ] && continue; h="${h,,}"; [[ "$h" =~ ^[0-9a-f]{40}$ ]] || continue
        cache_system="$(canonical_dat_system "$meta_system")"; cache_system="${cache_system,,}"
        [ -n "${ACTIVE_DAT_SYSTEMS[$cache_system]+x}" ] || { HASH_DB_SKIPPED_SYSTEM_RECORDS=$((HASH_DB_SKIPPED_SYSTEM_RECORDS+1)); continue; }
        [ -n "${DAT_RECORD_BY_SHA[$h]+x}" ] || { DAT_RECORD_BY_SHA["$h"]="$title$DAT_SEP$rom$DAT_SEP$source$DAT_SEP$meta_system$DAT_SEP$meta_core$DAT_SEP$meta_folder$DAT_SEP$meta_region$DAT_SEP$meta_release$DAT_SEP$meta_license"; HASH_INDEX_COUNT=$((HASH_INDEX_COUNT+1)); }
      done < "$HASH_DB_TSV"
    fi
  else
    echo "    WARNING: $HASH_DB_TSV was not found. Hashes will still be calculated, but canonical matching will be unavailable."
  fi
}

dat_lookup() { local h="${1,,}"; [ -n "${DAT_RECORD_BY_SHA[$h]+x}" ] || return 0; dat_unpack "${DAT_RECORD_BY_SHA[$h]}"; printf '%s\t%s\t%s\t%s\n' "$h" "$DAT_TITLE" "$DAT_ROM" "$DAT_SOURCE"; }

declare -A COMPLETION_REFERENCE_KEYS COMPLETION_OWNED_KEYS
declare -A COMPLETION_TOTAL_BY_SYSTEM COMPLETION_OWNED_BY_SYSTEM
declare -A COMPLETION_TITLE_REGION COMPLETION_TITLE_RELEASE COMPLETION_TITLE_LICENSE
completion_region_selected() {
  local meta="${1,,}" selected normalized; normalized="${meta// /}"
  for selected in "${COMPLETION_REGIONS[@]}"; do
    selected="${selected,,}"; selected="${selected// /}"
    case ",$normalized," in *",$selected,"*) return 0 ;; esac
    if [ "$COMPLETION_INCLUDE_WORLD" -eq 1 ] && [ "$normalized" = "world" ]; then case "$selected" in usa|europe|japan) return 0 ;; esac; fi
  done; return 1
}
completion_release_selected() { local release="${1,,}" license="${2,,}"; if [ "$COMPLETION_RETAIL_ONLY" -eq 1 ]; then case "$release" in retail/standard|retail|standard) ;; *) return 1 ;; esac; case "$license" in *unlicensed*|unl|*homebrew*|*aftermarket*) return 1 ;; esac; fi; return 0; }
completion_record_eligible() { completion_region_selected "$1" && completion_release_selected "$2" "$3"; }
build_completion_reference() {
  local h sys title region release license key
  for h in "${!DAT_RECORD_BY_SHA[@]}"; do
    dat_unpack "${DAT_RECORD_BY_SHA[$h]}"; sys="$DAT_SYSTEM"; title="$DAT_TITLE"; region="$DAT_REGION"; release="$DAT_RELEASE"; license="$DAT_LICENSE"
    [ -n "$sys" ] && [ -n "$title" ] || continue; completion_record_eligible "$region" "$release" "$license" || continue; key="$sys|$title"
    if [ -z "${COMPLETION_REFERENCE_KEYS[$key]+x}" ]; then COMPLETION_REFERENCE_KEYS["$key"]=1; COMPLETION_TOTAL_BY_SYSTEM["$sys"]=$(( ${COMPLETION_TOTAL_BY_SYSTEM["$sys"]:-0} + 1 )); COMPLETION_TITLE_REGION["$key"]="$region"; COMPLETION_TITLE_RELEASE["$key"]="$release"; COMPLETION_TITLE_LICENSE["$key"]="$license"; fi
  done
}
record_completion_owned() {
  local sys="$1" title="$2" region="$3" release="$4" license="$5" key
  [ -n "$sys" ] && [ -n "$title" ] || return 0; completion_record_eligible "$region" "$release" "$license" || return 0; key="$sys|$title"; [ -n "${COMPLETION_REFERENCE_KEYS[$key]+x}" ] || return 0
  if [ -z "${COMPLETION_OWNED_KEYS[$key]+x}" ]; then COMPLETION_OWNED_KEYS["$key"]=1; COMPLETION_OWNED_BY_SYSTEM["$sys"]=$(( ${COMPLETION_OWNED_BY_SYSTEM["$sys"]:-0} + 1 )); fi
}
load_hash_cache() {
  local old_format="" old_db="" p sig sha normalized_sha ds dn dr dsrc ms mc mf mr mrel ml rc rr rk rp ls k v
  if [ -s "$CACHE_META" ]; then
    while IFS='=' read -r k v; do
      case "$k" in
        CACHE_FORMAT) old_format="$v" ;;
        HASH_DB_FINGERPRINT) old_db="$v" ;;
      esac
    done < "$CACHE_META"
  fi
  [ "$old_format" = "$CACHE_FORMAT" ] || return 0
  [ -s "$HASH_CACHE" ] || return 0
  while IFS=$'\t' read -r p sig sha normalized_sha ds dn dr dsrc ms mc mf mr mrel ml rc rr rk rp ls; do
    [ "$p" = "path" ] && continue
    k="$p|$sig"
    CACHE_SHA["$k"]="$sha"
    CACHE_NORMALIZED_SHA["$k"]="$normalized_sha"
    CACHE_ENTRIES_LOADED=$((CACHE_ENTRIES_LOADED+1))
    if [ "$old_db" = "$HASH_DB_FINGERPRINT" ]; then
      CACHE_DAT_STATUS["$k"]="$ds"
      CACHE_DAT_NAME["$k"]="$dn"
      CACHE_DAT_ROM["$k"]="$dr"
      CACHE_DAT_SOURCE["$k"]="$dsrc"
      CACHE_META_SYSTEM["$k"]="$ms"
      CACHE_META_CORE["$k"]="$mc"
      CACHE_META_FOLDER["$k"]="$mf"
      CACHE_META_REGION["$k"]="$mr"
      CACHE_META_RELEASE["$k"]="$mrel"
      CACHE_META_LICENSE["$k"]="$ml"
      CACHE_RESOLVED_CLEAN["$k"]="$rc"
      CACHE_RESOLVED_REGION["$k"]="$rr"
      CACHE_RESOLVED_KIND["$k"]="$rk"
      CACHE_RESOLVED_PROPOSED["$k"]="$rp"
      CACHE_LOCATION_STATUS["$k"]="$ls"
    fi
  done < "$HASH_CACHE"
}
csv_escape() { local s="$1"; s="${s//\"/\"\"}"; printf '"%s"' "$s"; }
csv_row() { local dest="$1" out="" v; shift; for v in "$@"; do v="${v//\"/\"\"}"; [ -n "$out" ] && out+=","; out+="\"$v\""; done; printf '%s\n' "$out" >> "$dest"; }
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
region_of() { local s="${1,,}"; if [[ "$s" =~ \((usa|us|u)(,|\)|[[:space:]]) ]] || [[ "$s" =~ \((ue|u,e|u\+e)\) ]]; then echo USA; elif [[ "$s" =~ \((world|w)\) ]]; then echo World; elif [[ "$s" =~ \((europe|eur|e)\) ]]; then echo Europe; elif [[ "$s" =~ \((japan|jpn|j)\) ]]; then echo Japan; elif [[ "$s" =~ \((canada|can)\) ]]; then echo Canada; elif [[ "$s" =~ \((australia|aus)\) ]]; then echo Australia; elif [[ "$s" =~ \((korea|kor|k)\) ]]; then echo Korea; elif [[ "$s" =~ \((brazil|bra|b)\) ]]; then echo Brazil; else echo Unknown; fi; }
kind_of() { local s="${1,,}"; if [[ "$s" =~ \((proto|prototype|beta|demo|sample)([^a-z]|$) ]] || [[ "$s" =~ \[(proto|prototype|beta|demo|sample)([^a-z]|$) ]]; then echo Prototype/Beta/Demo; elif [[ "$s" =~ \((rev|revision)[[:space:]._-]*[0-9a-z]+\) ]] || [[ "$s" =~ \[(rev|revision)[[:space:]._-]*[0-9a-z]+\] ]]; then echo Revision; elif [[ "$s" =~ \((unl|unlicensed|homebrew|aftermarket)\) ]] || [[ "$s" =~ \[(unl|unlicensed|homebrew|aftermarket)\] ]] || [[ "$s" == *" homebrew "* ]] || [[ "$s" == *" aftermarket "* ]]; then echo Homebrew/Unlicensed; elif [[ "$s" =~ \[t[^]]*\] ]] || [[ "$s" == *"(translation"* ]] || [[ "$s" == *"(translated"* ]] || [[ "$s" == *"(eng)"* ]] || [[ "$s" == *"(english"* ]] || [[ "$s" == *"translation"* ]] || [[ "$s" == *"english patched"* ]]; then echo Translation; elif [[ "$s" =~ \[h[^]]*\] ]] || [[ "$s" == *"(hack"* ]] || [[ "$s" == *"(hacked"* ]] || [[ "$s" == *"(improvement"* ]] || [[ "$s" == *"(redux"* ]] || [[ "$s" == *"(randomizer"* ]] || [[ "$s" == *" hack "* ]] || [[ "$s" == *" improvement "* ]] || [[ "$s" == *" randomizer "* ]]; then echo Hack/Modified; else echo Retail/Standard; fi; }
is_support_file() { local path="${1,,}" file="${2,,}" stem="${2%.*}"; stem="${stem,,}"; case "$path" in */bios/*|*/bioses/*|*/firmware/*|*/kickstart/*|*/bootrom/*|*/boot_rom/*|*/boot-rom/*|*/system_rom/*|*/system-rom/*|*/machine_rom/*|*/machine-rom/*|*/testrom/*|*/test_rom/*|*/test-rom/*|*/diagnostic/*|*/diagnostics/*|*/utilities/*|*/utility/*) return 0 ;; esac; case "$file" in bios.*|boot.rom|boot.bin|boot[0-9]*.rom|boot[0-9]*_*.rom|boot[0-9]*-*.rom|firmware.*|kickstart.rom|cd_bios.rom|uni-bioscd.rom|kanji.rom|empty.rom) return 0 ;; esac; if [[ "$stem" == *" bios"* || "$stem" == *"bios "* || "$stem" == *"boot rom"* || "$stem" == *"bootrom"* || "$stem" == *"firmware"* || "$stem" == *"test rom"* || "$stem" == *"diagnostic"* || "$stem" == serialporttest* || "$stem" == sioecho* || "$stem" == statuslights* || "$stem" == *"240p test suite"* ]]; then return 0; fi; return 1; }
clean_title() { local s="$1" before; local re_region='^(.*)[[:space:]]+\((USA|US|U|World|W|Europe|EUR|E|Japan|JPN|J|Canada|CAN|Australia|AUS|Korea|KOR|Brazil|BRA|UE|U,E|U\+E)\)(.*)$'; local re_meta='^(.*)[[:space:]]+\((Rev(ision)?[[:space:]._-]*[0-9A-Za-z]+|Proto(type)?|Beta|Demo|Sample|Unl(icensed)?|Homebrew|Aftermarket|Translation|Translated|Eng(lish)?[^)]*)\)(.*)$'; local re_bracket='^(.*)[[:space:]]+\[([tThH][^]]*|!|[bBoOfFpPaA][0-9]*|[cCxX])\](.*)$'; while :; do before="$s"; if [[ "$s" =~ $re_region ]]; then s="${BASH_REMATCH[1]}${BASH_REMATCH[3]}"; elif [[ "$s" =~ $re_meta ]]; then s="${BASH_REMATCH[1]}${BASH_REMATCH[7]}"; elif [[ "$s" =~ $re_bracket ]]; then s="${BASH_REMATCH[1]}${BASH_REMATCH[3]}"; else break; fi; done; s="$(trim "$s")"; while [[ "$s" == *"  "* ]]; do s="${s//  / }"; done; s="${s% -}"; s="${s% _}"; s="$(trim "$s")"; [ -z "$s" ] && s="$1"; printf '%s' "$s"; }
suffix_for() { local region="$1" kind="$2" suffix=""; [ "$region" != "USA" ] && [ "$region" != "Unknown" ] && suffix=" [$region]"; [ "$region" = "Unknown" ] && suffix=" [Unknown Region]"; [ "$kind" != "Retail/Standard" ] && suffix="$suffix [$kind]"; printf '%s' "$suffix"; }
region_of_set() { local s="${1,,}"; if [[ "$s" =~ \((usa|us|u)(,|\)|[[:space:]]) ]] || [[ "$s" =~ \((ue|u,e|u\+e)\) ]]; then HOT_RESULT=USA; elif [[ "$s" =~ \((world|w)\) ]]; then HOT_RESULT=World; elif [[ "$s" =~ \((europe|eur|e)\) ]]; then HOT_RESULT=Europe; elif [[ "$s" =~ \((japan|jpn|j)\) ]]; then HOT_RESULT=Japan; elif [[ "$s" =~ \((canada|can)\) ]]; then HOT_RESULT=Canada; elif [[ "$s" =~ \((australia|aus)\) ]]; then HOT_RESULT=Australia; elif [[ "$s" =~ \((korea|kor|k)\) ]]; then HOT_RESULT=Korea; elif [[ "$s" =~ \((brazil|bra|b)\) ]]; then HOT_RESULT=Brazil; else HOT_RESULT=Unknown; fi; }
kind_of_set() { local s="${1,,}"; if [[ "$s" =~ \((proto|prototype|beta|demo|sample)([^a-z]|$) ]] || [[ "$s" =~ \[(proto|prototype|beta|demo|sample)([^a-z]|$) ]]; then HOT_RESULT='Prototype/Beta/Demo'; elif [[ "$s" =~ \((rev|revision)[[:space:]._-]*[0-9a-z]+\) ]] || [[ "$s" =~ \[(rev|revision)[[:space:]._-]*[0-9a-z]+\] ]]; then HOT_RESULT=Revision; elif [[ "$s" =~ \((unl|unlicensed|homebrew|aftermarket)\) ]] || [[ "$s" =~ \[(unl|unlicensed|homebrew|aftermarket)\] ]] || [[ "$s" == *" homebrew "* ]] || [[ "$s" == *" aftermarket "* ]]; then HOT_RESULT='Homebrew/Unlicensed'; elif [[ "$s" =~ \[t[^]]*\] ]] || [[ "$s" == *"(translation"* ]] || [[ "$s" == *"(translated"* ]] || [[ "$s" == *"(eng)"* ]] || [[ "$s" == *"(english"* ]] || [[ "$s" == *"translation"* ]] || [[ "$s" == *"english patched"* ]]; then HOT_RESULT=Translation; elif [[ "$s" =~ \[h[^]]*\] ]] || [[ "$s" == *"(hack"* ]] || [[ "$s" == *"(hacked"* ]] || [[ "$s" == *"(improvement"* ]] || [[ "$s" == *"(redux"* ]] || [[ "$s" == *"(randomizer"* ]] || [[ "$s" == *" hack "* ]] || [[ "$s" == *" improvement "* ]] || [[ "$s" == *" randomizer "* ]]; then HOT_RESULT='Hack/Modified'; else HOT_RESULT='Retail/Standard'; fi; }
trim_set() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; HOT_RESULT="$s"; }
clean_title_set() { local s="$1" original="$1" before; local re_region='^(.*)[[:space:]]+\((USA|US|U|World|W|Europe|EUR|E|Japan|JPN|J|Canada|CAN|Australia|AUS|Korea|KOR|Brazil|BRA|UE|U,E|U\+E)\)(.*)$'; local re_meta='^(.*)[[:space:]]+\((Rev(ision)?[[:space:]._-]*[0-9A-Za-z]+|Proto(type)?|Beta|Demo|Sample|Unl(icensed)?|Homebrew|Aftermarket|Translation|Translated|Eng(lish)?[^)]*)\)(.*)$'; local re_bracket='^(.*)[[:space:]]+\[([tThH][^]]*|!|[bBoOfFpPaA][0-9]*|[cCxX])\](.*)$'; while :; do before="$s"; if [[ "$s" =~ $re_region ]]; then s="${BASH_REMATCH[1]}${BASH_REMATCH[3]}"; elif [[ "$s" =~ $re_meta ]]; then s="${BASH_REMATCH[1]}${BASH_REMATCH[7]}"; elif [[ "$s" =~ $re_bracket ]]; then s="${BASH_REMATCH[1]}${BASH_REMATCH[3]}"; else break; fi; done; trim_set "$s"; s="$HOT_RESULT"; while [[ "$s" == *"  "* ]]; do s="${s//  / }"; done; s="${s% -}"; s="${s% _}"; trim_set "$s"; s="$HOT_RESULT"; [ -z "$s" ] && s="$original"; HOT_RESULT="$s"; }
suffix_for_set() { local region="$1" kind="$2" suffix=""; [ "$region" != "USA" ] && [ "$region" != "Unknown" ] && suffix=" [$region]"; [ "$region" = "Unknown" ] && suffix=" [Unknown Region]"; [ "$kind" != "Retail/Standard" ] && suffix="$suffix [$kind]"; HOT_RESULT="$suffix"; }
location_status_set() { local current="${1,,}" expected="${2,,}"; if [ -z "$expected" ]; then HOT_RESULT=Unknown; return; fi; if [ "$current" = "$expected" ]; then HOT_RESULT=OK; return; fi; case "$expected" in nes) case "$current" in nes|fds|famicom) HOT_RESULT='OK (compatible folder)'; return;; esac ;; gameboy) case "$current" in gameboy|game\ boy|gb|gbc|gameboycolor|game\ boy\ color) HOT_RESULT='OK (compatible folder)'; return;; esac ;; snes) case "$current" in snes|sfc|sgb|supergameboy|super\ game\ boy) HOT_RESULT='OK (compatible folder)'; return;; esac ;; n64) case "$current" in n64|nintendo64|nintendo\ 64) HOT_RESULT='OK (compatible folder)'; return;; esac ;; esac; HOT_RESULT=MISFILED; }
location_status() { local current="${1,,}" expected="${2,,}"; [ -z "$expected" ] && { echo "Unknown"; return; }; [ "$current" = "$expected" ] && { echo "OK"; return; }; case "$expected" in nes) case "$current" in nes|fds|famicom) echo "OK (compatible folder)"; return;; esac ;; gameboy) case "$current" in gameboy|game\ boy|gb|gbc|gameboycolor|game\ boy\ color) echo "OK (compatible folder)"; return;; esac ;; snes) case "$current" in snes|sfc|sgb|supergameboy|super\ game\ boy) echo "OK (compatible folder)"; return;; esac ;; n64) case "$current" in n64|nintendo64|nintendo\ 64) echo "OK (compatible folder)"; return;; esac ;; esac; echo "MISFILED"; }
expected_unmatched_class() {
  local name="${1,,}" kind="${2,,}"
  case "$kind" in *homebrew*|*unlicensed*|*prototype*|*demo*|*beta*) printf 'Expected non-retail'; return ;; esac
  case "$name" in *test*suite*|*test*rom*|*diagnostic*|*benchmark*|*homebrew*|*unlicensed*|*prototype*|*proto*|*beta*|*demo*) printf 'Expected support/non-retail'; return ;; esac
  printf 'Review unmatched retail/unknown'
}


START_TIME=$(date +%s); LAST_PROGRESS_TIME=$START_TIME
on_exit() { cleanup; }; trap on_exit EXIT INT TERM
progress_check() { local stage="$1" current="${2:-0}" total="${3:-0}" now elapsed pct; now=$(date +%s); if [ $((now - LAST_PROGRESS_TIME)) -ge 30 ]; then elapsed=$((now - START_TIME)); pct=0; if [ "$total" -gt 0 ] 2>/dev/null; then pct=$((current * 100 / total)); fi; printf '[%02d:%02d] %s: %s / %s (%s%%)' $((elapsed/60)) $((elapsed%60)) "$stage" "$current" "$total" "$pct"; if [ "$stage" = "Building reports" ]; then printf ' | DAT matches: %s | Unmatched: %s' "${DAT_MATCHED:-0}" "$(( ${HASHED:-0} - ${DAT_MATCHED:-0} ))"; fi; printf '\n'; LAST_PROGRESS_TIME=$now; fi; }

echo
SELF_CHECK_STATUS="PASS"; SELF_CHECK_NOTES=""
for cmd in find sort stat awk wc xargs; do if ! command -v "$cmd" >/dev/null 2>&1; then SELF_CHECK_STATUS="FAIL"; SELF_CHECK_NOTES="$SELF_CHECK_NOTES missing:$cmd"; fi; done
if ! command -v sha1sum >/dev/null 2>&1 && ! command -v openssl >/dev/null 2>&1; then SELF_CHECK_STATUS="FAIL"; SELF_CHECK_NOTES="$SELF_CHECK_NOTES missing:sha1-tool"; fi
if [ ! -f "$HASH_DB_TSV" ]; then SELF_CHECK_STATUS="FAIL"; SELF_CHECK_NOTES="$SELF_CHECK_NOTES missing:hash-db"; fi
if [ -f "$HASH_DB_TSV" ]; then IFS=$'\t' read -r dbh _ < "$HASH_DB_TSV"; [ "$dbh" = "sha1" ] || { SELF_CHECK_STATUS="FAIL"; SELF_CHECK_NOTES="$SELF_CHECK_NOTES invalid:hash-db-header"; }; DB_HEADER=$(head -n 1 "$HASH_DB_TSV" 2>/dev/null); REQUIRED_DB_HEADER=$'sha1\tcanonical_title\tcanonical_rom_name\tdat_source\tsize\tcrc32\tmd5\tmister_system\tmister_core\texpected_folder\tregion\trelease_type\tlicense_status'; if [ "$DB_HEADER" = "$REQUIRED_DB_HEADER" ]; then METADATA_LAYER_STATUS="MiSTer-aware"; else METADATA_LAYER_STATUS="INVALID"; SELF_CHECK_STATUS="FAIL"; SELF_CHECK_NOTES="$SELF_CHECK_NOTES invalid:mister-aware-db-schema"; fi; DB_LINE_COUNT=$(wc -l < "$HASH_DB_TSV" 2>/dev/null); DB_LINE_COUNT=${DB_LINE_COUNT//[[:space:]]/}; [ "${DB_LINE_COUNT:-0}" -ge 1000 ] 2>/dev/null || { SELF_CHECK_STATUS="FAIL"; SELF_CHECK_NOTES="$SELF_CHECK_NOTES suspiciously-small:hash-db"; }; fi
if [ ! -w "$AUDIT" ]; then SELF_CHECK_STATUS="FAIL"; SELF_CHECK_NOTES="$SELF_CHECK_NOTES not-writable:audit-dir"; fi
if [ "$SELF_CHECK_STATUS" != "PASS" ]; then echo "ERROR: Startup self-check failed:$SELF_CHECK_NOTES"; echo "No audit was published."; read -p "Press Enter to exit..."; exit 1; fi
METADATA_LAYER_STATUS="${METADATA_LAYER_STATUS:-Unknown}"; EXPORTER_BUILD_SHA1="$(hash_file "$0")"
exporter_build_id() {
  local p="$1" digest="" rest=""
  if command -v md5sum >/dev/null 2>&1; then
    read -r digest rest < <(md5sum "$p" 2>/dev/null)
  elif command -v openssl >/dev/null 2>&1; then
    digest="$(openssl md5 "$p" 2>/dev/null)"
    digest="${digest##* }"
  else
    digest="$RUNTIME_BUILD_SHA1"
  fi
  printf '%.8s' "$digest"
}
EXPORTER_BUILD_ID="$(exporter_build_id "$0")"
echo "+--------------------------------------------------+"; echo "| MiSTer ROM Library Auditor v1.4                 |"; printf "| Build: %-41s|\n" "$RUNTIME_BUILD_ID"; echo "| Read-only audit - no ROMs or saves are changed  |"; echo "+--------------------------------------------------+"; echo

AUDIT_MENU_SELECTION=1
render_audit_menu() {
  printf "+--------------------------------------------------+\n"
  printf "| SELECT AUDIT MODE                                |\n"
  printf "+--------------------------------------------------+\n"
  printf "|  UP / LEFT    FAST AUDIT                         |\n"
  printf "|               Recommended - reuses cached hashes |\n"
  printf "|                                                  |\n"
  printf "|  DOWN / RIGHT FULL VERIFICATION                  |\n"
  printf "|               Recalculates every supported SHA-1 |\n"
  printf "+--------------------------------------------------+\n"
  printf "| D-pad selects and starts immediately             |\n"
  printf "| Keyboard: 1 = Fast | 2 = Full | Auto Fast: 15s  |\n"
  printf "+--------------------------------------------------+\n"
}
render_audit_menu
while :; do
  AUDIT_KEY=""
  if ! IFS= read -rsn1 -t 15 AUDIT_KEY; then
    AUDIT_MENU_SELECTION=1
    break
  fi
  case "$AUDIT_KEY" in
    ""|1|f|F)
      AUDIT_MENU_SELECTION=1
      break
      ;;
    2|v|V)
      AUDIT_MENU_SELECTION=2
      break
      ;;
    $'\x1b')
      IFS= read -rsn1 -t 0.15 AUDIT_KEY2 || AUDIT_KEY2=""
      if [ "$AUDIT_KEY2" = "[" ]; then
        IFS= read -rsn1 -t 0.15 AUDIT_KEY3 || AUDIT_KEY3=""
        case "$AUDIT_KEY3" in
          A|D) AUDIT_MENU_SELECTION=1; break ;;
          B|C) AUDIT_MENU_SELECTION=2; break ;;
        esac
      fi
      ;;
  esac
done
if [ "$AUDIT_MENU_SELECTION" -eq 2 ]; then AUDIT_MODE="Full Verification"; USE_HASH_CACHE=0; else AUDIT_MODE="Fast Audit"; USE_HASH_CACHE=1; fi
echo; echo "Selected: $AUDIT_MODE"; echo "----------------------------------------------------"; echo
DISCOVERY_START=$(date +%s); echo "[1/5] Scanning game library..."
find "$GAMES" -type f \( -iname "*.nes" -o -iname "*.fds" -o -iname "*.sfc" -o -iname "*.smc" -o -iname "*.gb" -o -iname "*.gbc" -o -iname "*.gba" -o -iname "*.md" -o -iname "*.gen" -o -iname "*.32x" -o -iname "*.sms" -o -iname "*.gg" -o -iname "*.sg" -o -iname "*.pce" -o -iname "*.sgx" -o -iname "*.a26" -o -iname "*.a52" -o -iname "*.a78" -o -iname "*.col" -o -iname "*.int" -o -iname "*.cue" -o -iname "*.chd" -o -iname "*.d64" -o -iname "*.d81" -o -iname "*.g64" -o -iname "*.adf" -o -iname "*.hdf" -o -iname "*.dsk" -o -iname "*.tap" -o -iname "*.tzx" -o -iname "*.rom" -o -iname "*.n64" -o -iname "*.z64" -o -iname "*.v64" \) -print 2>/dev/null | LC_ALL=C sort > "$GAME_LIST"
GAME_SCAN_COUNT=$(wc -l < "$GAME_LIST" | tr -d "[:space:]"); load_discovery_snapshot; build_discovery_snapshot; echo "    Files discovered: $GAME_SCAN_COUNT"; if [ "$USE_HASH_CACHE" -eq 1 ]; then echo "    Unchanged: $DISCOVERY_UNCHANGED | Added: $DISCOVERY_ADDED | Changed: $((DISCOVERY_CHANGED_COUNT-DISCOVERY_ADDED)) | Removed: $DISCOVERY_REMOVED"; else echo "    Full Verification: incremental discovery state ignored"; fi; DISCOVERY_END=$(date +%s); SAVE_START=$DISCOVERY_END

echo "[2/5] Indexing save files..."; : > "$SAVE_LIST"; : > "$SAVE_INDEX"; declare -A SAVES_BY_STEM; SAVE_PROCESSED=0
if [ -d "$SAVES" ]; then find "$SAVES" -type f \( -iname "*.sav" -o -iname "*.srm" -o -iname "*.ram" -o -iname "*.eep" -o -iname "*.fla" -o -iname "*.sra" -o -iname "*.mcd" -o -iname "*.nv" \) -print 2>/dev/null | sort > "$SAVE_LIST"; SAVE_SCAN_COUNT=$(wc -l < "$SAVE_LIST" | tr -d "[:space:]"); [ -z "$SAVE_SCAN_COUNT" ] && SAVE_SCAN_COUNT=0; while IFS= read -r sp; do [ -z "$sp" ] && continue; sf="${sp##*/}"; sstem="${sf%.*}"; save_key_idx="${sstem,,}"; if [ -n "${SAVES_BY_STEM[$save_key_idx]:-}" ]; then SAVES_BY_STEM["$save_key_idx"]+=$'\n'"$sp"; else SAVES_BY_STEM["$save_key_idx"]="$sp"; fi; printf '%s\t%s\n' "$save_key_idx" "$sp" >> "$SAVE_INDEX"; SAVE_PROCESSED=$((SAVE_PROCESSED+1)); progress_check "Indexing saves" "$SAVE_PROCESSED" "$SAVE_SCAN_COUNT"; done < "$SAVE_LIST"; fi
SAVE_END=$(date +%s); DB_START=$SAVE_END
echo "[3/5] Loading hash database..."; build_active_dat_systems; build_dat_index; echo "    Hash database source: $HASH_DB_SOURCE"; echo "    Hash records indexed: $HASH_INDEX_COUNT"; build_completion_reference; load_hash_cache; load_classification_cache; DB_END=$(date +%s); CLASSIFY_START=$DB_END

declare -A CLASS_DISCOVERY_SIG; while IFS=$'\t' read -r dp ds; do [ "$dp" = "format" ] && continue; [ -n "$dp" ] && CLASS_DISCOVERY_SIG["$dp"]="$ds"; done < "$DISCOVERY_SNAPSHOT_NEW"
echo "[4/5] Classifying titles and collisions..."; : > "$PLAN"; : > "$WORK.hashjobs"; declare -A NAME_COUNTS; SKIPPED=0; CLASSIFIED=0
printf 'format\t%s\n' "$CLASS_CACHE_FORMAT" > "$CLASS_CACHE_NEW"
while IFS= read -r p; do
  [ -z "$p" ] && continue
  rel="${p#$GAMES/}"; system="${rel%%/*}"; [ "$system" = "$rel" ] && system="Unknown"; file="${p##*/}"; ext="${file##*.}"; stem="${file%.*}"; case "${ext,,}" in md|gen) system="MegaDrive" ;; 32x) system="S32X" ;; esac
  if is_support_file "$p" "$file"; then SKIPPED=$((SKIPPED+1)); continue; fi
  sig=""; if [ -s "$DISCOVERY_SNAPSHOT_NEW" ]; then sig="${CLASS_DISCOVERY_SIG[$p]:-}"; fi; [ -n "$sig" ] || sig="$(file_signature "$p")"; class_key="$p|$sig"
  if [ -n "${CLASS_CLEAN[$class_key]+x}" ]; then
    system="${CLASS_SYSTEM[$class_key]}"; file="${CLASS_FILE[$class_key]}"; ext="${CLASS_EXT[$class_key]}"; stem="${CLASS_STEM[$class_key]}"; clean="${CLASS_CLEAN[$class_key]}"; region="${CLASS_REGION[$class_key]}"; kind="${CLASS_KIND[$class_key]}"; proposed="${CLASS_PROPOSED[$class_key]}"; CLASS_CACHE_HITS=$((CLASS_CACHE_HITS+1))
  else
    region_of_set "$stem"; region="$HOT_RESULT"; kind_of_set "$stem"; kind="$HOT_RESULT"; clean_title_set "$stem"; clean="$HOT_RESULT"; suffix_for_set "$region" "$kind"; suffix="$HOT_RESULT"; proposed="$clean$suffix.$ext"; CLASS_CACHE_MISSES=$((CLASS_CACHE_MISSES+1))
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$p" "$sig" "$system" "$file" "$ext" "$stem" "$clean" "$region" "$kind" "$proposed" >> "$CLASS_CACHE_NEW"
  key="${system,,}|${proposed,,}"; NAME_COUNTS["$key"]=$(( ${NAME_COUNTS["$key"]:-0} + 1 )); if should_hash "$system" "$ext"; then [ "$USE_HASH_CACHE" -eq 0 ] && printf '%s\0' "$p" >> "$WORK.hashjobs"; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$system" "$p" "$file" "$ext" "$stem" "$clean" "$region" "$kind" "$sig" "$proposed" >> "$PLAN"; CLASSIFIED=$((CLASSIFIED+1)); progress_check "Classifying titles" "$CLASSIFIED" "$GAME_SCAN_COUNT"
done < "$GAME_LIST"
if [ -s "$CLASS_CACHE_NEW" ]; then mv -f "$CLASS_CACHE_NEW" "$CLASS_CACHE"; fi
if [ -s "$DISCOVERY_SNAPSHOT_NEW" ]; then mv -f "$DISCOVERY_SNAPSHOT_NEW" "$DISCOVERY_SNAPSHOT"; fi
CLASSIFY_END=$(date +%s)

declare -A PREHASH_SHA_BY_PATH SYSTEM_FILES SYSTEM_ELIGIBLE SYSTEM_MATCHED SYSTEM_UNMATCHED SYSTEM_SECONDS
FULL_VERIFY_PARALLEL_SECONDS=0
if [ "$USE_HASH_CACHE" -eq 0 ]; then
  : > "$PREHASH_RESULTS"; pv_start=$SECONDS
  if [ -s "$WORK.hashjobs" ]; then
    HASH_JOB_TOTAL=$(tr -cd '\0' < "$WORK.hashjobs" | wc -c | tr -d '[:space:]')
    [ -z "$HASH_JOB_TOTAL" ] && HASH_JOB_TOTAL=0
    echo "    Full Verification: hashing $HASH_JOB_TOTAL supported files..."
    XARGS_PARALLEL_ARGS=""
    if xargs --help 2>&1 | grep -q -- '-P'; then XARGS_PARALLEL_ARGS="-P $FULL_VERIFY_WORKERS"; fi
    if command -v sha1sum >/dev/null 2>&1; then
      xargs -0 -n1 $XARGS_PARALLEL_ARGS sh -c 'p="$1"; h=$(sha1sum "$p" 2>/dev/null); h=${h%% *}; printf "%s\t%s\n" "$h" "$p"' sh < "$WORK.hashjobs" > "$PREHASH_RESULTS" &
    else
      xargs -0 -n1 $XARGS_PARALLEL_ARGS sh -c 'p="$1"; h=$(openssl sha1 "$p" 2>/dev/null); h=${h##* }; printf "%s\t%s\n" "$h" "$p"' sh < "$WORK.hashjobs" > "$PREHASH_RESULTS" &
    fi
    HASH_PID=$!; HASH_NEXT_STATUS=500
    while kill -0 "$HASH_PID" 2>/dev/null; do
      HASH_DONE=$(wc -l < "$PREHASH_RESULTS" 2>/dev/null | tr -d '[:space:]'); [ -z "$HASH_DONE" ] && HASH_DONE=0
      if [ "$HASH_DONE" -ge "$HASH_NEXT_STATUS" ] 2>/dev/null; then
        HASH_PCT=0; [ "$HASH_JOB_TOTAL" -gt 0 ] 2>/dev/null && HASH_PCT=$((HASH_DONE * 100 / HASH_JOB_TOTAL))
        printf "    Hashing: %s / %s (%s%%)\n" "$HASH_DONE" "$HASH_JOB_TOTAL" "$HASH_PCT"
        HASH_NEXT_STATUS=$(( (HASH_DONE / 500 + 1) * 500 ))
      fi
      sleep 5
    done
    wait "$HASH_PID"
    HASH_DONE=$(wc -l < "$PREHASH_RESULTS" 2>/dev/null | tr -d '[:space:]'); [ -z "$HASH_DONE" ] && HASH_DONE=0
    HASH_PCT=0; [ "$HASH_JOB_TOTAL" -gt 0 ] 2>/dev/null && HASH_PCT=$((HASH_DONE * 100 / HASH_JOB_TOTAL))
    echo "    Hashing complete: $HASH_DONE / $HASH_JOB_TOTAL ($HASH_PCT%)"
    [ "$HASH_DONE" -eq "$HASH_JOB_TOTAL" ] || { echo "ERROR: Full Verification hash pass incomplete ($HASH_DONE/$HASH_JOB_TOTAL)."; exit 1; }
    while IFS=$'\t' read -r ph pp; do [ -n "$pp" ] && PREHASH_SHA_BY_PATH["$pp"]="$ph"; done < "$PREHASH_RESULTS"
  fi
  FULL_VERIFY_PARALLEL_SECONDS=$((SECONDS-pv_start))
fi
REPORT_START=$(date +%s)

cat > "$STAGE_OUT" <<EOF2
MiSTer Game Library v1.4
Generated: $(date)
READ-ONLY EXPORT - no games or saves were modified.
Reports folder: $AUDIT
============================================================
EOF2
printf '%s\n' '"system","clean_title","region","version_type","original_filename","proposed_filename","full_path","save_match_count","collision_status","sha1","dat_match","dat_canonical_name","dat_rom_name","dat_source","mister_system","mister_core","expected_folder","metadata_region","release_type","license_status","location_status"' > "$STAGE_CSV"
printf '%s\n' '"system","current_path","proposed_filename","region","version_type","status"' > "$STAGE_REN"
printf '%s\n' '"system","game_path","save_path","proposed_save_filename","match_type","status"' > "$STAGE_SAVE_REN"
printf '%s\n' '"sha1","system","full_path","original_filename","clean_title"' > "$STAGE_HASH_DUP"
printf '%s\n' '"sha1","system","full_path","original_filename","canonical_name","dat_rom_name","dat_source","mister_system","mister_core","expected_folder","region","release_type","license_status"' > "$STAGE_DAT_MATCH"
printf '%s\n' '"sha1","system","full_path","original_filename","unmatched_class"' > "$STAGE_DAT_UNMATCHED"
printf '%s\n' '"system","full_path","canonical_name","mister_system","mister_core","expected_folder","location_status"' > "$STAGE_LOCATION_AUDIT"
: > "$HASH_ROWS"; : > "$COLLISION_ROWS"
# Keep hot append targets open during the per-ROM loop to reduce FAT open/close I/O.
exec 17>>"$HASH_ROWS" 20>>"$HASH_CACHE_NEW" 21>>"$COLLISION_ROWS"
TOTAL=0; SAVE_MATCHES=0; COLLISIONS=0; RESOLVED_COLLISIONS=0; PRE_COLLISION_ROWS=0; HASHED=0; DAT_MATCHED=0; HASH_REUSED=0; ROW_METADATA_REUSED=0; ROW_METADATA_REFRESHED=0; HASH_CALCULATED=0; HASH_SKIPPED=0; HASH_ELIGIBLE=0
printf 'path\tsignature\tsha1\tnormalized_sha1\tdat_status\tdat_name\tdat_rom\tdat_source\tmeta_system\tmeta_core\tmeta_folder\tmeta_region\tmeta_release\tmeta_license\tresolved_clean\tresolved_region\tresolved_kind\tresolved_proposed\tlocation_status\n' > "$HASH_CACHE_NEW"
declare -A SEEN_NAMES

echo "[5/5] Building audit reports..."; PLAN_TOTAL=$(wc -l < "$PLAN" | tr -d "[:space:]"); [ -z "$PLAN_TOTAL" ] && PLAN_TOTAL=0
exec 3< "$PLAN"
while IFS=
  proposed="${fallback_proposed:-}"; if [ -z "$proposed" ]; then suffix_for_set "$region" "$kind"; suffix="$HOT_RESULT"; proposed="$clean$suffix.$ext"; fi; base="${proposed%.$ext}"; key="${system,,}|${proposed,,}"; collision="None"; pre_collision=0
  if [ "${NAME_COUNTS["$key"]:-0}" -gt 1 ]; then pre_collision=1; PRE_COLLISION_ROWS=$((PRE_COLLISION_ROWS+1)); n=$(( ${SEEN_NAMES["$key"]:-0} + 1 )); SEEN_NAMES["$key"]=$n; proposed="$base [Variant $n].$ext"; collision="Pending final-target review"; fi
  row_seconds_start=$SECONDS; SYSTEM_FILES["$system"]=$(( ${SYSTEM_FILES["$system"]:-0} + 1 ))
  sha1=""; dat_status="Not applicable"; dat_name=""; dat_rom=""; dat_source=""; meta_system=""; meta_core=""; meta_folder=""; meta_region=""; meta_release=""; meta_license=""; loc_status="Unknown"
  if should_hash "$system" "$ext"; then
    HASH_ELIGIBLE=$((HASH_ELIGIBLE+1)); SYSTEM_ELIGIBLE["$system"]=$(( ${SYSTEM_ELIGIBLE["$system"]:-0} + 1 )); cache_key="$p|$sig"; cached_sha=""; cached_normalized_sha=""; if [ "$USE_HASH_CACHE" -eq 1 ]; then cached_sha="${CACHE_SHA[$cache_key]:-}"; cached_normalized_sha="${CACHE_NORMALIZED_SHA[$cache_key]:-}"; fi
    if [ -n "$cached_sha" ]; then
      sha1="$cached_sha"; HASH_REUSED=$((HASH_REUSED+1))
      if [ -n "${CACHE_DAT_STATUS[$cache_key]+x}" ]; then
        dat_status="${CACHE_DAT_STATUS[$cache_key]}"; dat_name="${CACHE_DAT_NAME[$cache_key]:-}"; dat_rom="${CACHE_DAT_ROM[$cache_key]:-}"; dat_source="${CACHE_DAT_SOURCE[$cache_key]:-}"
        meta_system="${CACHE_META_SYSTEM[$cache_key]:-}"; meta_core="${CACHE_META_CORE[$cache_key]:-}"; meta_folder="${CACHE_META_FOLDER[$cache_key]:-}"; meta_region="${CACHE_META_REGION[$cache_key]:-}"; meta_release="${CACHE_META_RELEASE[$cache_key]:-}"; meta_license="${CACHE_META_LICENSE[$cache_key]:-}"
        if [ -n "${CACHE_RESOLVED_PROPOSED[$cache_key]+x}" ]; then clean="${CACHE_RESOLVED_CLEAN[$cache_key]:-$clean}"; region="${CACHE_RESOLVED_REGION[$cache_key]:-$region}"; kind="${CACHE_RESOLVED_KIND[$cache_key]:-$kind}"; proposed="${CACHE_RESOLVED_PROPOSED[$cache_key]:-$proposed}"; loc_status="${CACHE_LOCATION_STATUS[$cache_key]:-Unknown}"; row_metadata_reused=1; ROW_METADATA_REUSED=$((ROW_METADATA_REUSED+1)); fi
      else
        dat_status="No match"
      fi
    else
      if [ "$USE_HASH_CACHE" -eq 0 ] && [ -n "${PREHASH_SHA_BY_PATH[$p]:-}" ]; then sha1="${PREHASH_SHA_BY_PATH[$p]}"; else sha1="$(hash_file "$p")"; fi
      [ -n "$sha1" ] && [ "$sha1" != "UNAVAILABLE" ] && HASH_CALCULATED=$((HASH_CALCULATED+1)); dat_status="No match"
    fi
  else HASH_SKIPPED=$((HASH_SKIPPED+1)); fi
  if [ -n "$sha1" ] && [ "$sha1" != "UNAVAILABLE" ]; then
    HASHED=$((HASHED+1)); printf '%s\t%s\t%s\t%s\t%s\n' "${sha1,,}" "$system" "$p" "$file" "$clean" >&17; hkey="${sha1,,}"; file_size="${sig%%|*}"; if [ -n "$cached_normalized_sha" ]; then matched_hkey="${cached_normalized_sha,,}"; elif [ -n "${DAT_RECORD_BY_SHA[$hkey]+x}" ]; then matched_hkey="$hkey"; else matched_hkey="$(normalized_dat_hash "$p" "$ext" "$hkey" "$file_size")"; fi; if [ "$matched_hkey" != "$hkey" ]; then hkey="$matched_hkey"; sha1="$matched_hkey"; dat_status="Normalized SHA-1"; fi
    if [ -n "${DAT_RECORD_BY_SHA[$hkey]+x}" ]; then
      if [ "$row_metadata_reused" -eq 0 ]; then
        dat_unpack "${DAT_RECORD_BY_SHA[$hkey]}"; dat_name="$DAT_TITLE"; dat_rom="$DAT_ROM"; dat_source="$DAT_SOURCE"; meta_system="$DAT_SYSTEM"; meta_core="$DAT_CORE"; meta_folder="$DAT_FOLDER"; meta_region="$DAT_REGION"; meta_release="$DAT_RELEASE"; meta_license="$DAT_LICENSE"
      fi
      if [ "$row_metadata_reused" -eq 1 ]; then
        : # Fast Audit already restored DB-derived row metadata from the fingerprint-bound cache.
      elif [ -n "$dat_rom" ]; then canonical_file="${dat_rom##*/}"; canonical_stem="${canonical_file%.*}"; [ -n "$canonical_stem" ] && { clean_title_set "$canonical_stem"; clean="$HOT_RESULT"; }; [ -n "$meta_region" ] && region="$meta_region"; [ -n "$meta_release" ] && kind="$meta_release"; proposed="$canonical_file"; elif [ -n "$dat_name" ]; then clean="$(clean_title "$dat_name")"; [ -n "$meta_region" ] && region="$meta_region"; [ -n "$meta_release" ] && kind="$meta_release"; suffix_for_set "$region" "$kind"; proposed="$clean$HOT_RESULT.$ext"; fi
      if [ "$row_metadata_reused" -eq 0 ]; then location_status_set "$system" "$meta_folder"; loc_status="$HOT_RESULT"; ROW_METADATA_REFRESHED=$((ROW_METADATA_REFRESHED+1)); fi; record_completion_owned "${meta_system:-$system}" "$dat_name" "$meta_region" "$meta_release" "$meta_license"; [ "$dat_status" = "Normalized SHA-1" ] || dat_status="Exact SHA-1"; DAT_MATCHED=$((DAT_MATCHED+1)); SYSTEM_MATCHED["$system"]=$(( ${SYSTEM_MATCHED["$system"]:-0} + 1 ))
      csv_row "$STAGE_DAT_MATCH" "$sha1" "$system" "$p" "$file" "$dat_name" "$dat_rom" "$dat_source" "$meta_system" "$meta_core" "$meta_folder" "$meta_region" "$meta_release" "$meta_license"
      csv_row "$STAGE_LOCATION_AUDIT" "$system" "$p" "$dat_name" "$meta_system" "$meta_core" "$meta_folder" "$loc_status"
    else SYSTEM_UNMATCHED["$system"]=$(( ${SYSTEM_UNMATCHED["$system"]:-0} + 1 )); unmatched_class="$(expected_unmatched_class "$file" "$kind")"; csv_row "$STAGE_DAT_UNMATCHED" "$sha1" "$system" "$p" "$file" "$unmatched_class"; fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$p" "$sig" "${sha1,,}" "${matched_hkey:-${sha1,,}}" "$dat_status" "$dat_name" "$dat_rom" "$dat_source" "$meta_system" "$meta_core" "$meta_folder" "$meta_region" "$meta_release" "$meta_license" "$clean" "$region" "$kind" "$proposed" "$loc_status" >&20
  fi

  # Collision planning is actionable only for DAT-identified ROMs. Unmatched ROMs
  # remain visible in inventory/unmatched reports but are not rename candidates, so
  # their filename-derived fallback targets must not block Preview.
  authoritative=0; case "$dat_status" in "Exact SHA-1"|"Normalized SHA-1") [ -n "$proposed" ] && authoritative=1 ;; esac
  if [ "$authoritative" -eq 1 ]; then
    printf '%s\t%s\t%s\t%s\t%s\n' "$p" "$key" "$pre_collision" "$authoritative" "${system,,}|${proposed,,}" >&21
    if [ "$pre_collision" -eq 1 ]; then collision="Canonical DAT variant candidate"; fi
  elif [ "$pre_collision" -eq 1 ]; then
    collision="Inventory only - unmatched ROM"
  fi

  save_count=0; save_key="${stem,,}"
  if [ -n "${SAVES_BY_STEM[$save_key]:-}" ]; then while IFS= read -r sp; do [ -z "$sp" ] && continue; sf="${sp##*/}"; sext="${sf##*.}"; proposed_save="${proposed%.*}.$sext"; csv_row "$STAGE_SAVE_REN" "$system" "$p" "$sp" "$proposed_save" "Exact original basename" "REVIEW ONLY"; save_count=$((save_count+1)); SAVE_MATCHES=$((SAVE_MATCHES+1)); done <<< "${SAVES_BY_STEM[$save_key]}"; fi

  printf '[%s] %s | Region: %s | Type: %s | Saves: %s | File: %s | Collision: %s\n' "$system" "$clean" "$region" "$kind" "$save_count" "$file" "$collision" >> "$STAGE_OUT"
  csv_row "$STAGE_CSV" "$system" "$clean" "$region" "$kind" "$file" "$proposed" "$p" "$save_count" "$collision" "$sha1" "$dat_status" "$dat_name" "$dat_rom" "$dat_source" "$meta_system" "$meta_core" "$meta_folder" "$meta_region" "$meta_release" "$meta_license" "$loc_status"
  csv_row "$STAGE_REN" "$system" "$p" "$proposed" "$region" "$kind" "REVIEW ONLY"
  TOTAL=$((TOTAL+1)); SYSTEM_SECONDS["$system"]=$(( ${SYSTEM_SECONDS["$system"]:-0} + SECONDS - row_seconds_start )); progress_check "Building reports" "$TOTAL" "$PLAN_TOTAL"
done
exec 3<&-
exec 17>&- 20>&- 21>&-

# Issue #7: evaluate both pre-DAT groups and duplicate final targets.
if [ -s "$COLLISION_ROWS" ]; then
  read -r COLLISIONS RESOLVED_COLLISIONS < <(awk -F '\t' '
    { group[NR]=$2; pre[NR]=$3+0; auth[NR]=$4+0; target[NR]=$5; final_count[$5]++; if(pre[NR]){group_rows[$2]++;group_auth[$2]+=auth[NR];group_target[$2 SUBSEP $5]++} }
    END {
      for(g in group_rows){duplicate=0;prefix=g SUBSEP;for(k in group_target)if(index(k,prefix)==1&&group_target[k]>1){duplicate=1;break};group_safe[g]=(group_auth[g]==group_rows[g]&&!duplicate)}
      blocking=0;resolved=0
      for(i=1;i<=NR;i++){is_blocking=(final_count[target[i]]>1)||(pre[i]&&!group_safe[group[i]]);if(is_blocking)blocking++;else if(pre[i])resolved++}
      print blocking,resolved
    }' "$COLLISION_ROWS")
  COLLISIONS=${COLLISIONS:-0}; RESOLVED_COLLISIONS=${RESOLVED_COLLISIONS:-0}
fi

COMPLETION_REGION_LABEL="$(IFS=', '; echo "${COMPLETION_REGIONS[*]}")"
printf '%s\n' '"system","owned_titles","reference_titles","missing_titles","completion_percent","regions","scope"' > "$STAGE_COMPLETION"
printf '%s\n' '"system","canonical_title","region","release_type","license_status"' > "$STAGE_MISSING_COMPLETION"
while IFS= read -r c_sys; do [ -n "$c_sys" ] || continue; present_matches=0; for present_sys in "${!SYSTEM_MATCHED[@]}"; do [ "$(canonical_dat_system "$present_sys")" = "$c_sys" ] && present_matches=$((present_matches + ${SYSTEM_MATCHED[$present_sys]:-0})); done; [ "$present_matches" -gt 0 ] || continue; c_total="${COMPLETION_TOTAL_BY_SYSTEM[$c_sys]:-0}"; c_owned="${COMPLETION_OWNED_BY_SYSTEM[$c_sys]:-0}"; c_missing=$((c_total-c_owned)); c_pct="$(awk -v a="$c_owned" -v b="$c_total" 'BEGIN{if(b>0) printf "%.2f", (a*100)/b; else printf "0.00"}')"; if [ "$COMPLETION_RETAIL_ONLY" -eq 1 ]; then c_scope="Retail releases"; else c_scope="All release types"; fi; csv_row "$STAGE_COMPLETION" "$c_sys" "$c_owned" "$c_total" "$c_missing" "$c_pct" "$COMPLETION_REGION_LABEL" "$c_scope"; done < <(printf '%s\n' "${!COMPLETION_TOTAL_BY_SYSTEM[@]}" | LC_ALL=C sort)
for c_key in "${!COMPLETION_REFERENCE_KEYS[@]}"; do [ -n "${COMPLETION_OWNED_KEYS[$c_key]+x}" ] && continue; c_sys="${c_key%%|*}"; present_matches=0; for present_sys in "${!SYSTEM_MATCHED[@]}"; do [ "$(canonical_dat_system "$present_sys")" = "$c_sys" ] && present_matches=$((present_matches + ${SYSTEM_MATCHED[$present_sys]:-0})); done; [ "$present_matches" -gt 0 ] || continue; c_title="${c_key#*|}"; csv_row "$STAGE_MISSING_COMPLETION" "$c_sys" "$c_title" "${COMPLETION_TITLE_REGION[$c_key]:-}" "${COMPLETION_TITLE_RELEASE[$c_key]:-}" "${COMPLETION_TITLE_LICENSE[$c_key]:-}"; done
{ head -n 1 "$STAGE_MISSING_COMPLETION"; tail -n +2 "$STAGE_MISSING_COMPLETION" | LC_ALL=C sort; } > "$STAGE_MISSING_COMPLETION.tmp" && mv -f "$STAGE_MISSING_COMPLETION.tmp" "$STAGE_MISSING_COMPLETION"

CACHE_REFRESHED=$HASH_CALCULATED; CACHE_NOT_REUSED=$(( CACHE_ENTRIES_LOADED > HASH_REUSED ? CACHE_ENTRIES_LOADED - HASH_REUSED : 0 )); CACHE_HIT_RATE="0.0"; if [ "$HASH_ELIGIBLE" -gt 0 ]; then CACHE_HIT_RATE=$(awk -v a="$HASH_REUSED" -v b="$HASH_ELIGIBLE" 'BEGIN{printf "%.1f", (a*100)/b}'); fi
if [ -s "$HASH_CACHE_NEW" ]; then mv -f "$HASH_CACHE_NEW" "$HASH_CACHE"; else : > "$HASH_CACHE"; fi
{ echo "CACHE_FORMAT=$CACHE_FORMAT"; echo "EXPORTER_VERSION=1.4"; echo "HASH_DB_FINGERPRINT=$HASH_DB_FINGERPRINT"; echo "UPDATED=$(date +%s)"; } > "$CACHE_META.tmp" && mv -f "$CACHE_META.tmp" "$CACHE_META"
if [ -s "$HASH_ROWS" ]; then awk -F '\t' '{c[$1]++} END {for (h in c) if (c[h]>1) print h}' "$HASH_ROWS" | sort > "$WORK.duphashes"; while IFS= read -r dh; do awk -F '\t' -v k="$dh" '$1==k {print}' "$HASH_ROWS" | while IFS=$'\t' read -r h hs hp hf hc; do csv_escape "$h" >> "$STAGE_HASH_DUP"; printf ',' >> "$STAGE_HASH_DUP"; csv_escape "$hs" >> "$STAGE_HASH_DUP"; printf ',' >> "$STAGE_HASH_DUP"; csv_escape "$hp" >> "$STAGE_HASH_DUP"; printf ',' >> "$STAGE_HASH_DUP"; csv_escape "$hf" >> "$STAGE_HASH_DUP"; printf ',' >> "$STAGE_HASH_DUP"; csv_escape "$hc" >> "$STAGE_HASH_DUP"; printf '\n' >> "$STAGE_HASH_DUP"; done; done < "$WORK.duphashes"; rm -f "$WORK.duphashes"; fi

cat >> "$STAGE_OUT" <<EOF2

============================================================
Candidate game/disc files: $TOTAL
BIOS/support files skipped: $SKIPPED
Pre-DAT collision rows: $PRE_COLLISION_ROWS
Canonical DAT variant rows resolved safely: $RESOLVED_COLLISIONS
Blocking collision rows: $COLLISIONS
Corresponding save-file matches found: $SAVE_MATCHES
Files with SHA-1 available: $HASHED
Hashes reused from cache: $HASH_REUSED
Hashes calculated this run: $HASH_CALCULATED
Unsupported-format hashes skipped: $HASH_SKIPPED
Hash database source: $HASH_DB_SOURCE
Hash records indexed: $HASH_INDEX_COUNT
Exact DAT SHA-1 matches: $DAT_MATCHED

Created in $AUDIT:
  game_library.txt
  library_catalog.csv
  proposed_renames.csv
  proposed_save_renames.csv
  hash_duplicates.csv
  dat_matches.csv
  unmatched_hashes.csv
  library_completion.csv
  missing_library_titles.csv
  MiSTer_Library_Audit.txt  (single file to upload for review)

IMPORTANT:
- Nothing was renamed, moved, or deleted.
- Exact DAT matches use canonical DAT filenames; filename parsing is fallback-only for unmatched ROMs.
- Pre-DAT filename collisions are blocking only when final canonical targets remain ambiguous.
- Authoritative DAT variants with unique final targets are reported as resolved and do not block Preview.
- Unmatched/unsupported ROMs are inventory-only and do not participate in rename collision planning.
- Duplicate authoritative canonical targets remain blocking.
- Save matching still uses the original ROM basename and remains REVIEW ONLY.
- SHA-1 hashes identify byte-for-byte duplicate files regardless of filename.
- CUE/BIN and other multi-file disc sets require coordinated renaming before any future apply step.
EOF2

AUDIT_VERDICT="PASS"; APPLY_RECOMMENDATION="SAFE TO PREVIEW"; INTEGRITY_NOTES=""; MISFILED_COUNT=0
[ -s "$STAGE_LOCATION_AUDIT" ] && MISFILED_COUNT=$(grep -c ',"MISFILED"$' "$STAGE_LOCATION_AUDIT" 2>/dev/null || true)
for required_report in "$STAGE_OUT" "$STAGE_CSV" "$STAGE_REN" "$STAGE_SAVE_REN" "$STAGE_HASH_DUP" "$STAGE_DAT_MATCH" "$STAGE_DAT_UNMATCHED" "$STAGE_LOCATION_AUDIT"; do if [ ! -f "$required_report" ]; then AUDIT_VERDICT="FAIL"; APPLY_RECOMMENDATION="DO NOT APPLY"; INTEGRITY_NOTES="$INTEGRITY_NOTES missing-report:${required_report##*/}"; fi; done
if [ "$TOTAL" -ne "$CLASSIFIED" ] 2>/dev/null; then AUDIT_VERDICT="FAIL"; APPLY_RECOMMENDATION="DO NOT APPLY"; INTEGRITY_NOTES="$INTEGRITY_NOTES catalog-count-mismatch"; fi
if [ $((TOTAL + SKIPPED)) -ne "$GAME_SCAN_COUNT" ] 2>/dev/null; then AUDIT_VERDICT="FAIL"; APPLY_RECOMMENDATION="DO NOT APPLY"; INTEGRITY_NOTES="$INTEGRITY_NOTES discovery-accounting-mismatch"; fi
if [ "$DAT_MATCHED" -gt "$HASHED" ] 2>/dev/null; then AUDIT_VERDICT="FAIL"; APPLY_RECOMMENDATION="DO NOT APPLY"; INTEGRITY_NOTES="$INTEGRITY_NOTES impossible-dat-count"; fi
if [ "$METADATA_LAYER_STATUS" != "MiSTer-aware" ]; then AUDIT_VERDICT="FAIL"; APPLY_RECOMMENDATION="DO NOT APPLY"; INTEGRITY_NOTES="$INTEGRITY_NOTES metadata-layer-invalid"; fi
MATCH_RATE_INT=100; if [ "$HASHED" -gt 0 ]; then MATCH_RATE_INT=$((DAT_MATCHED * 100 / HASHED)); fi
if [ "$AUDIT_VERDICT" != "FAIL" ]; then
  if [ "$MATCH_RATE_INT" -lt 50 ]; then AUDIT_VERDICT="PASS WITH WARNINGS"; APPLY_RECOMMENDATION="DO NOT APPLY"; INTEGRITY_NOTES="$INTEGRITY_NOTES low-dat-match-rate"; fi
  if [ "$COLLISIONS" -gt 0 ]; then AUDIT_VERDICT="PASS WITH WARNINGS"; INTEGRITY_NOTES="$INTEGRITY_NOTES collision-rows-will-be-skipped"; [ "$APPLY_RECOMMENDATION" != "DO NOT APPLY" ] && APPLY_RECOMMENDATION="SAFE TO PREVIEW (COLLISIONS SKIPPED)"; fi
fi
[ -z "$INTEGRITY_NOTES" ] && INTEGRITY_NOTES="none"

{
  echo "MiSTer Game Library Audit Bundle v1.4"; echo "Generated: $(date)"; echo "READ-ONLY AUDIT REPORT - no ROM or save data is embedded."; echo "FULL LIBRARY REPORT - audit mode: $AUDIT_MODE."; echo "============================================================"; echo; echo "[RUN SUMMARY]"; echo "Report scope: FULL LIBRARY"; echo "Audit mode: $AUDIT_MODE"; echo "Cache mode: $([ "$USE_HASH_CACHE" -eq 1 ] && echo "Incremental processing only" || echo "Bypassed for hash verification")"; echo "Files discovered: $GAME_SCAN_COUNT"; echo "Games/discs cataloged: $TOTAL"; echo "BIOS/support files skipped: $SKIPPED"; echo "Pre-DAT collision rows: $PRE_COLLISION_ROWS"; echo "Canonical DAT variant rows resolved safely: $RESOLVED_COLLISIONS"; echo "Blocking collision rows: $COLLISIONS"; echo "Save matches: $SAVE_MATCHES"; echo "Files with SHA-1 available: $HASHED"; echo "Hashes reused from cache: $HASH_REUSED"; echo "Hashes calculated this run: $HASH_CALCULATED"; echo "Unsupported-format hashes skipped: $HASH_SKIPPED"; echo "Hash database source: $HASH_DB_SOURCE"; echo "MiSTer-aware metadata layer: $METADATA_LAYER_STATUS"; echo "Exporter build SHA-1: $RUNTIME_BUILD_SHA1"; echo "Audit integrity verdict: $AUDIT_VERDICT"; echo "Apply recommendation: $APPLY_RECOMMENDATION"; echo "Hash records indexed: $HASH_INDEX_COUNT"; echo "Persistent DAT index: ${DAT_CACHE_STATUS:-Unavailable}"; echo "Hash records skipped for absent systems: ${HASH_DB_SKIPPED_SYSTEM_RECORDS:-0}"; echo "Exact DAT SHA-1 matches: $DAT_MATCHED"; echo; echo "[AUDIT_METADATA]"; echo "schema_version=$AUDIT_SCHEMA_VERSION"; echo "exporter_version=1.4"; echo "build_sha1=$RUNTIME_BUILD_SHA1"; echo "audit_mode=$AUDIT_MODE"; echo "database_sha1=$HASH_DB_FINGERPRINT"; echo "metadata_layer=$METADATA_LAYER_STATUS"; echo "library_files=$GAME_SCAN_COUNT"; echo "cataloged_files=$TOTAL"; echo "self_check=$SELF_CHECK_STATUS"; echo "integrity_verdict=$AUDIT_VERDICT"; echo "apply_recommendation=$APPLY_RECOMMENDATION"; echo "integrity_notes=$INTEGRITY_NOTES"; echo; echo "[DATABASE COVERAGE]"; echo "DAT-eligible ROMs: $HASH_ELIGIBLE"; echo "Matched: $DAT_MATCHED"; echo "Unmatched: $((HASHED-DAT_MATCHED))"; if [ "$HASHED" -gt 0 ]; then awk -v a="$DAT_MATCHED" -v b="$HASHED" 'BEGIN{printf "Match rate: %.2f%%\n", (a*100)/b}'; else echo "Match rate: 0.00%"; fi; echo "Other/unsupported files cataloged: $HASH_SKIPPED"; echo; echo "[LIBRARY COMPLETION]"; echo "Regions: $COMPLETION_REGION_LABEL"; if [ "$COMPLETION_RETAIL_ONLY" -eq 1 ]; then echo "Scope: Retail releases only"; else echo "Scope: All release types"; fi; echo "World releases count toward USA, Europe, and Japan when COMPLETION_INCLUDE_WORLD=1."; tail -n +2 "$STAGE_COMPLETION" | while IFS=',' read -r c_sys c_owned c_total c_missing c_pct rest; do c_sys="${c_sys#\"}"; c_sys="${c_sys%\"}"; c_owned="${c_owned#\"}"; c_owned="${c_owned%\"}"; c_total="${c_total#\"}"; c_total="${c_total%\"}"; c_missing="${c_missing#\"}"; c_missing="${c_missing%\"}"; c_pct="${c_pct#\"}"; c_pct="${c_pct%\"}"; echo "$c_sys | owned=$c_owned | reference=$c_total | missing=$c_missing | completion=$c_pct%"; done; echo "Missing-title detail: missing_library_titles.csv"; echo; echo "[CACHE HEALTH]"; echo "Entries loaded: $CACHE_ENTRIES_LOADED"; echo "Entries reused: $HASH_REUSED"; echo "Unchanged library records: $DISCOVERY_UNCHANGED"; echo "New library records: $DISCOVERY_ADDED"; echo "Modified library records: $((DISCOVERY_CHANGED_COUNT-DISCOVERY_ADDED))"; echo "Deleted library records: $DISCOVERY_REMOVED"; echo "Delta records analyzed: $DISCOVERY_CHANGED_COUNT"; echo "Classification entries loaded: $CLASS_CACHE_ENTRIES_LOADED"; echo "Classification hits: $CLASS_CACHE_HITS"; echo "Classification misses/refreshed: $CLASS_CACHE_MISSES"; echo "DAT/classification row metadata reused: $ROW_METADATA_REUSED"; echo "DAT/classification row metadata refreshed: $ROW_METADATA_REFRESHED"; echo "Entries refreshed: $CACHE_REFRESHED"; echo "Entries not reused/expired: $CACHE_NOT_REUSED"; echo "Cache hit rate: $CACHE_HIT_RATE%"; echo "Database fingerprint: $HASH_DB_FINGERPRINT"; echo; echo "[PER-SYSTEM PROCESSING]"; for sys in "${!SYSTEM_FILES[@]}"; do echo "$sys | files=${SYSTEM_FILES[$sys]} | dat_eligible=${SYSTEM_ELIGIBLE[$sys]:-0} | matched=${SYSTEM_MATCHED[$sys]:-0} | unmatched=${SYSTEM_UNMATCHED[$sys]:-0} | processing_seconds=${SYSTEM_SECONDS[$sys]:-0}"; done | LC_ALL=C sort; echo; echo "[TIMING]"; echo "discovery_seconds=$((DISCOVERY_END-DISCOVERY_START))"; echo "save_index_seconds=$((SAVE_END-SAVE_START))"; echo "database_cache_seconds=$((DB_END-DB_START))"; echo "classification_seconds=$((CLASSIFY_END-CLASSIFY_START))"; echo "parallel_full_verify_hash_seconds=$FULL_VERIFY_PARALLEL_SECONDS"; echo "report_processing_seconds=$(( $(date +%s)-REPORT_START ))"; echo "total_seconds_so_far=$(( $(date +%s)-START_TIME ))"; echo
  for report in game_library.txt library_catalog.csv dat_matches.csv unmatched_hashes.csv hash_duplicates.csv location_audit.csv library_completion.csv missing_library_titles.csv proposed_renames.csv proposed_save_renames.csv; do echo "============================================================"; echo "[BEGIN $report]"; echo "============================================================"; if [ -f "$STAGE_DIR/$report" ]; then cat "$STAGE_DIR/$report"; else echo "(report not generated)"; fi; echo; echo "[END $report]"; echo; done
} > "$STAGE_BUNDLE"

REPORT_END=$(date +%s); PUBLISH_START=$REPORT_END
for report in game_library.txt library_catalog.csv proposed_renames.csv proposed_save_renames.csv hash_duplicates.csv dat_matches.csv unmatched_hashes.csv location_audit.csv library_completion.csv missing_library_titles.csv MiSTer_Library_Audit.txt; do [ -f "$STAGE_DIR/$report" ] || continue; mv -f "$STAGE_DIR/$report" "$AUDIT/$report"; done
PUBLISH_END=$(date +%s); TOTAL_END=$PUBLISH_END; sync
DISCOVERY_SECONDS=$((DISCOVERY_END-DISCOVERY_START))
SAVE_INDEX_SECONDS=$((SAVE_END-SAVE_START))
DATABASE_CACHE_SECONDS=$((DB_END-DB_START))
CLASSIFICATION_SECONDS=$((CLASSIFY_END-CLASSIFY_START))
REPORT_PROCESSING_SECONDS=$((REPORT_END-REPORT_START))
PUBLISH_SECONDS=$((PUBLISH_END-PUBLISH_START))
TOTAL_SECONDS=$((TOTAL_END-START_TIME))
# Final timing telemetry is appended after atomic publication so the uploaded
# audit contains the same stage timings shown on-screen. This is diagnostic
# metadata only and does not affect audit/rename decisions.
{
  echo
  echo "[FINAL TIMING]"
  echo "discovery_seconds=$DISCOVERY_SECONDS"
  echo "save_index_seconds=$SAVE_INDEX_SECONDS"
  echo "database_cache_seconds=$DATABASE_CACHE_SECONDS"
  echo "classification_seconds=$CLASSIFICATION_SECONDS"
  echo "parallel_full_verify_hash_seconds=$FULL_VERIFY_PARALLEL_SECONDS"
  echo "report_processing_seconds=$REPORT_PROCESSING_SECONDS"
  echo "publish_seconds=$PUBLISH_SECONDS"
  echo "total_seconds=$TOTAL_SECONDS"
} >> "$BUNDLE"
echo; echo "+--------------------------------------------------+"; echo "| AUDIT COMPLETE                                   |"; echo "+--------------------------------------------------+"; echo " Mode              : $AUDIT_MODE"; echo " Games cataloged   : $TOTAL"; echo " DAT matches       : $DAT_MATCHED / $HASHED"; echo " Blocking collisions: $COLLISIONS"; echo " DAT variants safe : $RESOLVED_COLLISIONS"; echo " Save matches      : $SAVE_MATCHES"; echo " Fast delta        : new=$DISCOVERY_ADDED modified=$((DISCOVERY_CHANGED_COUNT-DISCOVERY_ADDED)) deleted=$DISCOVERY_REMOVED"; echo " Cache hit rate    : $CACHE_HIT_RATE%"; echo " Integrity         : $AUDIT_VERDICT"; echo " Apply             : $APPLY_RECOMMENDATION"; echo "----------------------------------------------------"; echo " Timing (seconds)"; echo "   Discovery       : $DISCOVERY_SECONDS"; echo "   Save index      : $SAVE_INDEX_SECONDS"; echo "   Database/cache  : $DATABASE_CACHE_SECONDS"; echo "   Classification  : $CLASSIFICATION_SECONDS"; echo "   Full hash pass  : $FULL_VERIFY_PARALLEL_SECONDS"; echo "   Report processing: $REPORT_PROCESSING_SECONDS"; echo "   Publish         : $PUBLISH_SECONDS"; echo "   TOTAL           : $TOTAL_SECONDS"; echo "----------------------------------------------------"; echo " Reports: $AUDIT"; echo " Review : MiSTer_Library_Audit.txt"; echo " Missing: missing_library_titles.csv"; echo "----------------------------------------------------"; echo " READ ONLY: no ROMs or saves were changed."; echo "----------------------------------------------------"; echo; echo "Press Enter to close, or wait 60 seconds."; read -t 60 -r _ || true

}

run_update_tools() {
# MiSTer-Audit-Update_v1.4.sh
# Companion updater for MiSTer ROM Library Auditor v1.4

ROOT="/media/fat"; GAMES="$ROOT/games"; SAVES="$ROOT/saves"; AUDIT="$ROOT/GameLibraryAudit"
GAME_CSV="$AUDIT/proposed_renames.csv"; SAVE_CSV="$AUDIT/proposed_save_renames.csv"; CATALOG="$AUDIT/library_catalog.csv"; BUNDLE="$AUDIT/MiSTer_Library_Audit.txt"
HISTORY="$AUDIT/RenameHistory"; PLAN="$AUDIT/apply_preview.tsv"; SKIPS="$AUDIT/apply_skipped.tsv"; PLAN_META="$AUDIT/apply_preview.meta"
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"; RUNTIME="$SCRIPT_DIR/MiSTer_Audit.sh"; HASH_DB="$SCRIPT_DIR/mister_hash_database.tsv"
EXPECTED_SCHEMA="4"; EXPECTED_EXPORTER_VERSION="1.4"; BLOCKLIST="/tmp/mister_updater_blocked.$$"; HEARTBEAT_EVERY=500
UPDATER_BUILD="preview-summary-2026-09-13a"
STAGE_PREFIX=""; STAGE_COLLISION=""; STAGE_RESOLVE=""; STAGE_GAME=""; STAGE_SAVE=""
cleanup(){ rm -f "$BLOCKLIST"; }; trap cleanup EXIT INT TERM; mkdir -p "$HISTORY" || exit 1
stage(){ echo; echo "[$1] $2"; }
hash_file(){ local p="$1"; if command -v sha1sum >/dev/null 2>&1; then sha1sum "$p" 2>/dev/null|awk '{print $1}'; elif command -v openssl >/dev/null 2>&1; then openssl sha1 "$p" 2>/dev/null|awk '{print $NF}'; else printf 'UNAVAILABLE'; fi; }
audit_meta(){ local key="$1"; awk -F= -v k="$key" '/^\[AUDIT_METADATA\]$/{inmeta=1;next}/^\[/&&inmeta{exit}inmeta&&$1==k{sub(/^[^=]*=/,"");print;exit}' "$BUNDLE" 2>/dev/null; }
trim_spaces(){ local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
validate_audit(){
 local mode="${1:-preview}" schema exporter_version build_sha database_sha metadata_layer self_check verdict recommendation notes notes_trimmed current_exporter_sha current_database_sha errors=0 collision_only=0
 [[ -f "$BUNDLE" ]]||{ echo "ERROR: Missing $BUNDLE"; echo "Run MiSTer_Audit and choose Audit first."; return 1; }
 schema="$(audit_meta schema_version)"; exporter_version="$(audit_meta exporter_version)"; build_sha="$(audit_meta build_sha1)"; database_sha="$(audit_meta database_sha1)"; metadata_layer="$(audit_meta metadata_layer)"; self_check="$(audit_meta self_check)"; verdict="$(audit_meta integrity_verdict)"; recommendation="$(audit_meta apply_recommendation)"; notes="$(audit_meta integrity_notes)"; notes_trimmed="$(trim_spaces "$notes")"
 [[ "$verdict" == "PASS WITH WARNINGS" && "$notes_trimmed" == "collision-review-required" ]]&&collision_only=1
 [[ "$recommendation" == "APPLY WITH SKIPS" && "$notes_trimmed" == *collision* ]]&&collision_only=1
 echo "Audit compatibility check"; echo "-------------------------"; echo "Schema:               ${schema:-MISSING}"; echo "Exporter version:     ${exporter_version:-MISSING}"; echo "Self-check:           ${self_check:-MISSING}"; echo "Metadata layer:       ${metadata_layer:-MISSING}"; echo "Integrity verdict:    ${verdict:-MISSING}"; echo "Apply recommendation: ${recommendation:-MISSING}"; echo "Integrity notes:      ${notes:-MISSING}"
 [[ "$schema" == "$EXPECTED_SCHEMA" ]]||{ echo "ERROR: Expected audit schema $EXPECTED_SCHEMA."; errors=1; }; [[ "$exporter_version" == "$EXPECTED_EXPORTER_VERSION" ]]||{ echo "ERROR: Expected exporter v$EXPECTED_EXPORTER_VERSION."; errors=1; }; [[ "$self_check" == PASS ]]||{ echo "ERROR: Auditor startup self-check did not pass."; errors=1; }; [[ "$metadata_layer" == MiSTer-aware ]]||{ echo "ERROR: MiSTer-aware metadata layer was not validated."; errors=1; }; [[ -n "$build_sha" && "$build_sha" != UNAVAILABLE ]]||{ echo "ERROR: Audit exporter build fingerprint is missing."; errors=1; }; [[ -n "$database_sha" && "$database_sha" != missing && "$database_sha" != UNAVAILABLE ]]||{ echo "ERROR: Audit database fingerprint is missing."; errors=1; }
 if [[ "$mode" == apply ]]; then
  if [[ "$verdict" == FAIL ]]; then echo "ERROR: Apply is blocked by integrity_verdict=FAIL."; errors=1; elif [[ "$verdict" == PASS ]]; then [[ "$recommendation" != "DO NOT APPLY" ]]||{ echo "ERROR: Auditor explicitly recommends DO NOT APPLY."; errors=1; }; elif ((collision_only)); then echo "WARNING: Audit contains collision-only warnings; blocking rows will be skipped automatically."; else echo "ERROR: Apply warnings are not limited to skippable collision rows."; errors=1; fi
  [[ -f "$RUNTIME" ]]||{ echo "ERROR: Current exporter not found."; errors=1; }; if [[ -f "$RUNTIME" ]]; then current_exporter_sha="$(hash_file "$RUNTIME")"; [[ "$current_exporter_sha" == "$build_sha" && "$current_exporter_sha" != UNAVAILABLE ]]||{ echo "ERROR: Exporter changed since this audit. Re-run audit."; errors=1; }; fi
  [[ -f "$HASH_DB" ]]||{ echo "ERROR: Current hash database not found."; errors=1; }; if [[ -f "$HASH_DB" ]]; then current_database_sha="$(hash_file "$HASH_DB")"; [[ "$current_database_sha" == "$database_sha" && "$current_database_sha" != UNAVAILABLE ]]||{ echo "ERROR: Hash database changed since this audit. Re-run audit."; errors=1; }; fi
 else
  if [[ "$verdict" == FAIL ]]; then echo "ERROR: Audit integrity failed."; errors=1; elif ((collision_only)); then echo "WARNING: Collision-only warnings detected; blocking rows will be shown as skipped."; elif [[ "$verdict" == "PASS WITH WARNINGS" || "$recommendation" == "DO NOT APPLY" ]]; then echo "WARNING: Preview allowed, but Apply remains blocked by non-collision warnings."; fi
 fi
 ((errors))&&{ echo "Audit compatibility check: BLOCKED"; return 1; }; echo "Audit compatibility check: PASS"
}
parse_csv(){ local s="$1" c field="" quoted=0 i; CSV_FIELDS=(); for((i=0;i<${#s};i++));do c="${s:i:1}"; if((quoted));then if [[ "$c" == '"' ]];then if [[ "${s:i+1:1}" == '"' ]];then field+='"'; ((i++));else quoted=0;fi;else field+="$c";fi;else case "$c" in '"')quoted=1;; ',')CSV_FIELDS+=("$field");field="";; *)field+="$c";;esac;fi;done; CSV_FIELDS+=("$field"); }
safe_under(){ case "$1" in "$2"/*)return 0;;*)return 1;;esac; }; unsafe_name(){ [[ -z "$1" || "$1" == */* || "$1" == . || "$1" == .. ]]; }
classify_blocking_games(){
 :>"$BLOCKLIST"; [[ -f "$CATALOG" ]]||{ echo "Missing $CATALOG"; return 1; }; local total=0; total=$(( $(wc -l <"$CATALOG")-1)); ((total<0))&&total=0
 stage "$STAGE_COLLISION" "Building collision safety map..."; echo "  Catalog rows: $total"
 awk -v heartbeat="$HEARTBEAT_EVERY" -v total="$total" -v resolve_stage="$STAGE_RESOLVE" '
 function csv_parse(s,a, i,c,n,field,quoted,nextc,k){for(k in a)delete a[k];n=1;field="";quoted=0;for(i=1;i<=length(s);i++){c=substr(s,i,1);if(quoted){if(c=="\""){nextc=substr(s,i+1,1);if(nextc=="\""){field=field "\"";i++}else quoted=0}else field=field c}else{if(c=="\"")quoted=1;else if(c==","){a[n++]=field;field=""}else field=field c}}a[n]=field;return n}
 function trimv(s){sub(/^[[:space:]]+/,"",s);sub(/[[:space:]]+$/,"",s);return s}
 function region_of(stem, s){s=tolower(stem);if(s~/\((usa|us|u)(,|\)|[[:space:]])/||s~/\((ue|u,e|u\+e)\)/)return "USA";if(s~/\((world|w)\)/)return "World";if(s~/\((europe|eur|e)\)/)return "Europe";if(s~/\((japan|jpn|j)\)/)return "Japan";if(s~/\((canada|can)\)/)return "Canada";if(s~/\((australia|aus)\)/)return "Australia";if(s~/\((korea|kor|k)\)/)return "Korea";if(s~/\((brazil|bra|b)\)/)return "Brazil";return "Unknown"}
 function kind_of(stem, s){s=tolower(stem);if(s~/\((proto|prototype|beta|demo|sample)([^a-z]|$)/||s~/\[(proto|prototype|beta|demo|sample)([^a-z]|$)/)return "Prototype/Beta/Demo";if(s~/\((rev|revision)[[:space:]._-]*[0-9a-z]+\)/||s~/\[(rev|revision)[[:space:]._-]*[0-9a-z]+\]/)return "Revision";if(s~/\((unl|unlicensed|homebrew|aftermarket)\)/||s~/\[(unl|unlicensed|homebrew|aftermarket)\]/||s~/ homebrew /||s~/ aftermarket /)return "Homebrew/Unlicensed";if(s~/\[t[^]]*\]/||s~/\(translation/||s~/\(translated/||s~/\(eng\)/||s~/\(english/||s~/translation/||s~/english patched/)return "Translation";if(s~/\[h[^]]*\]/||s~/\(hack/||s~/\(hacked/||s~/\(improvement/||s~/\(redux/||s~/\(randomizer/||s~/ hack /||s~/ improvement /||s~/ randomizer /)return "Hack/Modified";return "Retail/Standard"}
 function clean_title(stem, s,old){s=stem;do{old=s;gsub(/[[:space:]]+\((USA|US|U|World|W|Europe|EUR|E|Japan|JPN|J|Canada|CAN|Australia|AUS|Korea|KOR|Brazil|BRA|UE|U,E|U\+E)\)/,"",s);gsub(/[[:space:]]+\((Rev(ision)?[[:space:]._-]*[0-9A-Za-z]+|Proto(type)?|Beta|Demo|Sample|Unl(icensed)?|Homebrew|Aftermarket|Translation|Translated|Eng(lish)?[^)]*)\)/,"",s);gsub(/[[:space:]]+\[([tThH][^]]*|!|[bBoOfFpPaA][0-9]*|[cCxX])\]/,"",s)}while(s!=old);s=trimv(s);gsub(/[[:space:]][[:space:]]+/," ",s);sub(/[[:space:]]+[-_]$/,"",s);s=trimv(s);if(s=="")s=stem;return s}
 NR==1{next}{nf=csv_parse($0,f);if(nf<21)next;processed++;if(heartbeat>0&&processed%heartbeat==0)print "  Processed " processed " / " total " catalog rows...">"/dev/stderr";sysname=tolower(f[1]);original=f[5];proposed=f[6];rowpath=f[7];collision_status=f[9];dat_status=f[11];ext=original;sub(/^.*\./,"",ext);ext=tolower(ext);stem=original;sub(/\.[^.]*$/,"",stem);region=region_of(stem);kind=kind_of(stem);clean=clean_title(stem);suffix="";if(region!="USA"&&region!="Unknown")suffix=" [" region "]";if(region=="Unknown")suffix=" [Unknown Region]";if(kind!="Retail/Standard")suffix=suffix " [" kind "]";fallback=clean suffix "." ext;g=sysname "|" tolower(fallback);pre=(collision_status!="None"&&collision_status!="");authoritative=(dat_status=="Exact SHA-1"||dat_status=="Normalized SHA-1")?1:0;target=sysname "|" tolower(proposed);r++;paths[r]=rowpath;groups[r]=g;pres[r]=pre;targets[r]=target;final_count[target]++;if(pre){group_rows[g]++;group_auth[g]+=authoritative;gt=g SUBSEP target;group_target_count[gt]++;if(group_target_count[gt]>1)group_duplicate[g]=1}}
 END{print "  Processed " processed " / " total " catalog rows.">"/dev/stderr";print "">"/dev/stderr";print "[" resolve_stage "] Resolving global collision groups...">"/dev/stderr";for(i=1;i<=r;i++){g=groups[i];target=targets[i];pre=pres[i];safe=(!pre)||(group_auth[g]==group_rows[g]&&!group_duplicate[g]);if(final_count[target]>1)print paths[i] "\tblocking collision: duplicate final target";else if(pre&&!safe)print paths[i] "\tblocking collision: unresolved pre-DAT group"}}
 ' "$CATALOG">"$BLOCKLIST"||{ echo "ERROR: Collision safety classification failed."; return 1; }; echo "  Collision safety map complete: $(wc -l <"$BLOCKLIST") blocking rows."
}
build_plan(){
 :>"$PLAN"; :>"$SKIPS"; printf 'type\told_path\tnew_path\n'>"$PLAN"; printf 'type\tpath\treason\n'>"$SKIPS"; declare -A TARGETS BLOCKED_GAMES; local line old proposed new dir ext type block_path block_reason game_path processed=0 total=0
 classify_blocking_games||return 1; while IFS=$'\t' read -r block_path block_reason;do [[ -n "$block_path" ]]&&BLOCKED_GAMES["$block_path"]="$block_reason";done<"$BLOCKLIST"
 [[ -f "$GAME_CSV" ]]||{ echo "Missing $GAME_CSV"; return 1; }; total=$(( $(wc -l <"$GAME_CSV")-1)); ((total<0))&&total=0; stage "$STAGE_GAME" "Building safe game rename plan..."; echo "  Game proposals: $total"
 while IFS= read -r line||[[ -n "$line" ]];do [[ "$line" == '"system"'* ]]&&continue; parse_csv "$line"; processed=$((processed+1)); ((processed%HEARTBEAT_EVERY==0))&&echo "  Processed $processed / $total game proposals..."; old="${CSV_FIELDS[1]}"; proposed="${CSV_FIELDS[2]}"; type=GAME; if [[ -n "${BLOCKED_GAMES["$old"]+x}" ]];then printf '%s\t%s\t%s\n' "$type" "$old" "${BLOCKED_GAMES["$old"]}">>"$SKIPS";continue;fi; safe_under "$old" "$GAMES"||{ printf '%s\t%s\t%s\n' "$type" "$old" "outside games root">>"$SKIPS";continue; }; unsafe_name "$proposed"&&{ printf '%s\t%s\t%s\n' "$type" "$old" "unsafe proposed filename">>"$SKIPS";continue; }; ext="${old##*.}";ext="${ext,,}"; [[ "$ext" == cue ]]&&{ printf '%s\t%s\t%s\n' "$type" "$old" "CUE/BIN set rename disabled">>"$SKIPS";continue; }; [[ -e "$old" ]]||{ printf '%s\t%s\t%s\n' "$type" "$old" "source missing">>"$SKIPS";continue; };dir="${old%/*}";new="$dir/$proposed";[[ "$old" == "$new" ]]&&continue;[[ -e "$new" ]]&&{ printf '%s\t%s\t%s\n' "$type" "$old" "target already exists: $new">>"$SKIPS";continue; };[[ -n "${TARGETS["$new"]+x}" ]]&&{ printf '%s\t%s\t%s\n' "$type" "$old" "duplicate proposed target: $new">>"$SKIPS";continue; };TARGETS["$new"]="$old";printf '%s\t%s\t%s\n' "$type" "$old" "$new">>"$PLAN";done<"$GAME_CSV"; echo "  Processed $processed / $total game proposals."
 stage "$STAGE_SAVE" "Building paired save rename plan..."; if [[ -f "$SAVE_CSV" ]];then total=$(( $(wc -l <"$SAVE_CSV")-1));((total<0))&&total=0;processed=0;echo "  Save proposals: $total";while IFS= read -r line||[[ -n "$line" ]];do [[ "$line" == '"system"'* ]]&&continue;parse_csv "$line";processed=$((processed+1));game_path="${CSV_FIELDS[1]}";old="${CSV_FIELDS[2]}";proposed="${CSV_FIELDS[3]}";type=SAVE;if [[ -n "${BLOCKED_GAMES["$game_path"]+x}" ]];then printf '%s\t%s\t%s\n' "$type" "$old" "game rename skipped: ${BLOCKED_GAMES["$game_path"]}">>"$SKIPS";continue;fi;safe_under "$old" "$SAVES"||{ printf '%s\t%s\t%s\n' "$type" "$old" "outside saves root">>"$SKIPS";continue;};unsafe_name "$proposed"&&{ printf '%s\t%s\t%s\n' "$type" "$old" "unsafe proposed filename">>"$SKIPS";continue;};[[ -e "$old" ]]||{ printf '%s\t%s\t%s\n' "$type" "$old" "source missing">>"$SKIPS";continue;};dir="${old%/*}";new="$dir/$proposed";[[ "$old" == "$new" ]]&&continue;[[ -e "$new" ]]&&{ printf '%s\t%s\t%s\n' "$type" "$old" "target already exists: $new">>"$SKIPS";continue;};[[ -n "${TARGETS["$new"]+x}" ]]&&{ printf '%s\t%s\t%s\n' "$type" "$old" "duplicate proposed target: $new">>"$SKIPS";continue;};TARGETS["$new"]="$old";printf '%s\t%s\t%s\n' "$type" "$old" "$new">>"$PLAN";done<"$SAVE_CSV";echo "  Processed $processed / $total save proposals.";else echo "  No save proposal file found; continuing.";fi
}
plan_counts(){ PLAN_N=$(( $(wc -l <"$PLAN" 2>/dev/null)-1)); SKIP_N=$(( $(wc -l <"$SKIPS" 2>/dev/null)-1)); ((PLAN_N<0))&&PLAN_N=0; ((SKIP_N<0))&&SKIP_N=0; COLLISION_N=$(awk -F'\t' 'NR>1&&$3~/^blocking collision:|^game rename skipped: blocking collision:/{n++}END{print n+0}' "$SKIPS" 2>/dev/null); }
write_plan_meta(){ plan_counts; { echo "generated=$(date '+%Y-%m-%d %I:%M:%S %p %Z')"; echo "audit_mode=$(audit_meta audit_mode)"; echo "safe_renames=$PLAN_N"; echo "skipped_items=$SKIP_N"; echo "collision_blocked=$COLLISION_N"; echo "exporter_build=$(audit_meta build_sha1)"; echo "database_sha1=$(audit_meta database_sha1)"; } > "$PLAN_META"; }
meta_value(){ local key="$1"; awk -F= -v k="$key" '$1==k{sub(/^[^=]*=/,"");print;exit}' "$PLAN_META" 2>/dev/null; }
show_plan_summary(){ plan_counts; echo; echo "Safe rename candidates: $PLAN_N"; echo "Skipped/review items: $SKIP_N"; echo "Collision-blocked rows skipped: $COLLISION_N"; echo "Preview: $PLAN"; echo "Skipped: $SKIPS"; }
view_summary(){
 [[ -f "$PLAN" && -f "$SKIPS" ]]||{ echo "No saved preview summary found. Run Preview safe renames first."; return 1; }; plan_counts; local generated mode; generated="$(meta_value generated)"; mode="$(meta_value audit_mode)"
 echo; echo "Last Preview Summary"; echo "===================="; [[ -n "$generated" ]]&&echo "Generated: $generated"; [[ -n "$mode" ]]&&echo "Audit mode: $mode"; echo; printf 'Safe rename candidates:        %s\n' "$PLAN_N"; printf 'Skipped / review items:        %s\n' "$SKIP_N"; printf 'Collision-blocked rows skipped: %s\n' "$COLLISION_N"; echo; echo "Preview file:"; echo "  $PLAN"; echo; echo "Skipped file:"; echo "  $SKIPS"; echo; echo "Press Enter to return."; read -r _
}
review_preview(){
 [[ -f "$PLAN" ]]||{ echo "No saved preview found. Run Preview safe renames first."; return 1; }; local shown=0 type old new n; n=$(( $(wc -l <"$PLAN")-1)); ((n<0))&&n=0
 echo; echo "Last preview"; echo "============"; echo "Safe rename candidates: $n"; echo
 while IFS=$'\t' read -r type old new; do [[ "$type" == type ]]&&continue; shown=$((shown+1)); ((shown>20))&&break; echo "[$shown] $type"; echo "  From:"; echo "    $old"; echo "  To:"; echo "    $new"; echo; done < "$PLAN"
 ((n>20))&&echo "... $((n-20)) more safe renames are listed in $PLAN"; echo; echo "Press Enter to return."; read -r _
}
review_skips(){
 [[ -f "$SKIPS" ]]||{ echo "No saved skipped-item report found. Run Preview safe renames first."; return 1; }; local shown=0 type path reason n; n=$(( $(wc -l <"$SKIPS")-1)); ((n<0))&&n=0
 echo; echo "Skipped / review items"; echo "======================"; echo "Items: $n"; echo
 while IFS=$'\t' read -r type path reason; do [[ "$type" == type ]]&&continue; shown=$((shown+1)); ((shown>20))&&break; echo "[$shown] $type"; echo "  File:"; echo "    $path"; echo "  Reason:"; echo "    $reason"; echo; done < "$SKIPS"
 ((n>20))&&echo "... $((n-20)) more skipped items are listed in $SKIPS"; echo; echo "Press Enter to return."; read -r _
}
preview(){ STAGE_COLLISION="2/6";STAGE_RESOLVE="3/6";STAGE_GAME="4/6";STAGE_SAVE="5/6";stage "1/6" "Validating audit compatibility...";validate_audit preview||return 1;build_plan||return 1;write_plan_meta;stage "6/6" "Finalizing preview...";show_plan_summary;echo;echo "Preview complete.";echo "Press Enter to review the last preview, or Ctrl+C to close.";read -r _;review_preview; }
apply_plan(){ STAGE_COLLISION="2/8";STAGE_RESOLVE="3/8";STAGE_GAME="4/8";STAGE_SAVE="5/8";stage "1/8" "Validating audit compatibility...";validate_audit apply||return 1;build_plan||return 1;write_plan_meta;stage "6/8" "Reviewing safe rename plan...";local n stamp manifest type old new;n=$(( $(wc -l <"$PLAN")-1));((n>0))||{ echo "Nothing safe to rename.";return 0;};show_plan_summary;echo;echo "This will rename $n safe files. Collision-blocked rows and their saves remain untouched.";echo "Type APPLY exactly to continue:";read -r confirm;[[ "$confirm" == APPLY ]]||{ echo "Cancelled.";return 0;};stage "7/8" "Revalidating and rebuilding safe plan...";validate_audit apply||return 1;STAGE_COLLISION="7a/8";STAGE_RESOLVE="7b/8";STAGE_GAME="7c/8";STAGE_SAVE="7d/8";build_plan||return 1;write_plan_meta;stage "8/8" "Applying safe renames and writing rollback manifest...";stamp=$(date +%Y%m%d-%H%M%S);manifest="$HISTORY/rename-$stamp.tsv";printf 'type\told_path\tnew_path\tresult\n'>"$manifest";tail -n +2 "$PLAN"|while IFS=$'\t' read -r type old new;do if [[ -e "$old" && ! -e "$new" ]];then if mv -- "$old" "$new";then printf '%s\t%s\t%s\tOK\n' "$type" "$old" "$new">>"$manifest";else printf '%s\t%s\t%s\tFAILED\n' "$type" "$old" "$new">>"$manifest";fi;else printf '%s\t%s\t%s\tSKIPPED_AT_APPLY\n' "$type" "$old" "$new">>"$manifest";fi;done;cp "$manifest" "$HISTORY/last_manifest.tsv";echo "Finished. Rollback manifest: $manifest"; }
rollback(){ local manifest="$HISTORY/last_manifest.tsv" type old new result;[[ -f "$manifest" ]]||{ echo "No last rollback manifest found.";return 1;};echo "Rollback will restore successful renames from:";echo "$manifest";echo "Type ROLLBACK exactly to continue:";read -r confirm;[[ "$confirm" == ROLLBACK ]]||{ echo "Cancelled.";return 0;};tail -n +2 "$manifest"|tac|while IFS=$'\t' read -r type old new result;do [[ "$result" == OK ]]||continue;if [[ -e "$new" && ! -e "$old" ]];then mv -- "$new" "$old"||echo "FAILED: $new";else echo "SKIP: cannot safely restore $old";fi;done;echo "Rollback pass finished. Re-run the auditor to verify the library."; }
echo "MiSTer ROM Library Updater v1.4";echo "=================================";echo "Updater build: $UPDATER_BUILD";echo "Script path:   $0";echo "1) Preview safe renames";echo "2) Apply safe renames (blocking collisions auto-skipped)";echo "3) View last preview summary";echo "4) Review last preview";echo "5) Review skipped items";echo "6) Roll back last applied cleanup";echo "7) Exit";read -r choice;case "$choice" in 1)preview;;2)apply_plan;;3)view_summary;;4)review_preview;;5)review_skips;;6)rollback;;*)exit 0;;esac

}

main_menu() {
  while :; do
    echo
    echo "MiSTer ROM Library Auditor v1.4"
    echo "================================"
    echo "1) Run library audit"
    echo "2) Preview / Apply / Rollback"
    echo "3) Exit"
    read -r choice
    case "$choice" in
      1) run_audit; trap - EXIT INT TERM ;;
      2)
        echo
        echo "WARNING: Preview / Apply / Rollback can make changes to your game and save library."
        echo "Apply can rename files, and Rollback can reverse previously applied changes."
        echo "Run an audit and review the preview before applying changes."
        echo
        echo "1) Back [default]"
        echo "2) Continue"
        read -r update_choice
        case "${update_choice:-1}" in
          2) run_update_tools; trap - EXIT INT TERM ;;
          *) continue ;;
        esac
        ;;
      3|*) exit 0 ;;
    esac
  done
}

case "${1:-}" in
  audit) run_audit ;;
  update|rename) run_update_tools ;;
  *) main_menu ;;
esac
\t' read -r -u 3 system p file ext stem clean region kind sig fallback_proposed; do
  [ -z "$p" ] && continue
  row_metadata_reused=0
  proposed="${fallback_proposed:-}"; if [ -z "$proposed" ]; then suffix_for_set "$region" "$kind"; suffix="$HOT_RESULT"; proposed="$clean$suffix.$ext"; fi; base="${proposed%.$ext}"; key="${system,,}|${proposed,,}"; collision="None"; pre_collision=0
  if [ "${NAME_COUNTS["$key"]:-0}" -gt 1 ]; then pre_collision=1; PRE_COLLISION_ROWS=$((PRE_COLLISION_ROWS+1)); n=$(( ${SEEN_NAMES["$key"]:-0} + 1 )); SEEN_NAMES["$key"]=$n; proposed="$base [Variant $n].$ext"; collision="Pending final-target review"; fi
  row_seconds_start=$SECONDS; SYSTEM_FILES["$system"]=$(( ${SYSTEM_FILES["$system"]:-0} + 1 ))
  sha1=""; dat_status="Not applicable"; dat_name=""; dat_rom=""; dat_source=""; meta_system=""; meta_core=""; meta_folder=""; meta_region=""; meta_release=""; meta_license=""; loc_status="Unknown"
  if should_hash "$system" "$ext"; then
    HASH_ELIGIBLE=$((HASH_ELIGIBLE+1)); SYSTEM_ELIGIBLE["$system"]=$(( ${SYSTEM_ELIGIBLE["$system"]:-0} + 1 )); cache_key="$p|$sig"; cached_sha=""; cached_normalized_sha=""; if [ "$USE_HASH_CACHE" -eq 1 ]; then cached_sha="${CACHE_SHA[$cache_key]:-}"; cached_normalized_sha="${CACHE_NORMALIZED_SHA[$cache_key]:-}"; fi
    if [ -n "$cached_sha" ]; then
      sha1="$cached_sha"; HASH_REUSED=$((HASH_REUSED+1))
      if [ -n "${CACHE_DAT_STATUS[$cache_key]+x}" ]; then
        dat_status="${CACHE_DAT_STATUS[$cache_key]}"; dat_name="${CACHE_DAT_NAME[$cache_key]:-}"; dat_rom="${CACHE_DAT_ROM[$cache_key]:-}"; dat_source="${CACHE_DAT_SOURCE[$cache_key]:-}"
        meta_system="${CACHE_META_SYSTEM[$cache_key]:-}"; meta_core="${CACHE_META_CORE[$cache_key]:-}"; meta_folder="${CACHE_META_FOLDER[$cache_key]:-}"; meta_region="${CACHE_META_REGION[$cache_key]:-}"; meta_release="${CACHE_META_RELEASE[$cache_key]:-}"; meta_license="${CACHE_META_LICENSE[$cache_key]:-}"
        if [ -n "${CACHE_RESOLVED_PROPOSED[$cache_key]+x}" ]; then clean="${CACHE_RESOLVED_CLEAN[$cache_key]:-$clean}"; region="${CACHE_RESOLVED_REGION[$cache_key]:-$region}"; kind="${CACHE_RESOLVED_KIND[$cache_key]:-$kind}"; proposed="${CACHE_RESOLVED_PROPOSED[$cache_key]:-$proposed}"; loc_status="${CACHE_LOCATION_STATUS[$cache_key]:-Unknown}"; ROW_METADATA_REUSED=$((ROW_METADATA_REUSED+1)); fi
      else
        dat_status="No match"
      fi
    else
      if [ "$USE_HASH_CACHE" -eq 0 ] && [ -n "${PREHASH_SHA_BY_PATH[$p]:-}" ]; then sha1="${PREHASH_SHA_BY_PATH[$p]}"; else sha1="$(hash_file "$p")"; fi
      [ -n "$sha1" ] && [ "$sha1" != "UNAVAILABLE" ] && HASH_CALCULATED=$((HASH_CALCULATED+1)); dat_status="No match"
    fi
  else HASH_SKIPPED=$((HASH_SKIPPED+1)); fi
  if [ -n "$sha1" ] && [ "$sha1" != "UNAVAILABLE" ]; then
    HASHED=$((HASHED+1)); printf '%s\t%s\t%s\t%s\t%s\n' "${sha1,,}" "$system" "$p" "$file" "$clean" >&17; hkey="${sha1,,}"; file_size="${sig%%|*}"; if [ -n "$cached_normalized_sha" ]; then matched_hkey="${cached_normalized_sha,,}"; elif [ -n "${DAT_RECORD_BY_SHA[$hkey]+x}" ]; then matched_hkey="$hkey"; else matched_hkey="$(normalized_dat_hash "$p" "$ext" "$hkey" "$file_size")"; fi; if [ "$matched_hkey" != "$hkey" ]; then hkey="$matched_hkey"; sha1="$matched_hkey"; dat_status="Normalized SHA-1"; fi
    if [ -n "${DAT_RECORD_BY_SHA[$hkey]+x}" ]; then
      if [ "$ROW_METADATA_REUSED" -eq 0 ] || [ -z "${CACHE_RESOLVED_PROPOSED[$cache_key]+x}" ]; then
        dat_unpack "${DAT_RECORD_BY_SHA[$hkey]}"; dat_name="$DAT_TITLE"; dat_rom="$DAT_ROM"; dat_source="$DAT_SOURCE"; meta_system="$DAT_SYSTEM"; meta_core="$DAT_CORE"; meta_folder="$DAT_FOLDER"; meta_region="$DAT_REGION"; meta_release="$DAT_RELEASE"; meta_license="$DAT_LICENSE"
      fi
      if [ -n "${CACHE_RESOLVED_PROPOSED[$cache_key]+x}" ] && [ "$USE_HASH_CACHE" -eq 1 ]; then
        : # Fast Audit already restored DB-derived row metadata from the fingerprint-bound cache.
      elif [ -n "$dat_rom" ]; then canonical_file="${dat_rom##*/}"; canonical_stem="${canonical_file%.*}"; [ -n "$canonical_stem" ] && { clean_title_set "$canonical_stem"; clean="$HOT_RESULT"; }; [ -n "$meta_region" ] && region="$meta_region"; [ -n "$meta_release" ] && kind="$meta_release"; proposed="$canonical_file"; elif [ -n "$dat_name" ]; then clean="$(clean_title "$dat_name")"; [ -n "$meta_region" ] && region="$meta_region"; [ -n "$meta_release" ] && kind="$meta_release"; suffix_for_set "$region" "$kind"; proposed="$clean$HOT_RESULT.$ext"; fi
      if [ -z "${CACHE_RESOLVED_PROPOSED[$cache_key]+x}" ] || [ "$USE_HASH_CACHE" -eq 0 ]; then location_status_set "$system" "$meta_folder"; loc_status="$HOT_RESULT"; ROW_METADATA_REFRESHED=$((ROW_METADATA_REFRESHED+1)); fi; record_completion_owned "${meta_system:-$system}" "$dat_name" "$meta_region" "$meta_release" "$meta_license"; [ "$dat_status" = "Normalized SHA-1" ] || dat_status="Exact SHA-1"; DAT_MATCHED=$((DAT_MATCHED+1)); SYSTEM_MATCHED["$system"]=$(( ${SYSTEM_MATCHED["$system"]:-0} + 1 ))
      csv_row "$STAGE_DAT_MATCH" "$sha1" "$system" "$p" "$file" "$dat_name" "$dat_rom" "$dat_source" "$meta_system" "$meta_core" "$meta_folder" "$meta_region" "$meta_release" "$meta_license"
      csv_row "$STAGE_LOCATION_AUDIT" "$system" "$p" "$dat_name" "$meta_system" "$meta_core" "$meta_folder" "$loc_status"
    else SYSTEM_UNMATCHED["$system"]=$(( ${SYSTEM_UNMATCHED["$system"]:-0} + 1 )); unmatched_class="$(expected_unmatched_class "$file" "$kind")"; csv_row "$STAGE_DAT_UNMATCHED" "$sha1" "$system" "$p" "$file" "$unmatched_class"; fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$p" "$sig" "${sha1,,}" "${matched_hkey:-${sha1,,}}" "$dat_status" "$dat_name" "$dat_rom" "$dat_source" "$meta_system" "$meta_core" "$meta_folder" "$meta_region" "$meta_release" "$meta_license" "$clean" "$region" "$kind" "$proposed" "$loc_status" >&20
  fi

  # Collision planning is actionable only for DAT-identified ROMs. Unmatched ROMs
  # remain visible in inventory/unmatched reports but are not rename candidates, so
  # their filename-derived fallback targets must not block Preview.
  authoritative=0; case "$dat_status" in "Exact SHA-1"|"Normalized SHA-1") [ -n "$proposed" ] && authoritative=1 ;; esac
  if [ "$authoritative" -eq 1 ]; then
    printf '%s\t%s\t%s\t%s\t%s\n' "$p" "$key" "$pre_collision" "$authoritative" "${system,,}|${proposed,,}" >&21
    if [ "$pre_collision" -eq 1 ]; then collision="Canonical DAT variant candidate"; fi
  elif [ "$pre_collision" -eq 1 ]; then
    collision="Inventory only - unmatched ROM"
  fi

  save_count=0; save_key="${stem,,}"
  if [ -n "${SAVES_BY_STEM[$save_key]:-}" ]; then while IFS= read -r sp; do [ -z "$sp" ] && continue; sf="${sp##*/}"; sext="${sf##*.}"; proposed_save="${proposed%.*}.$sext"; csv_row "$STAGE_SAVE_REN" "$system" "$p" "$sp" "$proposed_save" "Exact original basename" "REVIEW ONLY"; save_count=$((save_count+1)); SAVE_MATCHES=$((SAVE_MATCHES+1)); done <<< "${SAVES_BY_STEM[$save_key]}"; fi

  printf '[%s] %s | Region: %s | Type: %s | Saves: %s | File: %s | Collision: %s\n' "$system" "$clean" "$region" "$kind" "$save_count" "$file" "$collision" >> "$STAGE_OUT"
  csv_row "$STAGE_CSV" "$system" "$clean" "$region" "$kind" "$file" "$proposed" "$p" "$save_count" "$collision" "$sha1" "$dat_status" "$dat_name" "$dat_rom" "$dat_source" "$meta_system" "$meta_core" "$meta_folder" "$meta_region" "$meta_release" "$meta_license" "$loc_status"
  csv_row "$STAGE_REN" "$system" "$p" "$proposed" "$region" "$kind" "REVIEW ONLY"
  TOTAL=$((TOTAL+1)); SYSTEM_SECONDS["$system"]=$(( ${SYSTEM_SECONDS["$system"]:-0} + SECONDS - row_seconds_start )); progress_check "Building reports" "$TOTAL" "$PLAN_TOTAL"
done
exec 3<&-
exec 17>&- 20>&- 21>&-

# Issue #7: evaluate both pre-DAT groups and duplicate final targets.
if [ -s "$COLLISION_ROWS" ]; then
  read -r COLLISIONS RESOLVED_COLLISIONS < <(awk -F '\t' '
    { group[NR]=$2; pre[NR]=$3+0; auth[NR]=$4+0; target[NR]=$5; final_count[$5]++; if(pre[NR]){group_rows[$2]++;group_auth[$2]+=auth[NR];group_target[$2 SUBSEP $5]++} }
    END {
      for(g in group_rows){duplicate=0;prefix=g SUBSEP;for(k in group_target)if(index(k,prefix)==1&&group_target[k]>1){duplicate=1;break};group_safe[g]=(group_auth[g]==group_rows[g]&&!duplicate)}
      blocking=0;resolved=0
      for(i=1;i<=NR;i++){is_blocking=(final_count[target[i]]>1)||(pre[i]&&!group_safe[group[i]]);if(is_blocking)blocking++;else if(pre[i])resolved++}
      print blocking,resolved
    }' "$COLLISION_ROWS")
  COLLISIONS=${COLLISIONS:-0}; RESOLVED_COLLISIONS=${RESOLVED_COLLISIONS:-0}
fi

COMPLETION_REGION_LABEL="$(IFS=', '; echo "${COMPLETION_REGIONS[*]}")"
printf '%s\n' '"system","owned_titles","reference_titles","missing_titles","completion_percent","regions","scope"' > "$STAGE_COMPLETION"
printf '%s\n' '"system","canonical_title","region","release_type","license_status"' > "$STAGE_MISSING_COMPLETION"
while IFS= read -r c_sys; do [ -n "$c_sys" ] || continue; present_matches=0; for present_sys in "${!SYSTEM_MATCHED[@]}"; do [ "$(canonical_dat_system "$present_sys")" = "$c_sys" ] && present_matches=$((present_matches + ${SYSTEM_MATCHED[$present_sys]:-0})); done; [ "$present_matches" -gt 0 ] || continue; c_total="${COMPLETION_TOTAL_BY_SYSTEM[$c_sys]:-0}"; c_owned="${COMPLETION_OWNED_BY_SYSTEM[$c_sys]:-0}"; c_missing=$((c_total-c_owned)); c_pct="$(awk -v a="$c_owned" -v b="$c_total" 'BEGIN{if(b>0) printf "%.2f", (a*100)/b; else printf "0.00"}')"; if [ "$COMPLETION_RETAIL_ONLY" -eq 1 ]; then c_scope="Retail releases"; else c_scope="All release types"; fi; csv_row "$STAGE_COMPLETION" "$c_sys" "$c_owned" "$c_total" "$c_missing" "$c_pct" "$COMPLETION_REGION_LABEL" "$c_scope"; done < <(printf '%s\n' "${!COMPLETION_TOTAL_BY_SYSTEM[@]}" | LC_ALL=C sort)
for c_key in "${!COMPLETION_REFERENCE_KEYS[@]}"; do [ -n "${COMPLETION_OWNED_KEYS[$c_key]+x}" ] && continue; c_sys="${c_key%%|*}"; present_matches=0; for present_sys in "${!SYSTEM_MATCHED[@]}"; do [ "$(canonical_dat_system "$present_sys")" = "$c_sys" ] && present_matches=$((present_matches + ${SYSTEM_MATCHED[$present_sys]:-0})); done; [ "$present_matches" -gt 0 ] || continue; c_title="${c_key#*|}"; csv_row "$STAGE_MISSING_COMPLETION" "$c_sys" "$c_title" "${COMPLETION_TITLE_REGION[$c_key]:-}" "${COMPLETION_TITLE_RELEASE[$c_key]:-}" "${COMPLETION_TITLE_LICENSE[$c_key]:-}"; done
{ head -n 1 "$STAGE_MISSING_COMPLETION"; tail -n +2 "$STAGE_MISSING_COMPLETION" | LC_ALL=C sort; } > "$STAGE_MISSING_COMPLETION.tmp" && mv -f "$STAGE_MISSING_COMPLETION.tmp" "$STAGE_MISSING_COMPLETION"

CACHE_REFRESHED=$HASH_CALCULATED; CACHE_NOT_REUSED=$(( CACHE_ENTRIES_LOADED > HASH_REUSED ? CACHE_ENTRIES_LOADED - HASH_REUSED : 0 )); CACHE_HIT_RATE="0.0"; if [ "$HASH_ELIGIBLE" -gt 0 ]; then CACHE_HIT_RATE=$(awk -v a="$HASH_REUSED" -v b="$HASH_ELIGIBLE" 'BEGIN{printf "%.1f", (a*100)/b}'); fi
if [ -s "$HASH_CACHE_NEW" ]; then mv -f "$HASH_CACHE_NEW" "$HASH_CACHE"; else : > "$HASH_CACHE"; fi
{ echo "CACHE_FORMAT=$CACHE_FORMAT"; echo "EXPORTER_VERSION=1.4"; echo "HASH_DB_FINGERPRINT=$HASH_DB_FINGERPRINT"; echo "UPDATED=$(date +%s)"; } > "$CACHE_META.tmp" && mv -f "$CACHE_META.tmp" "$CACHE_META"
if [ -s "$HASH_ROWS" ]; then awk -F '\t' '{c[$1]++} END {for (h in c) if (c[h]>1) print h}' "$HASH_ROWS" | sort > "$WORK.duphashes"; while IFS= read -r dh; do awk -F '\t' -v k="$dh" '$1==k {print}' "$HASH_ROWS" | while IFS=$'\t' read -r h hs hp hf hc; do csv_escape "$h" >> "$STAGE_HASH_DUP"; printf ',' >> "$STAGE_HASH_DUP"; csv_escape "$hs" >> "$STAGE_HASH_DUP"; printf ',' >> "$STAGE_HASH_DUP"; csv_escape "$hp" >> "$STAGE_HASH_DUP"; printf ',' >> "$STAGE_HASH_DUP"; csv_escape "$hf" >> "$STAGE_HASH_DUP"; printf ',' >> "$STAGE_HASH_DUP"; csv_escape "$hc" >> "$STAGE_HASH_DUP"; printf '\n' >> "$STAGE_HASH_DUP"; done; done < "$WORK.duphashes"; rm -f "$WORK.duphashes"; fi

cat >> "$STAGE_OUT" <<EOF2

============================================================
Candidate game/disc files: $TOTAL
BIOS/support files skipped: $SKIPPED
Pre-DAT collision rows: $PRE_COLLISION_ROWS
Canonical DAT variant rows resolved safely: $RESOLVED_COLLISIONS
Blocking collision rows: $COLLISIONS
Corresponding save-file matches found: $SAVE_MATCHES
Files with SHA-1 available: $HASHED
Hashes reused from cache: $HASH_REUSED
Hashes calculated this run: $HASH_CALCULATED
Unsupported-format hashes skipped: $HASH_SKIPPED
Hash database source: $HASH_DB_SOURCE
Hash records indexed: $HASH_INDEX_COUNT
Exact DAT SHA-1 matches: $DAT_MATCHED

Created in $AUDIT:
  game_library.txt
  library_catalog.csv
  proposed_renames.csv
  proposed_save_renames.csv
  hash_duplicates.csv
  dat_matches.csv
  unmatched_hashes.csv
  library_completion.csv
  missing_library_titles.csv
  MiSTer_Library_Audit.txt  (single file to upload for review)

IMPORTANT:
- Nothing was renamed, moved, or deleted.
- Exact DAT matches use canonical DAT filenames; filename parsing is fallback-only for unmatched ROMs.
- Pre-DAT filename collisions are blocking only when final canonical targets remain ambiguous.
- Authoritative DAT variants with unique final targets are reported as resolved and do not block Preview.
- Unmatched/unsupported ROMs are inventory-only and do not participate in rename collision planning.
- Duplicate authoritative canonical targets remain blocking.
- Save matching still uses the original ROM basename and remains REVIEW ONLY.
- SHA-1 hashes identify byte-for-byte duplicate files regardless of filename.
- CUE/BIN and other multi-file disc sets require coordinated renaming before any future apply step.
EOF2

AUDIT_VERDICT="PASS"; APPLY_RECOMMENDATION="SAFE TO PREVIEW"; INTEGRITY_NOTES=""; MISFILED_COUNT=0
[ -s "$STAGE_LOCATION_AUDIT" ] && MISFILED_COUNT=$(grep -c ',"MISFILED"$' "$STAGE_LOCATION_AUDIT" 2>/dev/null || true)
for required_report in "$STAGE_OUT" "$STAGE_CSV" "$STAGE_REN" "$STAGE_SAVE_REN" "$STAGE_HASH_DUP" "$STAGE_DAT_MATCH" "$STAGE_DAT_UNMATCHED" "$STAGE_LOCATION_AUDIT"; do if [ ! -f "$required_report" ]; then AUDIT_VERDICT="FAIL"; APPLY_RECOMMENDATION="DO NOT APPLY"; INTEGRITY_NOTES="$INTEGRITY_NOTES missing-report:${required_report##*/}"; fi; done
if [ "$TOTAL" -ne "$CLASSIFIED" ] 2>/dev/null; then AUDIT_VERDICT="FAIL"; APPLY_RECOMMENDATION="DO NOT APPLY"; INTEGRITY_NOTES="$INTEGRITY_NOTES catalog-count-mismatch"; fi
if [ $((TOTAL + SKIPPED)) -ne "$GAME_SCAN_COUNT" ] 2>/dev/null; then AUDIT_VERDICT="FAIL"; APPLY_RECOMMENDATION="DO NOT APPLY"; INTEGRITY_NOTES="$INTEGRITY_NOTES discovery-accounting-mismatch"; fi
if [ "$DAT_MATCHED" -gt "$HASHED" ] 2>/dev/null; then AUDIT_VERDICT="FAIL"; APPLY_RECOMMENDATION="DO NOT APPLY"; INTEGRITY_NOTES="$INTEGRITY_NOTES impossible-dat-count"; fi
if [ "$METADATA_LAYER_STATUS" != "MiSTer-aware" ]; then AUDIT_VERDICT="FAIL"; APPLY_RECOMMENDATION="DO NOT APPLY"; INTEGRITY_NOTES="$INTEGRITY_NOTES metadata-layer-invalid"; fi
MATCH_RATE_INT=100; if [ "$HASHED" -gt 0 ]; then MATCH_RATE_INT=$((DAT_MATCHED * 100 / HASHED)); fi
if [ "$AUDIT_VERDICT" != "FAIL" ]; then
  if [ "$MATCH_RATE_INT" -lt 50 ]; then AUDIT_VERDICT="PASS WITH WARNINGS"; APPLY_RECOMMENDATION="DO NOT APPLY"; INTEGRITY_NOTES="$INTEGRITY_NOTES low-dat-match-rate"; fi
  if [ "$COLLISIONS" -gt 0 ]; then AUDIT_VERDICT="PASS WITH WARNINGS"; INTEGRITY_NOTES="$INTEGRITY_NOTES collision-rows-will-be-skipped"; [ "$APPLY_RECOMMENDATION" != "DO NOT APPLY" ] && APPLY_RECOMMENDATION="SAFE TO PREVIEW (COLLISIONS SKIPPED)"; fi
fi
[ -z "$INTEGRITY_NOTES" ] && INTEGRITY_NOTES="none"

{
  echo "MiSTer Game Library Audit Bundle v1.4"; echo "Generated: $(date)"; echo "READ-ONLY AUDIT REPORT - no ROM or save data is embedded."; echo "FULL LIBRARY REPORT - audit mode: $AUDIT_MODE."; echo "============================================================"; echo; echo "[RUN SUMMARY]"; echo "Report scope: FULL LIBRARY"; echo "Audit mode: $AUDIT_MODE"; echo "Cache mode: $([ "$USE_HASH_CACHE" -eq 1 ] && echo "Incremental processing only" || echo "Bypassed for hash verification")"; echo "Files discovered: $GAME_SCAN_COUNT"; echo "Games/discs cataloged: $TOTAL"; echo "BIOS/support files skipped: $SKIPPED"; echo "Pre-DAT collision rows: $PRE_COLLISION_ROWS"; echo "Canonical DAT variant rows resolved safely: $RESOLVED_COLLISIONS"; echo "Blocking collision rows: $COLLISIONS"; echo "Save matches: $SAVE_MATCHES"; echo "Files with SHA-1 available: $HASHED"; echo "Hashes reused from cache: $HASH_REUSED"; echo "Hashes calculated this run: $HASH_CALCULATED"; echo "Unsupported-format hashes skipped: $HASH_SKIPPED"; echo "Hash database source: $HASH_DB_SOURCE"; echo "MiSTer-aware metadata layer: $METADATA_LAYER_STATUS"; echo "Exporter build SHA-1: $RUNTIME_BUILD_SHA1"; echo "Audit integrity verdict: $AUDIT_VERDICT"; echo "Apply recommendation: $APPLY_RECOMMENDATION"; echo "Hash records indexed: $HASH_INDEX_COUNT"; echo "Persistent DAT index: ${DAT_CACHE_STATUS:-Unavailable}"; echo "Hash records skipped for absent systems: ${HASH_DB_SKIPPED_SYSTEM_RECORDS:-0}"; echo "Exact DAT SHA-1 matches: $DAT_MATCHED"; echo; echo "[AUDIT_METADATA]"; echo "schema_version=$AUDIT_SCHEMA_VERSION"; echo "exporter_version=1.4"; echo "build_sha1=$RUNTIME_BUILD_SHA1"; echo "audit_mode=$AUDIT_MODE"; echo "database_sha1=$HASH_DB_FINGERPRINT"; echo "metadata_layer=$METADATA_LAYER_STATUS"; echo "library_files=$GAME_SCAN_COUNT"; echo "cataloged_files=$TOTAL"; echo "self_check=$SELF_CHECK_STATUS"; echo "integrity_verdict=$AUDIT_VERDICT"; echo "apply_recommendation=$APPLY_RECOMMENDATION"; echo "integrity_notes=$INTEGRITY_NOTES"; echo; echo "[DATABASE COVERAGE]"; echo "DAT-eligible ROMs: $HASH_ELIGIBLE"; echo "Matched: $DAT_MATCHED"; echo "Unmatched: $((HASHED-DAT_MATCHED))"; if [ "$HASHED" -gt 0 ]; then awk -v a="$DAT_MATCHED" -v b="$HASHED" 'BEGIN{printf "Match rate: %.2f%%\n", (a*100)/b}'; else echo "Match rate: 0.00%"; fi; echo "Other/unsupported files cataloged: $HASH_SKIPPED"; echo; echo "[LIBRARY COMPLETION]"; echo "Regions: $COMPLETION_REGION_LABEL"; if [ "$COMPLETION_RETAIL_ONLY" -eq 1 ]; then echo "Scope: Retail releases only"; else echo "Scope: All release types"; fi; echo "World releases count toward USA, Europe, and Japan when COMPLETION_INCLUDE_WORLD=1."; tail -n +2 "$STAGE_COMPLETION" | while IFS=',' read -r c_sys c_owned c_total c_missing c_pct rest; do c_sys="${c_sys#\"}"; c_sys="${c_sys%\"}"; c_owned="${c_owned#\"}"; c_owned="${c_owned%\"}"; c_total="${c_total#\"}"; c_total="${c_total%\"}"; c_missing="${c_missing#\"}"; c_missing="${c_missing%\"}"; c_pct="${c_pct#\"}"; c_pct="${c_pct%\"}"; echo "$c_sys | owned=$c_owned | reference=$c_total | missing=$c_missing | completion=$c_pct%"; done; echo "Missing-title detail: missing_library_titles.csv"; echo; echo "[CACHE HEALTH]"; echo "Entries loaded: $CACHE_ENTRIES_LOADED"; echo "Entries reused: $HASH_REUSED"; echo "Unchanged library records: $DISCOVERY_UNCHANGED"; echo "New library records: $DISCOVERY_ADDED"; echo "Modified library records: $((DISCOVERY_CHANGED_COUNT-DISCOVERY_ADDED))"; echo "Deleted library records: $DISCOVERY_REMOVED"; echo "Delta records analyzed: $DISCOVERY_CHANGED_COUNT"; echo "Classification entries loaded: $CLASS_CACHE_ENTRIES_LOADED"; echo "Classification hits: $CLASS_CACHE_HITS"; echo "Classification misses/refreshed: $CLASS_CACHE_MISSES"; echo "DAT/classification row metadata reused: $ROW_METADATA_REUSED"; echo "DAT/classification row metadata refreshed: $ROW_METADATA_REFRESHED"; echo "Entries refreshed: $CACHE_REFRESHED"; echo "Entries not reused/expired: $CACHE_NOT_REUSED"; echo "Cache hit rate: $CACHE_HIT_RATE%"; echo "Database fingerprint: $HASH_DB_FINGERPRINT"; echo; echo "[PER-SYSTEM PROCESSING]"; for sys in "${!SYSTEM_FILES[@]}"; do echo "$sys | files=${SYSTEM_FILES[$sys]} | dat_eligible=${SYSTEM_ELIGIBLE[$sys]:-0} | matched=${SYSTEM_MATCHED[$sys]:-0} | unmatched=${SYSTEM_UNMATCHED[$sys]:-0} | processing_seconds=${SYSTEM_SECONDS[$sys]:-0}"; done | LC_ALL=C sort; echo; echo "[TIMING]"; echo "discovery_seconds=$((DISCOVERY_END-DISCOVERY_START))"; echo "save_index_seconds=$((SAVE_END-SAVE_START))"; echo "database_cache_seconds=$((DB_END-DB_START))"; echo "classification_seconds=$((CLASSIFY_END-CLASSIFY_START))"; echo "parallel_full_verify_hash_seconds=$FULL_VERIFY_PARALLEL_SECONDS"; echo "report_processing_seconds=$(( $(date +%s)-REPORT_START ))"; echo "total_seconds_so_far=$(( $(date +%s)-START_TIME ))"; echo
  for report in game_library.txt library_catalog.csv dat_matches.csv unmatched_hashes.csv hash_duplicates.csv location_audit.csv library_completion.csv missing_library_titles.csv proposed_renames.csv proposed_save_renames.csv; do echo "============================================================"; echo "[BEGIN $report]"; echo "============================================================"; if [ -f "$STAGE_DIR/$report" ]; then cat "$STAGE_DIR/$report"; else echo "(report not generated)"; fi; echo; echo "[END $report]"; echo; done
} > "$STAGE_BUNDLE"

REPORT_END=$(date +%s); PUBLISH_START=$REPORT_END
for report in game_library.txt library_catalog.csv proposed_renames.csv proposed_save_renames.csv hash_duplicates.csv dat_matches.csv unmatched_hashes.csv location_audit.csv library_completion.csv missing_library_titles.csv MiSTer_Library_Audit.txt; do [ -f "$STAGE_DIR/$report" ] || continue; mv -f "$STAGE_DIR/$report" "$AUDIT/$report"; done
PUBLISH_END=$(date +%s); TOTAL_END=$PUBLISH_END; sync
DISCOVERY_SECONDS=$((DISCOVERY_END-DISCOVERY_START))
SAVE_INDEX_SECONDS=$((SAVE_END-SAVE_START))
DATABASE_CACHE_SECONDS=$((DB_END-DB_START))
CLASSIFICATION_SECONDS=$((CLASSIFY_END-CLASSIFY_START))
REPORT_PROCESSING_SECONDS=$((REPORT_END-REPORT_START))
PUBLISH_SECONDS=$((PUBLISH_END-PUBLISH_START))
TOTAL_SECONDS=$((TOTAL_END-START_TIME))
# Final timing telemetry is appended after atomic publication so the uploaded
# audit contains the same stage timings shown on-screen. This is diagnostic
# metadata only and does not affect audit/rename decisions.
{
  echo
  echo "[FINAL TIMING]"
  echo "discovery_seconds=$DISCOVERY_SECONDS"
  echo "save_index_seconds=$SAVE_INDEX_SECONDS"
  echo "database_cache_seconds=$DATABASE_CACHE_SECONDS"
  echo "classification_seconds=$CLASSIFICATION_SECONDS"
  echo "parallel_full_verify_hash_seconds=$FULL_VERIFY_PARALLEL_SECONDS"
  echo "report_processing_seconds=$REPORT_PROCESSING_SECONDS"
  echo "publish_seconds=$PUBLISH_SECONDS"
  echo "total_seconds=$TOTAL_SECONDS"
} >> "$BUNDLE"
echo; echo "+--------------------------------------------------+"; echo "| AUDIT COMPLETE                                   |"; echo "+--------------------------------------------------+"; echo " Mode              : $AUDIT_MODE"; echo " Games cataloged   : $TOTAL"; echo " DAT matches       : $DAT_MATCHED / $HASHED"; echo " Blocking collisions: $COLLISIONS"; echo " DAT variants safe : $RESOLVED_COLLISIONS"; echo " Save matches      : $SAVE_MATCHES"; echo " Fast delta        : new=$DISCOVERY_ADDED modified=$((DISCOVERY_CHANGED_COUNT-DISCOVERY_ADDED)) deleted=$DISCOVERY_REMOVED"; echo " Cache hit rate    : $CACHE_HIT_RATE%"; echo " Integrity         : $AUDIT_VERDICT"; echo " Apply             : $APPLY_RECOMMENDATION"; echo "----------------------------------------------------"; echo " Timing (seconds)"; echo "   Discovery       : $DISCOVERY_SECONDS"; echo "   Save index      : $SAVE_INDEX_SECONDS"; echo "   Database/cache  : $DATABASE_CACHE_SECONDS"; echo "   Classification  : $CLASSIFICATION_SECONDS"; echo "   Full hash pass  : $FULL_VERIFY_PARALLEL_SECONDS"; echo "   Report processing: $REPORT_PROCESSING_SECONDS"; echo "   Publish         : $PUBLISH_SECONDS"; echo "   TOTAL           : $TOTAL_SECONDS"; echo "----------------------------------------------------"; echo " Reports: $AUDIT"; echo " Review : MiSTer_Library_Audit.txt"; echo " Missing: missing_library_titles.csv"; echo "----------------------------------------------------"; echo " READ ONLY: no ROMs or saves were changed."; echo "----------------------------------------------------"; echo; echo "Press Enter to close, or wait 60 seconds."; read -t 60 -r _ || true

}

run_update_tools() {
# MiSTer-Audit-Update_v1.4.sh
# Companion updater for MiSTer ROM Library Auditor v1.4

ROOT="/media/fat"; GAMES="$ROOT/games"; SAVES="$ROOT/saves"; AUDIT="$ROOT/GameLibraryAudit"
GAME_CSV="$AUDIT/proposed_renames.csv"; SAVE_CSV="$AUDIT/proposed_save_renames.csv"; CATALOG="$AUDIT/library_catalog.csv"; BUNDLE="$AUDIT/MiSTer_Library_Audit.txt"
HISTORY="$AUDIT/RenameHistory"; PLAN="$AUDIT/apply_preview.tsv"; SKIPS="$AUDIT/apply_skipped.tsv"; PLAN_META="$AUDIT/apply_preview.meta"
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"; RUNTIME="$SCRIPT_DIR/MiSTer_Audit.sh"; HASH_DB="$SCRIPT_DIR/mister_hash_database.tsv"
EXPECTED_SCHEMA="4"; EXPECTED_EXPORTER_VERSION="1.4"; BLOCKLIST="/tmp/mister_updater_blocked.$$"; HEARTBEAT_EVERY=500
UPDATER_BUILD="preview-summary-2026-09-13a"
STAGE_PREFIX=""; STAGE_COLLISION=""; STAGE_RESOLVE=""; STAGE_GAME=""; STAGE_SAVE=""
cleanup(){ rm -f "$BLOCKLIST"; }; trap cleanup EXIT INT TERM; mkdir -p "$HISTORY" || exit 1
stage(){ echo; echo "[$1] $2"; }
hash_file(){ local p="$1"; if command -v sha1sum >/dev/null 2>&1; then sha1sum "$p" 2>/dev/null|awk '{print $1}'; elif command -v openssl >/dev/null 2>&1; then openssl sha1 "$p" 2>/dev/null|awk '{print $NF}'; else printf 'UNAVAILABLE'; fi; }
audit_meta(){ local key="$1"; awk -F= -v k="$key" '/^\[AUDIT_METADATA\]$/{inmeta=1;next}/^\[/&&inmeta{exit}inmeta&&$1==k{sub(/^[^=]*=/,"");print;exit}' "$BUNDLE" 2>/dev/null; }
trim_spaces(){ local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
validate_audit(){
 local mode="${1:-preview}" schema exporter_version build_sha database_sha metadata_layer self_check verdict recommendation notes notes_trimmed current_exporter_sha current_database_sha errors=0 collision_only=0
 [[ -f "$BUNDLE" ]]||{ echo "ERROR: Missing $BUNDLE"; echo "Run MiSTer_Audit and choose Audit first."; return 1; }
 schema="$(audit_meta schema_version)"; exporter_version="$(audit_meta exporter_version)"; build_sha="$(audit_meta build_sha1)"; database_sha="$(audit_meta database_sha1)"; metadata_layer="$(audit_meta metadata_layer)"; self_check="$(audit_meta self_check)"; verdict="$(audit_meta integrity_verdict)"; recommendation="$(audit_meta apply_recommendation)"; notes="$(audit_meta integrity_notes)"; notes_trimmed="$(trim_spaces "$notes")"
 [[ "$verdict" == "PASS WITH WARNINGS" && "$notes_trimmed" == "collision-review-required" ]]&&collision_only=1
 [[ "$recommendation" == "APPLY WITH SKIPS" && "$notes_trimmed" == *collision* ]]&&collision_only=1
 echo "Audit compatibility check"; echo "-------------------------"; echo "Schema:               ${schema:-MISSING}"; echo "Exporter version:     ${exporter_version:-MISSING}"; echo "Self-check:           ${self_check:-MISSING}"; echo "Metadata layer:       ${metadata_layer:-MISSING}"; echo "Integrity verdict:    ${verdict:-MISSING}"; echo "Apply recommendation: ${recommendation:-MISSING}"; echo "Integrity notes:      ${notes:-MISSING}"
 [[ "$schema" == "$EXPECTED_SCHEMA" ]]||{ echo "ERROR: Expected audit schema $EXPECTED_SCHEMA."; errors=1; }; [[ "$exporter_version" == "$EXPECTED_EXPORTER_VERSION" ]]||{ echo "ERROR: Expected exporter v$EXPECTED_EXPORTER_VERSION."; errors=1; }; [[ "$self_check" == PASS ]]||{ echo "ERROR: Auditor startup self-check did not pass."; errors=1; }; [[ "$metadata_layer" == MiSTer-aware ]]||{ echo "ERROR: MiSTer-aware metadata layer was not validated."; errors=1; }; [[ -n "$build_sha" && "$build_sha" != UNAVAILABLE ]]||{ echo "ERROR: Audit exporter build fingerprint is missing."; errors=1; }; [[ -n "$database_sha" && "$database_sha" != missing && "$database_sha" != UNAVAILABLE ]]||{ echo "ERROR: Audit database fingerprint is missing."; errors=1; }
 if [[ "$mode" == apply ]]; then
  if [[ "$verdict" == FAIL ]]; then echo "ERROR: Apply is blocked by integrity_verdict=FAIL."; errors=1; elif [[ "$verdict" == PASS ]]; then [[ "$recommendation" != "DO NOT APPLY" ]]||{ echo "ERROR: Auditor explicitly recommends DO NOT APPLY."; errors=1; }; elif ((collision_only)); then echo "WARNING: Audit contains collision-only warnings; blocking rows will be skipped automatically."; else echo "ERROR: Apply warnings are not limited to skippable collision rows."; errors=1; fi
  [[ -f "$RUNTIME" ]]||{ echo "ERROR: Current exporter not found."; errors=1; }; if [[ -f "$RUNTIME" ]]; then current_exporter_sha="$(hash_file "$RUNTIME")"; [[ "$current_exporter_sha" == "$build_sha" && "$current_exporter_sha" != UNAVAILABLE ]]||{ echo "ERROR: Exporter changed since this audit. Re-run audit."; errors=1; }; fi
  [[ -f "$HASH_DB" ]]||{ echo "ERROR: Current hash database not found."; errors=1; }; if [[ -f "$HASH_DB" ]]; then current_database_sha="$(hash_file "$HASH_DB")"; [[ "$current_database_sha" == "$database_sha" && "$current_database_sha" != UNAVAILABLE ]]||{ echo "ERROR: Hash database changed since this audit. Re-run audit."; errors=1; }; fi
 else
  if [[ "$verdict" == FAIL ]]; then echo "ERROR: Audit integrity failed."; errors=1; elif ((collision_only)); then echo "WARNING: Collision-only warnings detected; blocking rows will be shown as skipped."; elif [[ "$verdict" == "PASS WITH WARNINGS" || "$recommendation" == "DO NOT APPLY" ]]; then echo "WARNING: Preview allowed, but Apply remains blocked by non-collision warnings."; fi
 fi
 ((errors))&&{ echo "Audit compatibility check: BLOCKED"; return 1; }; echo "Audit compatibility check: PASS"
}
parse_csv(){ local s="$1" c field="" quoted=0 i; CSV_FIELDS=(); for((i=0;i<${#s};i++));do c="${s:i:1}"; if((quoted));then if [[ "$c" == '"' ]];then if [[ "${s:i+1:1}" == '"' ]];then field+='"'; ((i++));else quoted=0;fi;else field+="$c";fi;else case "$c" in '"')quoted=1;; ',')CSV_FIELDS+=("$field");field="";; *)field+="$c";;esac;fi;done; CSV_FIELDS+=("$field"); }
safe_under(){ case "$1" in "$2"/*)return 0;;*)return 1;;esac; }; unsafe_name(){ [[ -z "$1" || "$1" == */* || "$1" == . || "$1" == .. ]]; }
classify_blocking_games(){
 :>"$BLOCKLIST"; [[ -f "$CATALOG" ]]||{ echo "Missing $CATALOG"; return 1; }; local total=0; total=$(( $(wc -l <"$CATALOG")-1)); ((total<0))&&total=0
 stage "$STAGE_COLLISION" "Building collision safety map..."; echo "  Catalog rows: $total"
 awk -v heartbeat="$HEARTBEAT_EVERY" -v total="$total" -v resolve_stage="$STAGE_RESOLVE" '
 function csv_parse(s,a, i,c,n,field,quoted,nextc,k){for(k in a)delete a[k];n=1;field="";quoted=0;for(i=1;i<=length(s);i++){c=substr(s,i,1);if(quoted){if(c=="\""){nextc=substr(s,i+1,1);if(nextc=="\""){field=field "\"";i++}else quoted=0}else field=field c}else{if(c=="\"")quoted=1;else if(c==","){a[n++]=field;field=""}else field=field c}}a[n]=field;return n}
 function trimv(s){sub(/^[[:space:]]+/,"",s);sub(/[[:space:]]+$/,"",s);return s}
 function region_of(stem, s){s=tolower(stem);if(s~/\((usa|us|u)(,|\)|[[:space:]])/||s~/\((ue|u,e|u\+e)\)/)return "USA";if(s~/\((world|w)\)/)return "World";if(s~/\((europe|eur|e)\)/)return "Europe";if(s~/\((japan|jpn|j)\)/)return "Japan";if(s~/\((canada|can)\)/)return "Canada";if(s~/\((australia|aus)\)/)return "Australia";if(s~/\((korea|kor|k)\)/)return "Korea";if(s~/\((brazil|bra|b)\)/)return "Brazil";return "Unknown"}
 function kind_of(stem, s){s=tolower(stem);if(s~/\((proto|prototype|beta|demo|sample)([^a-z]|$)/||s~/\[(proto|prototype|beta|demo|sample)([^a-z]|$)/)return "Prototype/Beta/Demo";if(s~/\((rev|revision)[[:space:]._-]*[0-9a-z]+\)/||s~/\[(rev|revision)[[:space:]._-]*[0-9a-z]+\]/)return "Revision";if(s~/\((unl|unlicensed|homebrew|aftermarket)\)/||s~/\[(unl|unlicensed|homebrew|aftermarket)\]/||s~/ homebrew /||s~/ aftermarket /)return "Homebrew/Unlicensed";if(s~/\[t[^]]*\]/||s~/\(translation/||s~/\(translated/||s~/\(eng\)/||s~/\(english/||s~/translation/||s~/english patched/)return "Translation";if(s~/\[h[^]]*\]/||s~/\(hack/||s~/\(hacked/||s~/\(improvement/||s~/\(redux/||s~/\(randomizer/||s~/ hack /||s~/ improvement /||s~/ randomizer /)return "Hack/Modified";return "Retail/Standard"}
 function clean_title(stem, s,old){s=stem;do{old=s;gsub(/[[:space:]]+\((USA|US|U|World|W|Europe|EUR|E|Japan|JPN|J|Canada|CAN|Australia|AUS|Korea|KOR|Brazil|BRA|UE|U,E|U\+E)\)/,"",s);gsub(/[[:space:]]+\((Rev(ision)?[[:space:]._-]*[0-9A-Za-z]+|Proto(type)?|Beta|Demo|Sample|Unl(icensed)?|Homebrew|Aftermarket|Translation|Translated|Eng(lish)?[^)]*)\)/,"",s);gsub(/[[:space:]]+\[([tThH][^]]*|!|[bBoOfFpPaA][0-9]*|[cCxX])\]/,"",s)}while(s!=old);s=trimv(s);gsub(/[[:space:]][[:space:]]+/," ",s);sub(/[[:space:]]+[-_]$/,"",s);s=trimv(s);if(s=="")s=stem;return s}
 NR==1{next}{nf=csv_parse($0,f);if(nf<21)next;processed++;if(heartbeat>0&&processed%heartbeat==0)print "  Processed " processed " / " total " catalog rows...">"/dev/stderr";sysname=tolower(f[1]);original=f[5];proposed=f[6];rowpath=f[7];collision_status=f[9];dat_status=f[11];ext=original;sub(/^.*\./,"",ext);ext=tolower(ext);stem=original;sub(/\.[^.]*$/,"",stem);region=region_of(stem);kind=kind_of(stem);clean=clean_title(stem);suffix="";if(region!="USA"&&region!="Unknown")suffix=" [" region "]";if(region=="Unknown")suffix=" [Unknown Region]";if(kind!="Retail/Standard")suffix=suffix " [" kind "]";fallback=clean suffix "." ext;g=sysname "|" tolower(fallback);pre=(collision_status!="None"&&collision_status!="");authoritative=(dat_status=="Exact SHA-1"||dat_status=="Normalized SHA-1")?1:0;target=sysname "|" tolower(proposed);r++;paths[r]=rowpath;groups[r]=g;pres[r]=pre;targets[r]=target;final_count[target]++;if(pre){group_rows[g]++;group_auth[g]+=authoritative;gt=g SUBSEP target;group_target_count[gt]++;if(group_target_count[gt]>1)group_duplicate[g]=1}}
 END{print "  Processed " processed " / " total " catalog rows.">"/dev/stderr";print "">"/dev/stderr";print "[" resolve_stage "] Resolving global collision groups...">"/dev/stderr";for(i=1;i<=r;i++){g=groups[i];target=targets[i];pre=pres[i];safe=(!pre)||(group_auth[g]==group_rows[g]&&!group_duplicate[g]);if(final_count[target]>1)print paths[i] "\tblocking collision: duplicate final target";else if(pre&&!safe)print paths[i] "\tblocking collision: unresolved pre-DAT group"}}
 ' "$CATALOG">"$BLOCKLIST"||{ echo "ERROR: Collision safety classification failed."; return 1; }; echo "  Collision safety map complete: $(wc -l <"$BLOCKLIST") blocking rows."
}
build_plan(){
 :>"$PLAN"; :>"$SKIPS"; printf 'type\told_path\tnew_path\n'>"$PLAN"; printf 'type\tpath\treason\n'>"$SKIPS"; declare -A TARGETS BLOCKED_GAMES; local line old proposed new dir ext type block_path block_reason game_path processed=0 total=0
 classify_blocking_games||return 1; while IFS=$'\t' read -r block_path block_reason;do [[ -n "$block_path" ]]&&BLOCKED_GAMES["$block_path"]="$block_reason";done<"$BLOCKLIST"
 [[ -f "$GAME_CSV" ]]||{ echo "Missing $GAME_CSV"; return 1; }; total=$(( $(wc -l <"$GAME_CSV")-1)); ((total<0))&&total=0; stage "$STAGE_GAME" "Building safe game rename plan..."; echo "  Game proposals: $total"
 while IFS= read -r line||[[ -n "$line" ]];do [[ "$line" == '"system"'* ]]&&continue; parse_csv "$line"; processed=$((processed+1)); ((processed%HEARTBEAT_EVERY==0))&&echo "  Processed $processed / $total game proposals..."; old="${CSV_FIELDS[1]}"; proposed="${CSV_FIELDS[2]}"; type=GAME; if [[ -n "${BLOCKED_GAMES["$old"]+x}" ]];then printf '%s\t%s\t%s\n' "$type" "$old" "${BLOCKED_GAMES["$old"]}">>"$SKIPS";continue;fi; safe_under "$old" "$GAMES"||{ printf '%s\t%s\t%s\n' "$type" "$old" "outside games root">>"$SKIPS";continue; }; unsafe_name "$proposed"&&{ printf '%s\t%s\t%s\n' "$type" "$old" "unsafe proposed filename">>"$SKIPS";continue; }; ext="${old##*.}";ext="${ext,,}"; [[ "$ext" == cue ]]&&{ printf '%s\t%s\t%s\n' "$type" "$old" "CUE/BIN set rename disabled">>"$SKIPS";continue; }; [[ -e "$old" ]]||{ printf '%s\t%s\t%s\n' "$type" "$old" "source missing">>"$SKIPS";continue; };dir="${old%/*}";new="$dir/$proposed";[[ "$old" == "$new" ]]&&continue;[[ -e "$new" ]]&&{ printf '%s\t%s\t%s\n' "$type" "$old" "target already exists: $new">>"$SKIPS";continue; };[[ -n "${TARGETS["$new"]+x}" ]]&&{ printf '%s\t%s\t%s\n' "$type" "$old" "duplicate proposed target: $new">>"$SKIPS";continue; };TARGETS["$new"]="$old";printf '%s\t%s\t%s\n' "$type" "$old" "$new">>"$PLAN";done<"$GAME_CSV"; echo "  Processed $processed / $total game proposals."
 stage "$STAGE_SAVE" "Building paired save rename plan..."; if [[ -f "$SAVE_CSV" ]];then total=$(( $(wc -l <"$SAVE_CSV")-1));((total<0))&&total=0;processed=0;echo "  Save proposals: $total";while IFS= read -r line||[[ -n "$line" ]];do [[ "$line" == '"system"'* ]]&&continue;parse_csv "$line";processed=$((processed+1));game_path="${CSV_FIELDS[1]}";old="${CSV_FIELDS[2]}";proposed="${CSV_FIELDS[3]}";type=SAVE;if [[ -n "${BLOCKED_GAMES["$game_path"]+x}" ]];then printf '%s\t%s\t%s\n' "$type" "$old" "game rename skipped: ${BLOCKED_GAMES["$game_path"]}">>"$SKIPS";continue;fi;safe_under "$old" "$SAVES"||{ printf '%s\t%s\t%s\n' "$type" "$old" "outside saves root">>"$SKIPS";continue;};unsafe_name "$proposed"&&{ printf '%s\t%s\t%s\n' "$type" "$old" "unsafe proposed filename">>"$SKIPS";continue;};[[ -e "$old" ]]||{ printf '%s\t%s\t%s\n' "$type" "$old" "source missing">>"$SKIPS";continue;};dir="${old%/*}";new="$dir/$proposed";[[ "$old" == "$new" ]]&&continue;[[ -e "$new" ]]&&{ printf '%s\t%s\t%s\n' "$type" "$old" "target already exists: $new">>"$SKIPS";continue;};[[ -n "${TARGETS["$new"]+x}" ]]&&{ printf '%s\t%s\t%s\n' "$type" "$old" "duplicate proposed target: $new">>"$SKIPS";continue;};TARGETS["$new"]="$old";printf '%s\t%s\t%s\n' "$type" "$old" "$new">>"$PLAN";done<"$SAVE_CSV";echo "  Processed $processed / $total save proposals.";else echo "  No save proposal file found; continuing.";fi
}
plan_counts(){ PLAN_N=$(( $(wc -l <"$PLAN" 2>/dev/null)-1)); SKIP_N=$(( $(wc -l <"$SKIPS" 2>/dev/null)-1)); ((PLAN_N<0))&&PLAN_N=0; ((SKIP_N<0))&&SKIP_N=0; COLLISION_N=$(awk -F'\t' 'NR>1&&$3~/^blocking collision:|^game rename skipped: blocking collision:/{n++}END{print n+0}' "$SKIPS" 2>/dev/null); }
write_plan_meta(){ plan_counts; { echo "generated=$(date '+%Y-%m-%d %I:%M:%S %p %Z')"; echo "audit_mode=$(audit_meta audit_mode)"; echo "safe_renames=$PLAN_N"; echo "skipped_items=$SKIP_N"; echo "collision_blocked=$COLLISION_N"; echo "exporter_build=$(audit_meta build_sha1)"; echo "database_sha1=$(audit_meta database_sha1)"; } > "$PLAN_META"; }
meta_value(){ local key="$1"; awk -F= -v k="$key" '$1==k{sub(/^[^=]*=/,"");print;exit}' "$PLAN_META" 2>/dev/null; }
show_plan_summary(){ plan_counts; echo; echo "Safe rename candidates: $PLAN_N"; echo "Skipped/review items: $SKIP_N"; echo "Collision-blocked rows skipped: $COLLISION_N"; echo "Preview: $PLAN"; echo "Skipped: $SKIPS"; }
view_summary(){
 [[ -f "$PLAN" && -f "$SKIPS" ]]||{ echo "No saved preview summary found. Run Preview safe renames first."; return 1; }; plan_counts; local generated mode; generated="$(meta_value generated)"; mode="$(meta_value audit_mode)"
 echo; echo "Last Preview Summary"; echo "===================="; [[ -n "$generated" ]]&&echo "Generated: $generated"; [[ -n "$mode" ]]&&echo "Audit mode: $mode"; echo; printf 'Safe rename candidates:        %s\n' "$PLAN_N"; printf 'Skipped / review items:        %s\n' "$SKIP_N"; printf 'Collision-blocked rows skipped: %s\n' "$COLLISION_N"; echo; echo "Preview file:"; echo "  $PLAN"; echo; echo "Skipped file:"; echo "  $SKIPS"; echo; echo "Press Enter to return."; read -r _
}
review_preview(){
 [[ -f "$PLAN" ]]||{ echo "No saved preview found. Run Preview safe renames first."; return 1; }; local shown=0 type old new n; n=$(( $(wc -l <"$PLAN")-1)); ((n<0))&&n=0
 echo; echo "Last preview"; echo "============"; echo "Safe rename candidates: $n"; echo
 while IFS=$'\t' read -r type old new; do [[ "$type" == type ]]&&continue; shown=$((shown+1)); ((shown>20))&&break; echo "[$shown] $type"; echo "  From:"; echo "    $old"; echo "  To:"; echo "    $new"; echo; done < "$PLAN"
 ((n>20))&&echo "... $((n-20)) more safe renames are listed in $PLAN"; echo; echo "Press Enter to return."; read -r _
}
review_skips(){
 [[ -f "$SKIPS" ]]||{ echo "No saved skipped-item report found. Run Preview safe renames first."; return 1; }; local shown=0 type path reason n; n=$(( $(wc -l <"$SKIPS")-1)); ((n<0))&&n=0
 echo; echo "Skipped / review items"; echo "======================"; echo "Items: $n"; echo
 while IFS=$'\t' read -r type path reason; do [[ "$type" == type ]]&&continue; shown=$((shown+1)); ((shown>20))&&break; echo "[$shown] $type"; echo "  File:"; echo "    $path"; echo "  Reason:"; echo "    $reason"; echo; done < "$SKIPS"
 ((n>20))&&echo "... $((n-20)) more skipped items are listed in $SKIPS"; echo; echo "Press Enter to return."; read -r _
}
preview(){ STAGE_COLLISION="2/6";STAGE_RESOLVE="3/6";STAGE_GAME="4/6";STAGE_SAVE="5/6";stage "1/6" "Validating audit compatibility...";validate_audit preview||return 1;build_plan||return 1;write_plan_meta;stage "6/6" "Finalizing preview...";show_plan_summary;echo;echo "Preview complete.";echo "Press Enter to review the last preview, or Ctrl+C to close.";read -r _;review_preview; }
apply_plan(){ STAGE_COLLISION="2/8";STAGE_RESOLVE="3/8";STAGE_GAME="4/8";STAGE_SAVE="5/8";stage "1/8" "Validating audit compatibility...";validate_audit apply||return 1;build_plan||return 1;write_plan_meta;stage "6/8" "Reviewing safe rename plan...";local n stamp manifest type old new;n=$(( $(wc -l <"$PLAN")-1));((n>0))||{ echo "Nothing safe to rename.";return 0;};show_plan_summary;echo;echo "This will rename $n safe files. Collision-blocked rows and their saves remain untouched.";echo "Type APPLY exactly to continue:";read -r confirm;[[ "$confirm" == APPLY ]]||{ echo "Cancelled.";return 0;};stage "7/8" "Revalidating and rebuilding safe plan...";validate_audit apply||return 1;STAGE_COLLISION="7a/8";STAGE_RESOLVE="7b/8";STAGE_GAME="7c/8";STAGE_SAVE="7d/8";build_plan||return 1;write_plan_meta;stage "8/8" "Applying safe renames and writing rollback manifest...";stamp=$(date +%Y%m%d-%H%M%S);manifest="$HISTORY/rename-$stamp.tsv";printf 'type\told_path\tnew_path\tresult\n'>"$manifest";tail -n +2 "$PLAN"|while IFS=$'\t' read -r type old new;do if [[ -e "$old" && ! -e "$new" ]];then if mv -- "$old" "$new";then printf '%s\t%s\t%s\tOK\n' "$type" "$old" "$new">>"$manifest";else printf '%s\t%s\t%s\tFAILED\n' "$type" "$old" "$new">>"$manifest";fi;else printf '%s\t%s\t%s\tSKIPPED_AT_APPLY\n' "$type" "$old" "$new">>"$manifest";fi;done;cp "$manifest" "$HISTORY/last_manifest.tsv";echo "Finished. Rollback manifest: $manifest"; }
rollback(){ local manifest="$HISTORY/last_manifest.tsv" type old new result;[[ -f "$manifest" ]]||{ echo "No last rollback manifest found.";return 1;};echo "Rollback will restore successful renames from:";echo "$manifest";echo "Type ROLLBACK exactly to continue:";read -r confirm;[[ "$confirm" == ROLLBACK ]]||{ echo "Cancelled.";return 0;};tail -n +2 "$manifest"|tac|while IFS=$'\t' read -r type old new result;do [[ "$result" == OK ]]||continue;if [[ -e "$new" && ! -e "$old" ]];then mv -- "$new" "$old"||echo "FAILED: $new";else echo "SKIP: cannot safely restore $old";fi;done;echo "Rollback pass finished. Re-run the auditor to verify the library."; }
echo "MiSTer ROM Library Updater v1.4";echo "=================================";echo "Updater build: $UPDATER_BUILD";echo "Script path:   $0";echo "1) Preview safe renames";echo "2) Apply safe renames (blocking collisions auto-skipped)";echo "3) View last preview summary";echo "4) Review last preview";echo "5) Review skipped items";echo "6) Roll back last applied cleanup";echo "7) Exit";read -r choice;case "$choice" in 1)preview;;2)apply_plan;;3)view_summary;;4)review_preview;;5)review_skips;;6)rollback;;*)exit 0;;esac

}

main_menu() {
  while :; do
    echo
    echo "MiSTer ROM Library Auditor v1.4"
    echo "================================"
    echo "1) Run library audit"
    echo "2) Preview / Apply / Rollback"
    echo "3) Exit"
    read -r choice
    case "$choice" in
      1) run_audit; trap - EXIT INT TERM ;;
      2)
        echo
        echo "WARNING: Preview / Apply / Rollback can make changes to your game and save library."
        echo "Apply can rename files, and Rollback can reverse previously applied changes."
        echo "Run an audit and review the preview before applying changes."
        echo
        echo "1) Back [default]"
        echo "2) Continue"
        read -r update_choice
        case "${update_choice:-1}" in
          2) run_update_tools; trap - EXIT INT TERM ;;
          *) continue ;;
        esac
        ;;
      3|*) exit 0 ;;
    esac
  done
}

case "${1:-}" in
  audit) run_audit ;;
  update|rename) run_update_tools ;;
  *) main_menu ;;
esac
