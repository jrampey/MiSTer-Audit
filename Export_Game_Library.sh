#!/bin/bash
# Export_Game_Library_v1.3.sh
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
HASH_CACHE="$AUDIT/hash_cache.tsv"
HASH_CACHE_NEW="$WORK.hashcache_new"
CACHE_META="$AUDIT/hash_cache.meta"
CACHE_FORMAT="4"
AUDIT_SCHEMA_VERSION="4"
FULL_VERIFY_WORKERS=2

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

cleanup() { rm -f "$GAME_LIST" "$SAVE_LIST" "$SAVE_INDEX" "$PLAN" "$DAT_INDEX" "$HASH_ROWS" "$HASH_CACHE_NEW" "$PREHASH_RESULTS" "$WORK.duphashes" "$WORK.hashjobs"; rm -rf "$STAGE_DIR"; }

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
    dd if="$p" bs="$block" skip=1 2>/dev/null | sha1sum 2>/dev/null | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    dd if="$p" bs="$block" skip=1 2>/dev/null | openssl sha1 2>/dev/null | awk '{print $NF}'
  else
    printf 'UNAVAILABLE'
  fi
}

# Raw SHA-1 is authoritative first. Only on a DAT miss do we try safe,
# platform-specific normalizations known to occur in cartridge dumps.
normalized_dat_hash() {
  local p="$1" ext="${2,,}" raw="${3,,}" size alt=""
  [ -n "${DAT_NAME_BY_SHA[$raw]+x}" ] && { printf '%s' "$raw"; return; }
  size=$(stat -c '%s' "$p" 2>/dev/null)
  [ -z "$size" ] && size=$(stat -f '%z' "$p" 2>/dev/null)

  case "$ext" in
    nes)
      # iNES/NES2 files may carry a 16-byte container header while a DAT may
      # identify the ROM payload. Try payload SHA only after the raw SHA misses.
      if [ "${size:-0}" -gt 16 ] 2>/dev/null; then
        alt="$(hash_stream_skip "$p" 16)"
        [ -n "${DAT_NAME_BY_SHA[${alt,,}]+x}" ] && { printf '%s' "${alt,,}"; return; }
      fi
      ;;
    sfc|smc)
      # Legacy SNES copier headers are 512 bytes. Only try stripping one when
      # file size strongly indicates a copier header.
      if [ "${size:-0}" -gt 512 ] 2>/dev/null && [ $((size % 32768)) -eq 512 ]; then
        alt="$(hash_stream_skip "$p" 512)"
        [ -n "${DAT_NAME_BY_SHA[${alt,,}]+x}" ] && { printf '%s' "${alt,,}"; return; }
      fi
      ;;
    z64|v64)
      # Big-endian and byte-swapped N64 DATs are both in the database, so raw
      # SHA matching is already the safe normalization strategy for these.
      ;;
    n64)
      # Little-endian N64 requires 32-bit byte reversal. Do not guess using a
      # lossy shell transform; leave unmatched unless a raw DAT record exists.
      ;;
  esac
  printf '%s' "$raw"
}


file_signature() {
  local p="$1" sig
  # GNU/BSD stat compatibility. Size + mtime is used only to decide whether a
  # previously calculated SHA-1 can be reused; every run still rescans the full library.
  sig="$(stat -c '%s|%Y' "$p" 2>/dev/null)"
  [ -z "$sig" ] && sig="$(stat -f '%z|%m' "$p" 2>/dev/null)"
  printf '%s' "$sig"
}

declare -A CACHE_SHA CACHE_DAT_STATUS CACHE_DAT_NAME CACHE_DAT_ROM CACHE_DAT_SOURCE
CACHE_ENTRIES_LOADED=0
cache_lookup() {
  local p="$1" sig="$2" k="$p|$sig"
  printf '%s' "${CACHE_SHA[$k]:-}"
}

should_hash() {
  local system="${1,,}" ext="${2,,}"
  # System-aware eligibility: hash formats covered by the bundled MiSTer-aware DB.
  # Extension remains a fallback for clearly Nintendo-specific cartridge formats.
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


# Build the local SHA-1 lookup exclusively from the bundled TSV database
# stored next to this script. Legacy XML DAT-folder parsing was removed in v1.2.
declare -A DAT_NAME_BY_SHA DAT_ROM_BY_SHA DAT_SOURCE_BY_SHA DAT_SYSTEM_BY_SHA DAT_CORE_BY_SHA DAT_FOLDER_BY_SHA DAT_REGION_BY_SHA DAT_RELEASE_BY_SHA DAT_LICENSE_BY_SHA
build_dat_index() {
  : > "$DAT_INDEX"
  HASH_DB_SOURCE="None"
  HASH_DB_FINGERPRINT="missing"
  HASH_INDEX_COUNT=0

  if [ -f "$HASH_DB_TSV" ]; then
    echo "    Using bundled hash database: $HASH_DB_TSV"
    HASH_DB_SOURCE="mister_hash_database.tsv"
    HASH_DB_FINGERPRINT="$(hash_file "$HASH_DB_TSV")"
    while IFS=$'\t' read -r h title rom source size crc32 md5 meta_system meta_core meta_folder meta_region meta_release meta_license rest; do
      [ "$h" = "sha1" ] && continue
      h="${h,,}"
      [[ "$h" =~ ^[0-9a-f]{40}$ ]] || continue
      if [ -z "${DAT_NAME_BY_SHA[$h]+x}" ]; then
        DAT_NAME_BY_SHA["$h"]="$title"
        DAT_ROM_BY_SHA["$h"]="$rom"
        DAT_SOURCE_BY_SHA["$h"]="$source"
        DAT_SYSTEM_BY_SHA["$h"]="$meta_system"
        DAT_CORE_BY_SHA["$h"]="$meta_core"
        DAT_FOLDER_BY_SHA["$h"]="$meta_folder"
        DAT_REGION_BY_SHA["$h"]="$meta_region"
        DAT_RELEASE_BY_SHA["$h"]="$meta_release"
        DAT_LICENSE_BY_SHA["$h"]="$meta_license"
        HASH_INDEX_COUNT=$((HASH_INDEX_COUNT+1))
      fi
    done < "$HASH_DB_TSV"
  else
    echo "    WARNING: $HASH_DB_TSV was not found. Hashes will still be calculated, but canonical matching will be unavailable."
  fi
}

dat_lookup() {
  local h="${1,,}"
  [ -n "${DAT_NAME_BY_SHA[$h]+x}" ] || return 0
  printf '%s\t%s\t%s\n' "$h" "${DAT_NAME_BY_SHA[$h]}" "${DAT_ROM_BY_SHA[$h]}" "${DAT_SOURCE_BY_SHA[$h]}"
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

load_hash_cache() {
  local old_format="" old_db="" p sig sha ds dn dr dsrc k
  if [ -s "$CACHE_META" ]; then
    while IFS='=' read -r k v; do
      case "$k" in CACHE_FORMAT) old_format="$v";; HASH_DB_FINGERPRINT) old_db="$v";; esac
    done < "$CACHE_META"
  fi
  [ "$old_format" = "$CACHE_FORMAT" ] || return 0
  [ -s "$HASH_CACHE" ] || return 0
  while IFS=$'\t' read -r p sig sha ds dn dr dsrc; do
    [ "$p" = "path" ] && continue
    k="$p|$sig"
    CACHE_SHA["$k"]="$sha"
    CACHE_ENTRIES_LOADED=$((CACHE_ENTRIES_LOADED+1))
    # DAT match metadata is valid only while the database fingerprint is unchanged.
    if [ "$old_db" = "$HASH_DB_FINGERPRINT" ]; then
      CACHE_DAT_STATUS["$k"]="$ds"
      CACHE_DAT_NAME["$k"]="$dn"
      CACHE_DAT_ROM["$k"]="$dr"
      CACHE_DAT_SOURCE["$k"]="$dsrc"
    fi
  done < "$HASH_CACHE"
}


csv_escape() { local s="$1"; s="${s//\"/\"\"}"; printf '"%s"' "$s"; }
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

region_of() {
  local s="${1,,}"
  # Long-form + common GoodTools/TOSEC abbreviations. Order matters for multi-region tags.
  if [[ "$s" =~ \((usa|us|u)(,|\)|[[:space:]]) ]] || [[ "$s" =~ \((ue|u,e|u\+e)\) ]]; then echo USA
  elif [[ "$s" =~ \((world|w)\) ]]; then echo World
  elif [[ "$s" =~ \((europe|eur|e)\) ]]; then echo Europe
  elif [[ "$s" =~ \((japan|jpn|j)\) ]]; then echo Japan
  elif [[ "$s" =~ \((canada|can)\) ]]; then echo Canada
  elif [[ "$s" =~ \((australia|aus)\) ]]; then echo Australia
  elif [[ "$s" =~ \((korea|kor|k)\) ]]; then echo Korea
  elif [[ "$s" =~ \((brazil|bra|b)\) ]]; then echo Brazil
  else echo Unknown; fi
}

kind_of() {
  local s="${1,,}"
  # Only metadata-style tokens and explicit phrases; avoids false positives such as "Protoman".
  if [[ "$s" =~ \((proto|prototype|beta|demo|sample)([^a-z]|$) ]] || [[ "$s" =~ \[(proto|prototype|beta|demo|sample)([^a-z]|$) ]]; then echo Prototype/Beta/Demo
  elif [[ "$s" =~ \((rev|revision)[[:space:]._-]*[0-9a-z]+\) ]] || [[ "$s" =~ \[(rev|revision)[[:space:]._-]*[0-9a-z]+\] ]]; then echo Revision
  elif [[ "$s" =~ \((unl|unlicensed|homebrew|aftermarket)\) ]] || [[ "$s" =~ \[(unl|unlicensed|homebrew|aftermarket)\] ]] || [[ "$s" == *" homebrew "* ]] || [[ "$s" == *" aftermarket "* ]]; then echo Homebrew/Unlicensed
  elif [[ "$s" =~ \[t[^]]*\] ]] || [[ "$s" == *"(translation"* ]] || [[ "$s" == *"(translated"* ]] || [[ "$s" == *"(eng)"* ]] || [[ "$s" == *"(english"* ]] || [[ "$s" == *"translation"* ]] || [[ "$s" == *"english patched"* ]]; then echo Translation
  elif [[ "$s" =~ \[h[^]]*\] ]] || [[ "$s" == *"(hack"* ]] || [[ "$s" == *"(hacked"* ]] || [[ "$s" == *"(improvement"* ]] || [[ "$s" == *"(redux"* ]] || [[ "$s" == *"(randomizer"* ]] || [[ "$s" == *" hack "* ]] || [[ "$s" == *" improvement "* ]] || [[ "$s" == *" randomizer "* ]]; then echo Hack/Modified
  else echo Retail/Standard; fi
}

is_support_file() {
  local path="${1,,}" file="${2,,}" stem="${2%.*}"; stem="${stem,,}"
  case "$path" in
    */bios/*|*/bioses/*|*/firmware/*|*/kickstart/*|*/bootrom/*|*/boot_rom/*|*/boot-rom/*|*/system_rom/*|*/system-rom/*|*/machine_rom/*|*/machine-rom/*|*/testrom/*|*/test_rom/*|*/test-rom/*|*/diagnostic/*|*/diagnostics/*|*/utilities/*|*/utility/*) return 0 ;;
  esac
  case "$file" in
    bios.*|boot.rom|boot.bin|boot[0-9]*.rom|boot[0-9]*_*.rom|boot[0-9]*-*.rom|firmware.*|kickstart.rom|cd_bios.rom|uni-bioscd.rom|kanji.rom|empty.rom) return 0 ;;
  esac
  # Strong support/diagnostic names observed in v1.0 output and common MiSTer sets.
  if [[ "$stem" == *" bios"* || "$stem" == *"bios "* || "$stem" == *"boot rom"* || "$stem" == *"bootrom"* || "$stem" == *"firmware"* || "$stem" == *"test rom"* || "$stem" == *"diagnostic"* || "$stem" == serialporttest* || "$stem" == sioecho* || "$stem" == statuslights* || "$stem" == *"240p test suite"* ]]; then return 0; fi
  return 1
}

clean_title() {
  local s="$1" before
  local re_region='^(.*)[[:space:]]+\((USA|US|U|World|W|Europe|EUR|E|Japan|JPN|J|Canada|CAN|Australia|AUS|Korea|KOR|Brazil|BRA|UE|U,E|U\+E)\)(.*)$'
  local re_meta='^(.*)[[:space:]]+\((Rev(ision)?[[:space:]._-]*[0-9A-Za-z]+|Proto(type)?|Beta|Demo|Sample|Unl(icensed)?|Homebrew|Aftermarket|Translation|Translated|Eng(lish)?[^)]*)\)(.*)$'
  local re_bracket='^(.*)[[:space:]]+\[([tThH][^]]*|!|[bBoOfFpPaA][0-9]*|[cCxX])\](.*)$'
  # Bash-only normalization avoids spawning sed once per ROM.
  while :; do
    before="$s"
    if [[ "$s" =~ $re_region ]]; then
      s="${BASH_REMATCH[1]}${BASH_REMATCH[3]}"
    elif [[ "$s" =~ $re_meta ]]; then
      s="${BASH_REMATCH[1]}${BASH_REMATCH[7]}"
    elif [[ "$s" =~ $re_bracket ]]; then
      s="${BASH_REMATCH[1]}${BASH_REMATCH[3]}"
    else
      break
    fi
  done
  s="$(trim "$s")"
  while [[ "$s" == *"  "* ]]; do s="${s//  / }"; done
  s="${s% -}"; s="${s% _}"; s="$(trim "$s")"
  [ -z "$s" ] && s="$1"
  printf '%s' "$s"
}


suffix_for() {
  local region="$1" kind="$2" suffix=""
  # USA retail is the preferred clean filename. Preserve meaningful alternatives.
  [ "$region" != "USA" ] && [ "$region" != "Unknown" ] && suffix=" [$region]"
  [ "$region" = "Unknown" ] && suffix=" [Unknown Region]"
  [ "$kind" != "Retail/Standard" ] && suffix="$suffix [$kind]"
  printf '%s' "$suffix"
}

location_status() {
  local current="${1,,}" expected="${2,,}"
  [ -z "$expected" ] && { echo "Unknown"; return; }
  [ "$current" = "$expected" ] && { echo "OK"; return; }
  case "$expected" in
    nes) case "$current" in nes|fds|famicom) echo "OK (compatible folder)"; return;; esac ;;
    gameboy) case "$current" in gameboy|game\ boy|gb) echo "OK (compatible folder)"; return;; esac ;;
    n64) case "$current" in n64|nintendo64|nintendo\ 64) echo "OK (compatible folder)"; return;; esac ;;
  esac
  echo "MISFILED"
}

# Static stage output plus a progress heartbeat every 30 seconds.
START_TIME=$(date +%s)
LAST_PROGRESS_TIME=$START_TIME

on_exit() { cleanup; }
trap on_exit EXIT INT TERM

progress_check() {
  local stage="$1" current="${2:-0}" total="${3:-0}" now elapsed pct
  now=$(date +%s)
  if [ $((now - LAST_PROGRESS_TIME)) -ge 30 ]; then
    elapsed=$((now - START_TIME))
    pct=0
    if [ "$total" -gt 0 ] 2>/dev/null; then pct=$((current * 100 / total)); fi
    printf '[%02d:%02d] %s: %s / %s (%s%%)' $((elapsed/60)) $((elapsed%60)) "$stage" "$current" "$total" "$pct"
    if [ "$stage" = "Building reports" ]; then
      printf ' | DAT matches: %s | Unmatched: %s' "${DAT_MATCHED:-0}" "$(( ${HASHED:-0} - ${DAT_MATCHED:-0} ))"
    fi
    printf '\n'
    LAST_PROGRESS_TIME=$now
  fi
}

echo
SELF_CHECK_STATUS="PASS"
SELF_CHECK_NOTES=""
for cmd in find sort stat awk wc xargs; do
  if ! command -v "$cmd" >/dev/null 2>&1; then SELF_CHECK_STATUS="FAIL"; SELF_CHECK_NOTES="$SELF_CHECK_NOTES missing:$cmd"; fi
done
if ! command -v sha1sum >/dev/null 2>&1 && ! command -v openssl >/dev/null 2>&1; then SELF_CHECK_STATUS="FAIL"; SELF_CHECK_NOTES="$SELF_CHECK_NOTES missing:sha1-tool"; fi
if [ ! -f "$HASH_DB_TSV" ]; then SELF_CHECK_STATUS="FAIL"; SELF_CHECK_NOTES="$SELF_CHECK_NOTES missing:hash-db"; fi
if [ -f "$HASH_DB_TSV" ]; then
  IFS=$'\t' read -r dbh _ < "$HASH_DB_TSV"
  [ "$dbh" = "sha1" ] || { SELF_CHECK_STATUS="FAIL"; SELF_CHECK_NOTES="$SELF_CHECK_NOTES invalid:hash-db-header"; }
  DB_HEADER=$(head -n 1 "$HASH_DB_TSV" 2>/dev/null)
  REQUIRED_DB_HEADER=$'sha1\tcanonical_title\tcanonical_rom_name\tdat_source\tsize\tcrc32\tmd5\tmister_system\tmister_core\texpected_folder\tregion\trelease_type\tlicense_status'
  if [ "$DB_HEADER" = "$REQUIRED_DB_HEADER" ]; then
    METADATA_LAYER_STATUS="MiSTer-aware"
  else
    METADATA_LAYER_STATUS="INVALID"
    SELF_CHECK_STATUS="FAIL"
    SELF_CHECK_NOTES="$SELF_CHECK_NOTES invalid:mister-aware-db-schema"
  fi
  DB_LINE_COUNT=$(wc -l < "$HASH_DB_TSV" 2>/dev/null); DB_LINE_COUNT=${DB_LINE_COUNT//[[:space:]]/}
  [ "${DB_LINE_COUNT:-0}" -ge 1000 ] 2>/dev/null || { SELF_CHECK_STATUS="FAIL"; SELF_CHECK_NOTES="$SELF_CHECK_NOTES suspiciously-small:hash-db"; }
fi
if [ ! -w "$AUDIT" ]; then SELF_CHECK_STATUS="FAIL"; SELF_CHECK_NOTES="$SELF_CHECK_NOTES not-writable:audit-dir"; fi
if [ "$SELF_CHECK_STATUS" != "PASS" ]; then
  echo "ERROR: Startup self-check failed:$SELF_CHECK_NOTES"
  echo "No audit was published."
  read -p "Press Enter to exit..."
  exit 1
fi

METADATA_LAYER_STATUS="${METADATA_LAYER_STATUS:-Unknown}"
EXPORTER_BUILD_SHA1="$(hash_file "$0")"
echo "+--------------------------------------------------+"
echo "| MiSTer ROM Library Auditor v1.3                 |"
echo "| Read-only audit - no ROMs or saves are changed  |"
echo "+--------------------------------------------------+"
echo

# Interactive audit-mode menu. Fast Audit is highlighted by default.
# Supports keyboard/controller Up/Down arrows, Enter, and 1/2 shortcuts.
AUDIT_MENU_SELECTION=1
AUDIT_MENU_LINES=5
render_audit_menu() {
  local fast_prefix="  " full_prefix="  "
  [ "$AUDIT_MENU_SELECTION" -eq 1 ] && fast_prefix="> " || full_prefix="> "
  printf "+--------------------------------------------------+\n"
  printf "| AUDIT MODE                                       |\n"
  printf "+--------------------------------------------------+\n"
  printf "%s1) Fast Audit - recommended\n" "$fast_prefix"
  printf "     Reuse valid cached hashes.\n"
  printf "%s2) Full Verification\n" "$full_prefix"
  printf "     Recalculate every supported SHA-1.\n"
  printf '%s\n' '----------------------------------------------------'
  printf "1/2 or arrows select | Enter = Fast | Auto = 15s\n"
}

render_audit_menu
while :; do
  # Wait up to 15 seconds for input. A timeout runs the default Fast Audit.
  AUDIT_KEY=""
  if ! IFS= read -rsn1 -t 15 AUDIT_KEY; then
    AUDIT_MENU_SELECTION=1
    break
  fi
  case "$AUDIT_KEY" in
    "") AUDIT_MENU_SELECTION=1; break ;; # Enter runs default Fast Audit
    1) AUDIT_MENU_SELECTION=1; break ;;
    2) AUDIT_MENU_SELECTION=2; break ;;
    $'\x1b')
      # Arrow keys normally arrive as ESC [ A / ESC [ B. Read the rest
      # with a short timeout so a lone Escape key does not block.
      IFS= read -rsn1 -t 0.15 AUDIT_KEY2 || AUDIT_KEY2=""
      if [ "$AUDIT_KEY2" = "[" ]; then
        IFS= read -rsn1 -t 0.15 AUDIT_KEY3 || AUDIT_KEY3=""
        case "$AUDIT_KEY3" in
          A) AUDIT_MENU_SELECTION=1; break ;; # Up immediately runs Fast Audit
          B) AUDIT_MENU_SELECTION=2; break ;; # Down immediately runs Full Verification
        esac
      fi
      ;;
  esac
done

if [ "$AUDIT_MENU_SELECTION" -eq 2 ]; then
  AUDIT_MODE="Full Verification"; USE_HASH_CACHE=0
else
  AUDIT_MODE="Fast Audit"; USE_HASH_CACHE=1
fi
echo
echo "Selected: $AUDIT_MODE"
echo "----------------------------------------------------"
echo
DISCOVERY_START=$(date +%s)
echo "[1/5] Scanning game library..."
find "$GAMES" -type f \( \
  -iname "*.nes" -o -iname "*.fds" -o -iname "*.sfc" -o -iname "*.smc" \
  -o -iname "*.gb" -o -iname "*.gbc" -o -iname "*.gba" -o -iname "*.md" \
  -o -iname "*.gen" -o -iname "*.32x" -o -iname "*.sms" -o -iname "*.gg" \
  -o -iname "*.sg" -o -iname "*.pce" -o -iname "*.sgx" -o -iname "*.a26" \
  -o -iname "*.a52" -o -iname "*.a78" -o -iname "*.col" -o -iname "*.int" \
  -o -iname "*.cue" -o -iname "*.chd" -o -iname "*.d64" -o -iname "*.d81" \
  -o -iname "*.g64" -o -iname "*.adf" -o -iname "*.hdf" -o -iname "*.dsk" \
  -o -iname "*.tap" -o -iname "*.tzx" -o -iname "*.rom" -o -iname "*.n64" -o -iname "*.z64" -o -iname "*.v64" \) -print 2>/dev/null | LC_ALL=C sort > "$GAME_LIST"
GAME_SCAN_COUNT=$(wc -l < "$GAME_LIST" | tr -d "[:space:]")
echo "    Files discovered: $GAME_SCAN_COUNT"
DISCOVERY_END=$(date +%s)
SAVE_START=$DISCOVERY_END

echo "[2/5] Indexing save files..."
: > "$SAVE_LIST"; : > "$SAVE_INDEX"
declare -A SAVES_BY_STEM
SAVE_PROCESSED=0
if [ -d "$SAVES" ]; then
  find "$SAVES" -type f \( -iname "*.sav" -o -iname "*.srm" -o -iname "*.ram" -o -iname "*.eep" -o -iname "*.fla" -o -iname "*.sra" -o -iname "*.mcd" -o -iname "*.nv" \) -print 2>/dev/null | sort > "$SAVE_LIST"
  SAVE_SCAN_COUNT=$(wc -l < "$SAVE_LIST" | tr -d "[:space:]"); [ -z "$SAVE_SCAN_COUNT" ] && SAVE_SCAN_COUNT=0
  while IFS= read -r sp; do
    [ -z "$sp" ] && continue; sf="${sp##*/}"; sstem="${sf%.*}"
    save_key_idx="${sstem,,}"
    if [ -n "${SAVES_BY_STEM[$save_key_idx]:-}" ]; then SAVES_BY_STEM["$save_key_idx"]+=$'\n'"$sp"; else SAVES_BY_STEM["$save_key_idx"]="$sp"; fi
    printf '%s\t%s\n' "$save_key_idx" "$sp" >> "$SAVE_INDEX"
    SAVE_PROCESSED=$((SAVE_PROCESSED+1)); progress_check "Indexing saves" "$SAVE_PROCESSED" "$SAVE_SCAN_COUNT"
  done < "$SAVE_LIST"
fi
SAVE_END=$(date +%s)
DB_START=$SAVE_END

echo "[3/5] Loading hash database..."
build_dat_index
echo "    Hash database source: $HASH_DB_SOURCE"
echo "    Hash records indexed: $HASH_INDEX_COUNT"
build_completion_reference
load_hash_cache
DB_END=$(date +%s)
CLASSIFY_START=$DB_END

# First pass builds metadata and collision counts.
echo "[4/5] Classifying titles and collisions..."
: > "$PLAN"
declare -A NAME_COUNTS
SKIPPED=0; CLASSIFIED=0
while IFS= read -r p; do
  [ -z "$p" ] && continue
  rel="${p#$GAMES/}"; system="${rel%%/*}"; [ "$system" = "$rel" ] && system="Unknown"
  file="${p##*/}"; ext="${file##*.}"; stem="${file%.*}"
  case "${ext,,}" in
    md|gen) system="MegaDrive" ;;
    32x) system="S32X" ;;
  esac
  if is_support_file "$p" "$file"; then SKIPPED=$((SKIPPED+1)); continue; fi
  region="$(region_of "$stem")"; kind="$(kind_of "$stem")"; clean="$(clean_title "$stem")"
  suffix="$(suffix_for "$region" "$kind")"; proposed="$clean$suffix.$ext"
  key="${system,,}|${proposed,,}"
  NAME_COUNTS["$key"]=$(( ${NAME_COUNTS["$key"]:-0} + 1 ))
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$system" "$p" "$file" "$ext" "$stem" "$clean" "$region" "$kind" >> "$PLAN"
  CLASSIFIED=$((CLASSIFIED+1)); progress_check "Classifying titles" "$CLASSIFIED" "$GAME_SCAN_COUNT"
done < "$GAME_LIST"

CLASSIFY_END=$(date +%s)

# Full Verification hashes eligible ROMs with two workers before report generation.
declare -A PREHASH_SHA_BY_PATH SYSTEM_FILES SYSTEM_ELIGIBLE SYSTEM_MATCHED SYSTEM_UNMATCHED SYSTEM_SECONDS
FULL_VERIFY_PARALLEL_SECONDS=0
if [ "$USE_HASH_CACHE" -eq 0 ]; then
  : > "$WORK.hashjobs"; : > "$PREHASH_RESULTS"
  while IFS=$'\t' read -r psystem pp pfile pext prest; do
    should_hash "$psystem" "$pext" && printf '%s\0' "$pp" >> "$WORK.hashjobs"
  done < "$PLAN"
  pv_start=$SECONDS
  if [ -s "$WORK.hashjobs" ]; then
    XARGS_PARALLEL_ARGS=""
    if xargs --help 2>&1 | grep -q -- '-P'; then XARGS_PARALLEL_ARGS="-P $FULL_VERIFY_WORKERS"; fi
    if command -v sha1sum >/dev/null 2>&1; then
      xargs -0 -n1 $XARGS_PARALLEL_ARGS sh -c 'p="$1"; h=$(sha1sum "$p" 2>/dev/null); h=${h%% *}; printf "%s\t%s\n" "$h" "$p"' sh < "$WORK.hashjobs" > "$PREHASH_RESULTS"
    else
      xargs -0 -n1 $XARGS_PARALLEL_ARGS sh -c 'p="$1"; h=$(openssl sha1 "$p" 2>/dev/null); h=${h##* }; printf "%s\t%s\n" "$h" "$p"' sh < "$WORK.hashjobs" > "$PREHASH_RESULTS"
    fi
    while IFS=$'\t' read -r ph pp; do [ -n "$pp" ] && PREHASH_SHA_BY_PATH["$pp"]="$ph"; done < "$PREHASH_RESULTS"
  fi
  FULL_VERIFY_PARALLEL_SECONDS=$((SECONDS-pv_start))
fi
REPORT_START=$(date +%s)

cat > "$STAGE_OUT" <<EOF2
MiSTer Game Library v1.3
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
printf '%s\n' '"sha1","system","full_path","original_filename"' > "$STAGE_DAT_UNMATCHED"
printf '%s\n' '"system","full_path","canonical_name","mister_system","mister_core","expected_folder","location_status"' > "$STAGE_LOCATION_AUDIT"
: > "$HASH_ROWS"

TOTAL=0; SAVE_MATCHES=0; COLLISIONS=0; HASHED=0; DAT_MATCHED=0; HASH_REUSED=0; HASH_CALCULATED=0; HASH_SKIPPED=0; HASH_ELIGIBLE=0
printf 'path\tsignature\tsha1\tdat_status\tdat_name\tdat_rom\tdat_source\n' > "$HASH_CACHE_NEW"
declare -A SEEN_NAMES

echo "[5/5] Building audit reports..."
PLAN_TOTAL=$(wc -l < "$PLAN" | tr -d "[:space:]"); [ -z "$PLAN_TOTAL" ] && PLAN_TOTAL=0

# Read the report plan through a dedicated descriptor. This prevents commands
# executed inside the loop from accidentally consuming PLAN records from stdin.
exec 3< "$PLAN"
while IFS=$'\t' read -r -u 3 system p file ext stem clean region kind; do
  [ -z "$p" ] && continue
  suffix="$(suffix_for "$region" "$kind")"; base="$clean$suffix"; proposed="$base.$ext"
  key="${system,,}|${proposed,,}"; collision="None"
  if [ "${NAME_COUNTS["$key"]:-0}" -gt 1 ]; then
    # Keep every proposal unique without discarding source metadata.
    n=$(( ${SEEN_NAMES["$key"]:-0} + 1 )); SEEN_NAMES["$key"]=$n
    proposed="$base [Variant $n].$ext"; collision="Resolved variant $n of ${NAME_COUNTS["$key"]}"
    COLLISIONS=$((COLLISIONS+1))
  fi

  row_seconds_start=$SECONDS
  SYSTEM_FILES["$system"]=$(( ${SYSTEM_FILES["$system"]:-0} + 1 ))
  sha1=""; dat_status="Not applicable"; dat_name=""; dat_rom=""; dat_source=""; meta_system=""; meta_core=""; meta_folder=""; meta_region=""; meta_release=""; meta_license=""; loc_status="Unknown"
  if should_hash "$system" "$ext"; then
    HASH_ELIGIBLE=$((HASH_ELIGIBLE+1)); SYSTEM_ELIGIBLE["$system"]=$(( ${SYSTEM_ELIGIBLE["$system"]:-0} + 1 ))
    sig="$(file_signature "$p")"
    cache_key="$p|$sig"
    cached_sha=""
    if [ "$USE_HASH_CACHE" -eq 1 ]; then
      cached_sha="${CACHE_SHA[$cache_key]:-}"
    fi
    if [ -n "$cached_sha" ]; then
      sha1="$cached_sha"
      HASH_REUSED=$((HASH_REUSED+1))
      if [ -n "${CACHE_DAT_STATUS[$cache_key]+x}" ]; then
        dat_status="${CACHE_DAT_STATUS[$cache_key]}"
        dat_name="${CACHE_DAT_NAME[$cache_key]:-}"
        dat_rom="${CACHE_DAT_ROM[$cache_key]:-}"
        dat_source="${CACHE_DAT_SOURCE[$cache_key]:-}"
      else
        dat_status="No match"
      fi
    else
      if [ "$USE_HASH_CACHE" -eq 0 ] && [ -n "${PREHASH_SHA_BY_PATH[$p]:-}" ]; then sha1="${PREHASH_SHA_BY_PATH[$p]}"; else sha1="$(hash_file "$p")"; fi
      [ -n "$sha1" ] && [ "$sha1" != "UNAVAILABLE" ] && HASH_CALCULATED=$((HASH_CALCULATED+1))
      dat_status="No match"
    fi
  else
    HASH_SKIPPED=$((HASH_SKIPPED+1))
  fi
  if [ -n "$sha1" ] && [ "$sha1" != "UNAVAILABLE" ]; then
    HASHED=$((HASHED+1))
    printf '%s\t%s\t%s\t%s\t%s\n' "${sha1,,}" "$system" "$p" "$file" "$clean" >> "$HASH_ROWS"
    hkey="${sha1,,}"
    matched_hkey="$(normalized_dat_hash "$p" "$ext" "$hkey")"
    if [ "$matched_hkey" != "$hkey" ]; then
      hkey="$matched_hkey"
      sha1="$matched_hkey"
      dat_status="Normalized SHA-1"
    fi
    if [ -n "${DAT_NAME_BY_SHA[$hkey]+x}" ]; then
      dat_name="${DAT_NAME_BY_SHA[$hkey]}"; dat_rom="${DAT_ROM_BY_SHA[$hkey]}"; dat_source="${DAT_SOURCE_BY_SHA[$hkey]}"
      meta_system="${DAT_SYSTEM_BY_SHA[$hkey]:-}"; meta_core="${DAT_CORE_BY_SHA[$hkey]:-}"; meta_folder="${DAT_FOLDER_BY_SHA[$hkey]:-}"; meta_region="${DAT_REGION_BY_SHA[$hkey]:-}"; meta_release="${DAT_RELEASE_BY_SHA[$hkey]:-}"; meta_license="${DAT_LICENSE_BY_SHA[$hkey]:-}"
      # DAT identity wins over filename parsing. Canonical No-Intro ROM names
      # preserve title, region, revision and other release metadata.
      if [ -n "$dat_rom" ]; then
        canonical_file="${dat_rom##*/}"
        canonical_ext="${canonical_file##*.}"
        canonical_stem="${canonical_file%.*}"
        [ -n "$canonical_stem" ] && clean="$(clean_title "$canonical_stem")"
        [ -n "$meta_region" ] && region="$meta_region"
        [ -n "$meta_release" ] && kind="$meta_release"
        proposed="$canonical_file"
      elif [ -n "$dat_name" ]; then
        clean="$(clean_title "$dat_name")"
        [ -n "$meta_region" ] && region="$meta_region"
        [ -n "$meta_release" ] && kind="$meta_release"
        proposed="$clean$(suffix_for "$region" "$kind").$ext"
      fi
      loc_status="$(location_status "$system" "$meta_folder")"
      record_completion_owned "${meta_system:-$system}" "$dat_name" "$meta_region" "$meta_release" "$meta_license"
      [ "$dat_status" = "Normalized SHA-1" ] || dat_status="Exact SHA-1"; DAT_MATCHED=$((DAT_MATCHED+1)); SYSTEM_MATCHED["$system"]=$(( ${SYSTEM_MATCHED["$system"]:-0} + 1 ))
      csv_escape "$sha1" >> "$STAGE_DAT_MATCH"; printf ',' >> "$STAGE_DAT_MATCH"; csv_escape "$system" >> "$STAGE_DAT_MATCH"; printf ',' >> "$STAGE_DAT_MATCH"; csv_escape "$p" >> "$STAGE_DAT_MATCH"; printf ',' >> "$STAGE_DAT_MATCH"; csv_escape "$file" >> "$STAGE_DAT_MATCH"; printf ',' >> "$STAGE_DAT_MATCH"; csv_escape "$dat_name" >> "$STAGE_DAT_MATCH"; printf ',' >> "$STAGE_DAT_MATCH"; csv_escape "$dat_rom" >> "$STAGE_DAT_MATCH"; printf ',' >> "$STAGE_DAT_MATCH"; csv_escape "$dat_source" >> "$STAGE_DAT_MATCH"; printf ',' >> "$STAGE_DAT_MATCH"; csv_escape "$meta_system" >> "$STAGE_DAT_MATCH"; printf ',' >> "$STAGE_DAT_MATCH"; csv_escape "$meta_core" >> "$STAGE_DAT_MATCH"; printf ',' >> "$STAGE_DAT_MATCH"; csv_escape "$meta_folder" >> "$STAGE_DAT_MATCH"; printf ',' >> "$STAGE_DAT_MATCH"; csv_escape "$meta_region" >> "$STAGE_DAT_MATCH"; printf ',' >> "$STAGE_DAT_MATCH"; csv_escape "$meta_release" >> "$STAGE_DAT_MATCH"; printf ',' >> "$STAGE_DAT_MATCH"; csv_escape "$meta_license" >> "$STAGE_DAT_MATCH"; printf '\n' >> "$STAGE_DAT_MATCH"
      csv_escape "$system" >> "$STAGE_LOCATION_AUDIT"; printf ',' >> "$STAGE_LOCATION_AUDIT"; csv_escape "$p" >> "$STAGE_LOCATION_AUDIT"; printf ',' >> "$STAGE_LOCATION_AUDIT"; csv_escape "$dat_name" >> "$STAGE_LOCATION_AUDIT"; printf ',' >> "$STAGE_LOCATION_AUDIT"; csv_escape "$meta_system" >> "$STAGE_LOCATION_AUDIT"; printf ',' >> "$STAGE_LOCATION_AUDIT"; csv_escape "$meta_core" >> "$STAGE_LOCATION_AUDIT"; printf ',' >> "$STAGE_LOCATION_AUDIT"; csv_escape "$meta_folder" >> "$STAGE_LOCATION_AUDIT"; printf ',' >> "$STAGE_LOCATION_AUDIT"; csv_escape "$loc_status" >> "$STAGE_LOCATION_AUDIT"; printf '\n' >> "$STAGE_LOCATION_AUDIT"
    else
      SYSTEM_UNMATCHED["$system"]=$(( ${SYSTEM_UNMATCHED["$system"]:-0} + 1 ))
      csv_escape "$sha1" >> "$STAGE_DAT_UNMATCHED"; printf ',' >> "$STAGE_DAT_UNMATCHED"; csv_escape "$system" >> "$STAGE_DAT_UNMATCHED"; printf ',' >> "$STAGE_DAT_UNMATCHED"; csv_escape "$p" >> "$STAGE_DAT_UNMATCHED"; printf ',' >> "$STAGE_DAT_UNMATCHED"; csv_escape "$file" >> "$STAGE_DAT_UNMATCHED"; printf '\n' >> "$STAGE_DAT_UNMATCHED"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$p" "$sig" "${sha1,,}" "$dat_status" "$dat_name" "$dat_rom" "$dat_source" >> "$HASH_CACHE_NEW"
  fi

  # Do not perform arithmetic on filename-derived associative-array
  # subscripts here. Canonical duplicate safety is enforced later by the
  # updater's preview/apply validation; the exporter only records proposals.

  save_count=0; save_key="${stem,,}"
  if [ -n "${SAVES_BY_STEM[$save_key]:-}" ]; then
    while IFS= read -r sp; do
      [ -z "$sp" ] && continue; sf="${sp##*/}"; sext="${sf##*.}"; proposed_save="${proposed%.*}.$sext"
      csv_escape "$system" >> "$STAGE_SAVE_REN"; printf ',' >> "$STAGE_SAVE_REN"; csv_escape "$p" >> "$STAGE_SAVE_REN"; printf ',' >> "$STAGE_SAVE_REN"
      csv_escape "$sp" >> "$STAGE_SAVE_REN"; printf ',' >> "$STAGE_SAVE_REN"; csv_escape "$proposed_save" >> "$STAGE_SAVE_REN"; printf ',' >> "$STAGE_SAVE_REN"
      csv_escape "Exact original basename" >> "$STAGE_SAVE_REN"; printf ',' >> "$STAGE_SAVE_REN"; csv_escape "REVIEW ONLY" >> "$STAGE_SAVE_REN"; printf '\n' >> "$STAGE_SAVE_REN"
      save_count=$((save_count+1)); SAVE_MATCHES=$((SAVE_MATCHES+1))
    done <<< "${SAVES_BY_STEM[$save_key]}"
  fi

  printf '[%s] %s | Region: %s | Type: %s | Saves: %s | File: %s | Collision: %s\n' "$system" "$clean" "$region" "$kind" "$save_count" "$file" "$collision" >> "$STAGE_OUT"
  csv_escape "$system" >> "$STAGE_CSV"; printf ',' >> "$STAGE_CSV"; csv_escape "$clean" >> "$STAGE_CSV"; printf ',' >> "$STAGE_CSV"; csv_escape "$region" >> "$STAGE_CSV"; printf ',' >> "$STAGE_CSV"
  csv_escape "$kind" >> "$STAGE_CSV"; printf ',' >> "$STAGE_CSV"; csv_escape "$file" >> "$STAGE_CSV"; printf ',' >> "$STAGE_CSV"; csv_escape "$proposed" >> "$STAGE_CSV"; printf ',' >> "$STAGE_CSV"
  csv_escape "$p" >> "$STAGE_CSV"; printf ',' >> "$STAGE_CSV"; csv_escape "$save_count" >> "$STAGE_CSV"; printf ',' >> "$STAGE_CSV"; csv_escape "$collision" >> "$STAGE_CSV"; printf ',' >> "$STAGE_CSV"; csv_escape "$sha1" >> "$STAGE_CSV"; printf ',' >> "$STAGE_CSV"; csv_escape "$dat_status" >> "$STAGE_CSV"; printf ',' >> "$STAGE_CSV"; csv_escape "$dat_name" >> "$STAGE_CSV"; printf ',' >> "$STAGE_CSV"; csv_escape "$dat_rom" >> "$STAGE_CSV"; printf ',' >> "$STAGE_CSV"; csv_escape "$dat_source" >> "$STAGE_CSV"; printf ',' >> "$STAGE_CSV"; csv_escape "$meta_system" >> "$STAGE_CSV"; printf ',' >> "$STAGE_CSV"; csv_escape "$meta_core" >> "$STAGE_CSV"; printf ',' >> "$STAGE_CSV"; csv_escape "$meta_folder" >> "$STAGE_CSV"; printf ',' >> "$STAGE_CSV"; csv_escape "$meta_region" >> "$STAGE_CSV"; printf ',' >> "$STAGE_CSV"; csv_escape "$meta_release" >> "$STAGE_CSV"; printf ',' >> "$STAGE_CSV"; csv_escape "$meta_license" >> "$STAGE_CSV"; printf ',' >> "$STAGE_CSV"; csv_escape "$loc_status" >> "$STAGE_CSV"; printf '\n' >> "$STAGE_CSV"
  csv_escape "$system" >> "$STAGE_REN"; printf ',' >> "$STAGE_REN"; csv_escape "$p" >> "$STAGE_REN"; printf ',' >> "$STAGE_REN"; csv_escape "$proposed" >> "$STAGE_REN"; printf ',' >> "$STAGE_REN"
  csv_escape "$region" >> "$STAGE_REN"; printf ',' >> "$STAGE_REN"; csv_escape "$kind" >> "$STAGE_REN"; printf ',' >> "$STAGE_REN"; csv_escape "REVIEW ONLY" >> "$STAGE_REN"; printf '\n' >> "$STAGE_REN"
  TOTAL=$((TOTAL+1)); SYSTEM_SECONDS["$system"]=$(( ${SYSTEM_SECONDS["$system"]:-0} + SECONDS - row_seconds_start )); progress_check "Building reports" "$TOTAL" "$PLAN_TOTAL"
done
exec 3<&-

# Build title-level regional completion reports.
COMPLETION_REGION_LABEL="$(IFS=', '; echo "${COMPLETION_REGIONS[*]}")"
printf '%s\n' '"system","owned_titles","reference_titles","missing_titles","completion_percent","regions","scope"' > "$STAGE_COMPLETION"
printf '%s\n' '"system","canonical_title","region","release_type","license_status"' > "$STAGE_MISSING_COMPLETION"
while IFS= read -r c_sys; do
  [ -n "$c_sys" ] || continue
  c_total="${COMPLETION_TOTAL_BY_SYSTEM[$c_sys]:-0}"; c_owned="${COMPLETION_OWNED_BY_SYSTEM[$c_sys]:-0}"; c_missing=$((c_total-c_owned))
  c_pct="$(awk -v a="$c_owned" -v b="$c_total" 'BEGIN{if(b>0) printf "%.2f", (a*100)/b; else printf "0.00"}')"
  csv_escape "$c_sys" >> "$STAGE_COMPLETION"; printf ',' >> "$STAGE_COMPLETION"; csv_escape "$c_owned" >> "$STAGE_COMPLETION"; printf ',' >> "$STAGE_COMPLETION"
  csv_escape "$c_total" >> "$STAGE_COMPLETION"; printf ',' >> "$STAGE_COMPLETION"; csv_escape "$c_missing" >> "$STAGE_COMPLETION"; printf ',' >> "$STAGE_COMPLETION"
  csv_escape "$c_pct" >> "$STAGE_COMPLETION"; printf ',' >> "$STAGE_COMPLETION"; csv_escape "$COMPLETION_REGION_LABEL" >> "$STAGE_COMPLETION"; printf ',' >> "$STAGE_COMPLETION"
  if [ "$COMPLETION_RETAIL_ONLY" -eq 1 ]; then csv_escape "Retail releases" >> "$STAGE_COMPLETION"; else csv_escape "All release types" >> "$STAGE_COMPLETION"; fi; printf '\n' >> "$STAGE_COMPLETION"
done < <(printf '%s\n' "${!COMPLETION_TOTAL_BY_SYSTEM[@]}" | LC_ALL=C sort)

for c_key in "${!COMPLETION_REFERENCE_KEYS[@]}"; do
  [ -n "${COMPLETION_OWNED_KEYS[$c_key]+x}" ] && continue
  c_sys="${c_key%%|*}"; c_title="${c_key#*|}"
  csv_escape "$c_sys" >> "$STAGE_MISSING_COMPLETION"; printf ',' >> "$STAGE_MISSING_COMPLETION"; csv_escape "$c_title" >> "$STAGE_MISSING_COMPLETION"; printf ',' >> "$STAGE_MISSING_COMPLETION"
  csv_escape "${COMPLETION_TITLE_REGION[$c_key]:-}" >> "$STAGE_MISSING_COMPLETION"; printf ',' >> "$STAGE_MISSING_COMPLETION"; csv_escape "${COMPLETION_TITLE_RELEASE[$c_key]:-}" >> "$STAGE_MISSING_COMPLETION"; printf ',' >> "$STAGE_MISSING_COMPLETION"
  csv_escape "${COMPLETION_TITLE_LICENSE[$c_key]:-}" >> "$STAGE_MISSING_COMPLETION"; printf '\n' >> "$STAGE_MISSING_COMPLETION"
done
{ head -n 1 "$STAGE_MISSING_COMPLETION"; tail -n +2 "$STAGE_MISSING_COMPLETION" | LC_ALL=C sort; } > "$STAGE_MISSING_COMPLETION.tmp" && mv -f "$STAGE_MISSING_COMPLETION.tmp" "$STAGE_MISSING_COMPLETION"

CACHE_REFRESHED=$HASH_CALCULATED
CACHE_NOT_REUSED=$(( CACHE_ENTRIES_LOADED > HASH_REUSED ? CACHE_ENTRIES_LOADED - HASH_REUSED : 0 ))
CACHE_HIT_RATE="0.0"
if [ "$HASH_ELIGIBLE" -gt 0 ]; then CACHE_HIT_RATE=$(awk -v a="$HASH_REUSED" -v b="$HASH_ELIGIBLE" 'BEGIN{printf "%.1f", (a*100)/b}'); fi

# Refresh the cache from the CURRENT full-library scan only. Deleted files disappear;
# new/changed files have freshly calculated hashes. Cache never defines report scope.
if [ -s "$HASH_CACHE_NEW" ]; then
  mv -f "$HASH_CACHE_NEW" "$HASH_CACHE"
else
  : > "$HASH_CACHE"
fi
{
  echo "CACHE_FORMAT=$CACHE_FORMAT"
  echo "EXPORTER_VERSION=1.3"
  echo "HASH_DB_FINGERPRINT=$HASH_DB_FINGERPRINT"
  echo "UPDATED=$(date +%s)"
} > "$CACHE_META.tmp" && mv -f "$CACHE_META.tmp" "$CACHE_META"

# hash_duplicates.csv contains only hashes that occur more than once.
if [ -s "$HASH_ROWS" ]; then
  awk -F '\t' '{c[$1]++} END {for (h in c) if (c[h]>1) print h}' "$HASH_ROWS" | sort > "$WORK.duphashes"
  while IFS= read -r dh; do
    awk -F '\t' -v k="$dh" '$1==k {print}' "$HASH_ROWS" | while IFS=$'\t' read -r h hs hp hf hc; do
      csv_escape "$h" >> "$STAGE_HASH_DUP"; printf ',' >> "$STAGE_HASH_DUP"; csv_escape "$hs" >> "$STAGE_HASH_DUP"; printf ',' >> "$STAGE_HASH_DUP"; csv_escape "$hp" >> "$STAGE_HASH_DUP"; printf ',' >> "$STAGE_HASH_DUP"; csv_escape "$hf" >> "$STAGE_HASH_DUP"; printf ',' >> "$STAGE_HASH_DUP"; csv_escape "$hc" >> "$STAGE_HASH_DUP"; printf '\n' >> "$STAGE_HASH_DUP"
    done
  done < "$WORK.duphashes"
  rm -f "$WORK.duphashes"
fi

cat >> "$STAGE_OUT" <<EOF2

============================================================
Candidate game/disc files: $TOTAL
BIOS/support files skipped: $SKIPPED
Collision-affected rows made unique: $COLLISIONS
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
- USA retail titles receive the cleanest preferred filename.
- Regional and special variants retain identifying suffixes.
- Exact DAT matches use canonical DAT filenames; filename parsing is fallback-only for unmatched ROMs.
- Save matching still uses the original ROM basename and remains REVIEW ONLY.
- SHA-1 hashes identify byte-for-byte duplicate files regardless of filename.
- The bundled mister_hash_database.tsv is the single canonical hash lookup source.
- Exact DAT matches add canonical DAT title, ROM/track name, and source DAT to library_catalog.csv.
- Raw SHA-1 is tried first; safe NES/SNES header normalization is attempted only after a DAT miss. Disc containers remain outside cartridge normalization.
- Hashes are recorded locally only; no ROM data is uploaded.
- CUE/BIN and other multi-file disc sets require coordinated renaming before any future apply step.
EOF2

# Final audit integrity verdict. PASS means the report set is internally
# consistent. Warnings block Apply when cleanup would be unsafe or coverage is
# abnormally weak; FAIL means the audit itself is not trustworthy.
AUDIT_VERDICT="PASS"
APPLY_RECOMMENDATION="SAFE TO PREVIEW"
INTEGRITY_NOTES=""
MISFILED_COUNT=0
[ -s "$STAGE_LOCATION_AUDIT" ] && MISFILED_COUNT=$(grep -c ',"MISFILED"$' "$STAGE_LOCATION_AUDIT" 2>/dev/null || true)

for required_report in "$STAGE_OUT" "$STAGE_CSV" "$STAGE_REN" "$STAGE_SAVE_REN" "$STAGE_HASH_DUP" "$STAGE_DAT_MATCH" "$STAGE_DAT_UNMATCHED" "$STAGE_LOCATION_AUDIT"; do
  if [ ! -f "$required_report" ]; then
    AUDIT_VERDICT="FAIL"
    APPLY_RECOMMENDATION="DO NOT APPLY"
    INTEGRITY_NOTES="$INTEGRITY_NOTES missing-report:${required_report##*/}"
  fi
done
if [ "$TOTAL" -ne "$CLASSIFIED" ] 2>/dev/null; then
  AUDIT_VERDICT="FAIL"; APPLY_RECOMMENDATION="DO NOT APPLY"
  INTEGRITY_NOTES="$INTEGRITY_NOTES catalog-count-mismatch"
fi

# Every discovered game-library file must be accounted for as either a
# cataloged game/disc or an intentionally skipped BIOS/support file.
if [ $((TOTAL + SKIPPED)) -ne "$GAME_SCAN_COUNT" ] 2>/dev/null; then
  AUDIT_VERDICT="FAIL"; APPLY_RECOMMENDATION="DO NOT APPLY"
  INTEGRITY_NOTES="$INTEGRITY_NOTES discovery-accounting-mismatch"
fi
if [ "$DAT_MATCHED" -gt "$HASHED" ] 2>/dev/null; then
  AUDIT_VERDICT="FAIL"; APPLY_RECOMMENDATION="DO NOT APPLY"
  INTEGRITY_NOTES="$INTEGRITY_NOTES impossible-dat-count"
fi
if [ "$METADATA_LAYER_STATUS" != "MiSTer-aware" ]; then
  AUDIT_VERDICT="FAIL"; APPLY_RECOMMENDATION="DO NOT APPLY"
  INTEGRITY_NOTES="$INTEGRITY_NOTES metadata-layer-invalid"
fi

MATCH_RATE_INT=100
if [ "$HASHED" -gt 0 ]; then MATCH_RATE_INT=$((DAT_MATCHED * 100 / HASHED)); fi
if [ "$AUDIT_VERDICT" != "FAIL" ]; then
  if [ "$COLLISIONS" -gt 0 ] || [ "$MATCH_RATE_INT" -lt 50 ]; then
    AUDIT_VERDICT="PASS WITH WARNINGS"
    APPLY_RECOMMENDATION="DO NOT APPLY"
    [ "$COLLISIONS" -gt 0 ] && INTEGRITY_NOTES="$INTEGRITY_NOTES collision-review-required"
    [ "$MATCH_RATE_INT" -lt 50 ] && INTEGRITY_NOTES="$INTEGRITY_NOTES low-dat-match-rate"
  fi
fi
[ -z "$INTEGRITY_NOTES" ] && INTEGRITY_NOTES="none"

# Build one consolidated, upload-friendly report while preserving the individual
# files used by the updater. No ROM/save contents are embedded; only audit metadata.
{
  echo "MiSTer Game Library Audit Bundle v1.3"
  echo "Generated: $(date)"
  echo "READ-ONLY AUDIT REPORT - no ROM or save data is embedded."
  echo "FULL LIBRARY REPORT - audit mode: $AUDIT_MODE."
  echo "============================================================"
  echo
  echo "[RUN SUMMARY]"
  echo "Report scope: FULL LIBRARY"
  echo "Audit mode: $AUDIT_MODE"
  echo "Cache mode: $([ "$USE_HASH_CACHE" -eq 1 ] && echo "Incremental processing only" || echo "Bypassed for hash verification")"
  echo "Files discovered: $GAME_SCAN_COUNT"
  echo "Audit mode:             $AUDIT_MODE"
echo "Games/discs cataloged: $TOTAL"
  echo "BIOS/support files skipped: $SKIPPED"
  echo "Collision-affected rows: $COLLISIONS"
  echo "Save matches: $SAVE_MATCHES"
  echo "Files with SHA-1 available: $HASHED"
  echo "Hashes reused from cache: $HASH_REUSED"
  echo "Hashes calculated this run: $HASH_CALCULATED"
  echo "Unsupported-format hashes skipped: $HASH_SKIPPED"
  echo "Hash database source: $HASH_DB_SOURCE"
  echo "MiSTer-aware metadata layer: $METADATA_LAYER_STATUS"
  echo "Exporter build SHA-1: $EXPORTER_BUILD_SHA1"
  echo "Audit integrity verdict: $AUDIT_VERDICT"
  echo "Apply recommendation: $APPLY_RECOMMENDATION"
  echo "Hash records indexed: $HASH_INDEX_COUNT"
  echo "Exact DAT SHA-1 matches: $DAT_MATCHED"
  echo
  echo "[AUDIT_METADATA]"
  echo "schema_version=$AUDIT_SCHEMA_VERSION"
  echo "exporter_version=1.3"
  echo "build_sha1=$EXPORTER_BUILD_SHA1"
  echo "audit_mode=$AUDIT_MODE"
  echo "database_sha1=$HASH_DB_FINGERPRINT"
  echo "metadata_layer=$METADATA_LAYER_STATUS"
  echo "library_files=$GAME_SCAN_COUNT"
  echo "cataloged_files=$TOTAL"
  echo "self_check=$SELF_CHECK_STATUS"
  echo "integrity_verdict=$AUDIT_VERDICT"
  echo "apply_recommendation=$APPLY_RECOMMENDATION"
  echo "integrity_notes=$INTEGRITY_NOTES"
  echo
  echo "[DATABASE COVERAGE]"
  echo "DAT-eligible ROMs: $HASH_ELIGIBLE"
  echo "Matched: $DAT_MATCHED"
  echo "Unmatched: $((HASHED-DAT_MATCHED))"
  if [ "$HASHED" -gt 0 ]; then awk -v a="$DAT_MATCHED" -v b="$HASHED" 'BEGIN{printf "Match rate: %.2f%%\n", (a*100)/b}'; else echo "Match rate: 0.00%"; fi
  echo "Other/unsupported files cataloged: $HASH_SKIPPED"
  echo
  echo "[LIBRARY COMPLETION]"
  echo "Regions: $COMPLETION_REGION_LABEL"
  if [ "$COMPLETION_RETAIL_ONLY" -eq 1 ]; then echo "Scope: Retail releases only"; else echo "Scope: All release types"; fi
  echo "World releases count toward USA, Europe, and Japan when COMPLETION_INCLUDE_WORLD=1."
  tail -n +2 "$STAGE_COMPLETION" | while IFS=',' read -r c_sys c_owned c_total c_missing c_pct rest; do
    c_sys="${c_sys#\"}"; c_sys="${c_sys%\"}"; c_owned="${c_owned#\"}"; c_owned="${c_owned%\"}"; c_total="${c_total#\"}"; c_total="${c_total%\"}"; c_missing="${c_missing#\"}"; c_missing="${c_missing%\"}"; c_pct="${c_pct#\"}"; c_pct="${c_pct%\"}"
    echo "$c_sys | owned=$c_owned | reference=$c_total | missing=$c_missing | completion=$c_pct%"
  done
  echo "Missing-title detail: missing_library_titles.csv"
  echo
  echo "[CACHE HEALTH]"
  echo "Entries loaded: $CACHE_ENTRIES_LOADED"
  echo "Entries reused: $HASH_REUSED"
  echo "Entries refreshed: $CACHE_REFRESHED"
  echo "Entries not reused/expired: $CACHE_NOT_REUSED"
  echo "Cache hit rate: $CACHE_HIT_RATE%"
  echo "Database fingerprint: $HASH_DB_FINGERPRINT"
  echo
  echo "[PER-SYSTEM PROCESSING]"
  for sys in "${!SYSTEM_FILES[@]}"; do
    echo "$sys | files=${SYSTEM_FILES[$sys]} | dat_eligible=${SYSTEM_ELIGIBLE[$sys]:-0} | matched=${SYSTEM_MATCHED[$sys]:-0} | unmatched=${SYSTEM_UNMATCHED[$sys]:-0} | processing_seconds=${SYSTEM_SECONDS[$sys]:-0}"
  done | LC_ALL=C sort
  echo
  echo "[TIMING]"
  echo "discovery_seconds=$((DISCOVERY_END-DISCOVERY_START))"
  echo "save_index_seconds=$((SAVE_END-SAVE_START))"
  echo "database_cache_seconds=$((DB_END-DB_START))"
  echo "classification_seconds=$((CLASSIFY_END-CLASSIFY_START))"
  echo "parallel_full_verify_hash_seconds=$FULL_VERIFY_PARALLEL_SECONDS"
  echo "report_processing_seconds=$(( $(date +%s)-REPORT_START ))"
  echo "total_seconds_so_far=$(( $(date +%s)-START_TIME ))"
  echo
  for report in game_library.txt library_catalog.csv dat_matches.csv unmatched_hashes.csv hash_duplicates.csv location_audit.csv library_completion.csv missing_library_titles.csv proposed_renames.csv proposed_save_renames.csv; do
    echo "============================================================"
    echo "[BEGIN $report]"
    echo "============================================================"
    if [ -f "$STAGE_DIR/$report" ]; then
      cat "$STAGE_DIR/$report"
    else
      echo "(report not generated)"
    fi
    echo
    echo "[END $report]"
    echo
  done
} > "$STAGE_BUNDLE"

REPORT_END=$(date +%s)
PUBLISH_START=$REPORT_END

# Publish reports atomically, one complete file at a time. Previous reports remain
# intact until their fully generated replacements are ready.
for report in game_library.txt library_catalog.csv proposed_renames.csv proposed_save_renames.csv hash_duplicates.csv dat_matches.csv unmatched_hashes.csv location_audit.csv library_completion.csv missing_library_titles.csv MiSTer_Library_Audit.txt; do
  [ -f "$STAGE_DIR/$report" ] || continue
  mv -f "$STAGE_DIR/$report" "$AUDIT/$report"
done
PUBLISH_END=$(date +%s)
TOTAL_END=$PUBLISH_END

sync

echo
echo "+--------------------------------------------------+"
echo "| AUDIT COMPLETE                                   |"
echo "+--------------------------------------------------+"
echo " Mode              : $AUDIT_MODE"
echo " Games cataloged   : $TOTAL"
echo " DAT matches       : $DAT_MATCHED / $HASHED"
echo " Collisions        : $COLLISIONS"
echo " Save matches      : $SAVE_MATCHES"
echo " Cache hit rate    : $CACHE_HIT_RATE%"
echo " Integrity         : $AUDIT_VERDICT"
echo " Apply             : $APPLY_RECOMMENDATION"
echo "----------------------------------------------------"
echo " Reports: $AUDIT"
echo " Review : MiSTer_Library_Audit.txt"
echo " Missing: missing_library_titles.csv"
echo "----------------------------------------------------"
echo " READ ONLY: no ROMs or saves were changed."
echo "----------------------------------------------------"
echo
echo "Press Enter to close, or wait 60 seconds."
read -t 60 -r _ || true
