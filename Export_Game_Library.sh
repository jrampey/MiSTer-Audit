#!/bin/bash
# Export_Game_Library_v1.2.sh
# MiSTer library audit/export. READ ONLY: never renames, moves, or deletes games/saves.
# v1.2 improves region/version parsing, BIOS/support filtering, title normalization,
# collision-safe proposals, ROM hashing, bundled TSV hash matching, and stores all reports in /media/fat/GameLibraryAudit.

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

cleanup() { rm -f "$GAME_LIST" "$SAVE_LIST" "$SAVE_INDEX" "$PLAN" "$DAT_INDEX" "$HASH_ROWS" "$HASH_CACHE_NEW" "$WORK.duphashes"; }
trap cleanup EXIT INT TERM

if [ ! -d "$GAMES" ]; then
  echo "ERROR: $GAMES was not found."
  read -p "Press Enter to exit..."
  exit 1
fi
mkdir -p "$AUDIT" || exit 1

hash_file() {
  local p="$1"
  if command -v sha1sum >/dev/null 2>&1; then
    sha1sum "$p" 2>/dev/null | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl sha1 "$p" 2>/dev/null | awk '{print $NF}'
  else
    printf 'UNAVAILABLE'
  fi
}


file_signature() {
  local p="$1" sig
  # GNU/BSD stat compatibility. Size + mtime is used only to decide whether a
  # previously calculated SHA-1 can be reused; every run still rescans the full library.
  sig="$(stat -c '%s|%Y' "$p" 2>/dev/null)"
  [ -z "$sig" ] && sig="$(stat -f '%z|%m' "$p" 2>/dev/null)"
  printf '%s' "$sig"
}

cache_lookup() {
  local p="$1" sig="$2"
  [ -s "$HASH_CACHE" ] || return 0
  awk -F '\t' -v p="$p" -v s="$sig" '$1==p && $2==s {print $3; exit}' "$HASH_CACHE"
}

should_hash() {
  local system="${1,,}" ext="${2,,}"
  # The bundled v1.2 reference database currently identifies Nintendo cartridge/disk
  # formats. Avoid expensive hashing of large unsupported CHD/computer/disc containers.
  case "$ext" in
    nes|fds|sfc|smc|gb|gbc|gba|n64|z64|v64) return 0 ;;
  esac
  # Existing library exporter may classify N64 files under generic .rom in some sets.
  case "$system" in
    *n64*|*nintendo*64*) [ "$ext" = "rom" ] && return 0 ;;
  esac
  return 1
}


# Build the local SHA-1 lookup exclusively from the bundled TSV database
# stored next to this script. Legacy XML DAT-folder parsing was removed in v1.2.
build_dat_index() {
  : > "$DAT_INDEX"
  HASH_DB_SOURCE="None"

  if [ -f "$HASH_DB_TSV" ]; then
    echo "    Using bundled hash database: $HASH_DB_TSV"
    awk -F '\t' 'NR>1 {
      h=tolower($1)
      if (h ~ /^[0-9a-f]+$/ && length(h)==40)
        print h "\t" $2 "\t" $3 "\t" $4
    }' "$HASH_DB_TSV" > "$DAT_INDEX"
    HASH_DB_SOURCE="mister_hash_database.tsv"
  else
    echo "    WARNING: $HASH_DB_TSV was not found. Hashes will still be calculated, but canonical matching will be unavailable."
  fi

  [ -s "$DAT_INDEX" ] && LC_ALL=C sort -t $'\t' -k1,1 -u -o "$DAT_INDEX" "$DAT_INDEX"
}

dat_lookup() {
  local h="${1,,}"
  [ -s "$DAT_INDEX" ] || return 0
  # DAT index is sorted by SHA-1; awk is used for broad MiSTer compatibility.
  awk -F '\t' -v k="$h" '$1==k {print; exit}' "$DAT_INDEX"
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
  local s="$1" old
  # Strip metadata blocks, but keep parenthetical/bracket text that looks like part of the title.
  old=""
  while [ "$old" != "$s" ]; do
    old="$s"
    s="$(printf '%s' "$s" | sed -E \
      -e 's/[[:space:]]*\((USA|US|U|World|W|Europe|EUR|E|Japan|JPN|J|Canada|CAN|Australia|AUS|Korea|KOR|Brazil|BRA|UE|U,E|U\+E)\)//Ig' \
      -e 's/[[:space:]]*\((Rev(ision)?[[:space:]._-]*[0-9A-Za-z]+|Proto(type)?|Beta|Demo|Sample|Unl(icensed)?|Homebrew|Aftermarket|Translation|Translated|Eng(lish)?[^)]*)\)//Ig' \
      -e 's/[[:space:]]*\[[!a-zA-Z0-9+._ -]*(t[^]]*|h[^]]*|!|b[0-9]*|o[0-9]*|f[0-9]*|p[0-9]*|a[0-9]*|c|x)[^]]*\]//Ig')"
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

# Live activity spinner plus a detailed progress heartbeat every 30 seconds.
START_TIME=$(date +%s)
LAST_PROGRESS_TIME=$START_TIME
SPINNER_PID=""

start_spinner() {
  [ -n "$SPINNER_PID" ] && return
  (
    frames='|/-\\'
    i=0
    while :; do
      now=$(date +%s)
      elapsed=$((now - START_TIME))
      frame=$(printf '%s' "$frames" | cut -c $((i % 4 + 1)))
      printf '\r[%02d:%02d] %s Still working... ' $((elapsed/60)) $((elapsed%60)) "$frame"
      i=$((i+1))
      sleep 1
    done
  ) &
  SPINNER_PID=$!
}

stop_spinner() {
  if [ -n "$SPINNER_PID" ]; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
    printf '\r\033[K'
  fi
}

trap 'stop_spinner' EXIT INT TERM

progress_check() {
  local stage="$1" current="${2:-0}" total="${3:-0}" now elapsed pct
  now=$(date +%s)
  if [ $((now - LAST_PROGRESS_TIME)) -ge 30 ]; then
    elapsed=$((now - START_TIME))
    pct=0
    if [ "$total" -gt 0 ] 2>/dev/null; then pct=$((current * 100 / total)); fi
    printf '\r\033[K'
    printf '[%02d:%02d] [OK] %s - %s / %s (%s%%)' $((elapsed/60)) $((elapsed%60)) "$stage" "$current" "$total" "$pct"
    if [ "$stage" = "Building reports" ]; then
      printf ' | DAT matches: %s | Unmatched: %s' "${DAT_MATCHED:-0}" "$(( ${HASHED:-0} - ${DAT_MATCHED:-0} ))"
    fi
    printf '\n'
    LAST_PROGRESS_TIME=$now
  fi
}

echo
echo "MiSTer Game Library Export v1.2"
echo "================================"
start_spinner
echo "1/5 Scanning games..."
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

echo "2/5 Indexing saves once..."
: > "$SAVE_LIST"; : > "$SAVE_INDEX"
SAVE_PROCESSED=0
if [ -d "$SAVES" ]; then
  find "$SAVES" -type f \( -iname "*.sav" -o -iname "*.srm" -o -iname "*.ram" -o -iname "*.eep" -o -iname "*.fla" -o -iname "*.sra" -o -iname "*.mcd" -o -iname "*.nv" \) -print 2>/dev/null | sort > "$SAVE_LIST"
  SAVE_SCAN_COUNT=$(wc -l < "$SAVE_LIST" | tr -d "[:space:]"); [ -z "$SAVE_SCAN_COUNT" ] && SAVE_SCAN_COUNT=0
  while IFS= read -r sp; do
    [ -z "$sp" ] && continue; sf="${sp##*/}"; sstem="${sf%.*}"
    printf '%s\t%s\n' "${sstem,,}" "$sp" >> "$SAVE_INDEX"
    SAVE_PROCESSED=$((SAVE_PROCESSED+1)); progress_check "Indexing saves" "$SAVE_PROCESSED" "$SAVE_SCAN_COUNT"
  done < "$SAVE_LIST"
  sort -o "$SAVE_INDEX" "$SAVE_INDEX"
fi

echo "3/5 Loading bundled hash database..."
build_dat_index
HASH_INDEX_COUNT=$(wc -l < "$DAT_INDEX" 2>/dev/null | tr -d "[:space:]")
[ -z "$HASH_INDEX_COUNT" ] && HASH_INDEX_COUNT=0
echo "    Hash database source: $HASH_DB_SOURCE"
echo "    Hash records indexed: $HASH_INDEX_COUNT"

# First pass builds metadata and collision counts.
echo "4/5 Classifying titles and checking collisions..."
: > "$PLAN"
declare -A NAME_COUNTS
SKIPPED=0; CLASSIFIED=0
while IFS= read -r p; do
  [ -z "$p" ] && continue
  rel="${p#$GAMES/}"; system="${rel%%/*}"; [ "$system" = "$rel" ] && system="Unknown"
  file="${p##*/}"; ext="${file##*.}"; stem="${file%.*}"
  if is_support_file "$p" "$file"; then SKIPPED=$((SKIPPED+1)); continue; fi
  region="$(region_of "$stem")"; kind="$(kind_of "$stem")"; clean="$(clean_title "$stem")"
  suffix="$(suffix_for "$region" "$kind")"; proposed="$clean$suffix.$ext"
  key="${system,,}|${proposed,,}"
  NAME_COUNTS["$key"]=$(( ${NAME_COUNTS["$key"]:-0} + 1 ))
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$system" "$p" "$file" "$ext" "$stem" "$clean" "$region" "$kind" >> "$PLAN"
  CLASSIFIED=$((CLASSIFIED+1)); progress_check "Classifying titles" "$CLASSIFIED" "$GAME_SCAN_COUNT"
done < "$GAME_LIST"

cat > "$OUT" <<EOF2
MiSTer Game Library v1.2
Generated: $(date)
READ-ONLY EXPORT - no games or saves were modified.
Reports folder: $AUDIT
============================================================
EOF2
printf '%s\n' '"system","clean_title","region","version_type","original_filename","proposed_filename","full_path","save_match_count","collision_status","sha1","dat_match","dat_canonical_name","dat_rom_name","dat_source"' > "$CSV"
printf '%s\n' '"system","current_path","proposed_filename","region","version_type","status"' > "$REN"
printf '%s\n' '"system","game_path","save_path","proposed_save_filename","match_type","status"' > "$SAVE_REN"
printf '%s\n' '"sha1","system","full_path","original_filename","clean_title"' > "$HASH_DUP"
printf '%s\n' '"sha1","system","full_path","original_filename","canonical_name","dat_rom_name","dat_source"' > "$DAT_MATCH"
printf '%s\n' '"sha1","system","full_path","original_filename"' > "$DAT_UNMATCHED"
: > "$HASH_ROWS"

TOTAL=0; SAVE_MATCHES=0; COLLISIONS=0; HASHED=0; DAT_MATCHED=0; HASH_REUSED=0; HASH_CALCULATED=0; HASH_SKIPPED=0
: > "$HASH_CACHE_NEW"
declare -A SEEN_NAMES

echo "5/5 Building reports..."
PLAN_TOTAL=$(wc -l < "$PLAN" | tr -d "[:space:]"); [ -z "$PLAN_TOTAL" ] && PLAN_TOTAL=0
while IFS=$'\t' read -r system p file ext stem clean region kind; do
  [ -z "$p" ] && continue
  suffix="$(suffix_for "$region" "$kind")"; base="$clean$suffix"; proposed="$base.$ext"
  key="${system,,}|${proposed,,}"; collision="None"
  if [ "${NAME_COUNTS["$key"]:-0}" -gt 1 ]; then
    # Keep every proposal unique without discarding source metadata.
    n=$(( ${SEEN_NAMES["$key"]:-0} + 1 )); SEEN_NAMES["$key"]=$n
    proposed="$base [Variant $n].$ext"; collision="Resolved variant $n of ${NAME_COUNTS["$key"]}"
    COLLISIONS=$((COLLISIONS+1))
  fi

  sha1=""; dat_status="Not applicable"; dat_name=""; dat_rom=""; dat_source=""
  if should_hash "$system" "$ext"; then
    sig="$(file_signature "$p")"
    cached_sha="$(cache_lookup "$p" "$sig")"
    if [ -n "$cached_sha" ]; then
      sha1="$cached_sha"
      HASH_REUSED=$((HASH_REUSED+1))
    else
      sha1="$(hash_file "$p")"
      [ -n "$sha1" ] && [ "$sha1" != "UNAVAILABLE" ] && HASH_CALCULATED=$((HASH_CALCULATED+1))
    fi
    if [ -n "$sha1" ] && [ "$sha1" != "UNAVAILABLE" ]; then
      printf '%s\t%s\t%s\n' "$p" "$sig" "${sha1,,}" >> "$HASH_CACHE_NEW"
    fi
    dat_status="No match"
  else
    HASH_SKIPPED=$((HASH_SKIPPED+1))
  fi
  if [ -n "$sha1" ] && [ "$sha1" != "UNAVAILABLE" ]; then
    HASHED=$((HASHED+1))
    printf '%s\t%s\t%s\t%s\t%s\n' "${sha1,,}" "$system" "$p" "$file" "$clean" >> "$HASH_ROWS"
    dat_line="$(dat_lookup "$sha1")"
    if [ -n "$dat_line" ]; then
      IFS=$'\t' read -r _ dat_name dat_rom dat_source <<< "$dat_line"
      dat_status="Exact SHA-1"; DAT_MATCHED=$((DAT_MATCHED+1))
      csv_escape "$sha1" >> "$DAT_MATCH"; printf ',' >> "$DAT_MATCH"; csv_escape "$system" >> "$DAT_MATCH"; printf ',' >> "$DAT_MATCH"; csv_escape "$p" >> "$DAT_MATCH"; printf ',' >> "$DAT_MATCH"; csv_escape "$file" >> "$DAT_MATCH"; printf ',' >> "$DAT_MATCH"; csv_escape "$dat_name" >> "$DAT_MATCH"; printf ',' >> "$DAT_MATCH"; csv_escape "$dat_rom" >> "$DAT_MATCH"; printf ',' >> "$DAT_MATCH"; csv_escape "$dat_source" >> "$DAT_MATCH"; printf '\n' >> "$DAT_MATCH"
    else
      csv_escape "$sha1" >> "$DAT_UNMATCHED"; printf ',' >> "$DAT_UNMATCHED"; csv_escape "$system" >> "$DAT_UNMATCHED"; printf ',' >> "$DAT_UNMATCHED"; csv_escape "$p" >> "$DAT_UNMATCHED"; printf ',' >> "$DAT_UNMATCHED"; csv_escape "$file" >> "$DAT_UNMATCHED"; printf '\n' >> "$DAT_UNMATCHED"
    fi
  fi

  save_count=0; save_key="${stem,,}"
  if [ -s "$SAVE_INDEX" ]; then
    while IFS=$'\t' read -r dummy sp; do
      [ -z "$sp" ] && continue; sf="${sp##*/}"; sext="${sf##*.}"; proposed_save="${proposed%.*}.$sext"
      csv_escape "$system" >> "$SAVE_REN"; printf ',' >> "$SAVE_REN"; csv_escape "$p" >> "$SAVE_REN"; printf ',' >> "$SAVE_REN"
      csv_escape "$sp" >> "$SAVE_REN"; printf ',' >> "$SAVE_REN"; csv_escape "$proposed_save" >> "$SAVE_REN"; printf ',' >> "$SAVE_REN"
      csv_escape "Exact original basename" >> "$SAVE_REN"; printf ',' >> "$SAVE_REN"; csv_escape "REVIEW ONLY" >> "$SAVE_REN"; printf '\n' >> "$SAVE_REN"
      save_count=$((save_count+1)); SAVE_MATCHES=$((SAVE_MATCHES+1))
    done < <(awk -F '\t' -v k="$save_key" '$1==k {print $0}' "$SAVE_INDEX")
  fi

  printf '[%s] %s | Region: %s | Type: %s | Saves: %s | File: %s | Collision: %s\n' "$system" "$clean" "$region" "$kind" "$save_count" "$file" "$collision" >> "$OUT"
  csv_escape "$system" >> "$CSV"; printf ',' >> "$CSV"; csv_escape "$clean" >> "$CSV"; printf ',' >> "$CSV"; csv_escape "$region" >> "$CSV"; printf ',' >> "$CSV"
  csv_escape "$kind" >> "$CSV"; printf ',' >> "$CSV"; csv_escape "$file" >> "$CSV"; printf ',' >> "$CSV"; csv_escape "$proposed" >> "$CSV"; printf ',' >> "$CSV"
  csv_escape "$p" >> "$CSV"; printf ',' >> "$CSV"; csv_escape "$save_count" >> "$CSV"; printf ',' >> "$CSV"; csv_escape "$collision" >> "$CSV"; printf ',' >> "$CSV"; csv_escape "$sha1" >> "$CSV"; printf ',' >> "$CSV"; csv_escape "$dat_status" >> "$CSV"; printf ',' >> "$CSV"; csv_escape "$dat_name" >> "$CSV"; printf ',' >> "$CSV"; csv_escape "$dat_rom" >> "$CSV"; printf ',' >> "$CSV"; csv_escape "$dat_source" >> "$CSV"; printf '\n' >> "$CSV"
  csv_escape "$system" >> "$REN"; printf ',' >> "$REN"; csv_escape "$p" >> "$REN"; printf ',' >> "$REN"; csv_escape "$proposed" >> "$REN"; printf ',' >> "$REN"
  csv_escape "$region" >> "$REN"; printf ',' >> "$REN"; csv_escape "$kind" >> "$REN"; printf ',' >> "$REN"; csv_escape "REVIEW ONLY" >> "$REN"; printf '\n' >> "$REN"
  TOTAL=$((TOTAL+1)); progress_check "Building reports" "$TOTAL" "$PLAN_TOTAL"
done < "$PLAN"

# Refresh the cache from the CURRENT full-library scan only. Deleted files disappear;
# new/changed files have freshly calculated hashes. Cache never defines report scope.
if [ -s "$HASH_CACHE_NEW" ]; then
  mv -f "$HASH_CACHE_NEW" "$HASH_CACHE"
else
  : > "$HASH_CACHE"
fi

# hash_duplicates.csv contains only hashes that occur more than once.
if [ -s "$HASH_ROWS" ]; then
  awk -F '\t' '{c[$1]++} END {for (h in c) if (c[h]>1) print h}' "$HASH_ROWS" | sort > "$WORK.duphashes"
  while IFS= read -r dh; do
    awk -F '\t' -v k="$dh" '$1==k {print}' "$HASH_ROWS" | while IFS=$'\t' read -r h hs hp hf hc; do
      csv_escape "$h" >> "$HASH_DUP"; printf ',' >> "$HASH_DUP"; csv_escape "$hs" >> "$HASH_DUP"; printf ',' >> "$HASH_DUP"; csv_escape "$hp" >> "$HASH_DUP"; printf ',' >> "$HASH_DUP"; csv_escape "$hf" >> "$HASH_DUP"; printf ',' >> "$HASH_DUP"; csv_escape "$hc" >> "$HASH_DUP"; printf '\n' >> "$HASH_DUP"
    done
  done < "$WORK.duphashes"
  rm -f "$WORK.duphashes"
fi

cat >> "$OUT" <<EOF2

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
  MiSTer_Library_Audit.txt  (single file to upload for review)

IMPORTANT:
- Nothing was renamed, moved, or deleted.
- USA retail titles receive the cleanest preferred filename.
- Regional and special variants retain identifying suffixes.
- Duplicate proposals receive deterministic [Variant N] suffixes for review.
- Save matching still uses the original ROM basename and remains REVIEW ONLY.
- SHA-1 hashes identify byte-for-byte duplicate files regardless of filename.
- The bundled mister_hash_database.tsv is the single canonical hash lookup source.
- Exact DAT matches add canonical DAT title, ROM/track name, and source DAT to library_catalog.csv.
- Raw whole-file SHA-1 matching may not identify headered ROMs or container formats such as CHD/CUE when a DAT hashes normalized ROM data or individual disc tracks.
- Hashes are recorded locally only; no ROM data is uploaded.
- CUE/BIN and other multi-file disc sets require coordinated renaming before any future apply step.
EOF2

# Build one consolidated, upload-friendly report while preserving the individual
# files used by the updater. No ROM/save contents are embedded; only audit metadata.
{
  echo "MiSTer Game Library Audit Bundle v1.2"
  echo "Generated: $(date)"
  echo "READ-ONLY AUDIT REPORT - no ROM or save data is embedded."
  echo "FULL LIBRARY REPORT - cache is used only to avoid recalculating unchanged hashes."
  echo "============================================================"
  echo
  echo "[RUN SUMMARY]"
  echo "Report scope: FULL LIBRARY"
  echo "Cache mode: Incremental processing only"
  echo "Files discovered: $GAME_SCAN_COUNT"
  echo "Games/discs cataloged: $TOTAL"
  echo "BIOS/support files skipped: $SKIPPED"
  echo "Collision-affected rows: $COLLISIONS"
  echo "Save matches: $SAVE_MATCHES"
  echo "Files with SHA-1 available: $HASHED"
  echo "Hashes reused from cache: $HASH_REUSED"
  echo "Hashes calculated this run: $HASH_CALCULATED"
  echo "Unsupported-format hashes skipped: $HASH_SKIPPED"
  echo "Hash database source: $HASH_DB_SOURCE"
  echo "Hash records indexed: $HASH_INDEX_COUNT"
  echo "Exact DAT SHA-1 matches: $DAT_MATCHED"
  echo
  for report in game_library.txt library_catalog.csv dat_matches.csv unmatched_hashes.csv hash_duplicates.csv proposed_renames.csv proposed_save_renames.csv; do
    echo "============================================================"
    echo "[BEGIN $report]"
    echo "============================================================"
    if [ -f "$AUDIT/$report" ]; then
      cat "$AUDIT/$report"
    else
      echo "(report not generated)"
    fi
    echo
    echo "[END $report]"
    echo
  done
} > "$BUNDLE"

sync
stop_spinner

echo
echo "========================================"
echo " MiSTer LIBRARY EXPORT v1.2 COMPLETE"
echo "========================================"
echo "Games/discs cataloged: $TOTAL"
echo "Support files skipped: $SKIPPED"
echo "Collision rows:        $COLLISIONS"
echo "Save matches:          $SAVE_MATCHES"
echo "Files with SHA-1:       $HASHED"
echo "Hashes reused:          $HASH_REUSED"
echo "Hashes calculated:      $HASH_CALCULATED"
echo "Unsupported hash skips: $HASH_SKIPPED"
echo "Hash DB source:          $HASH_DB_SOURCE"
echo "Hash records indexed:    $HASH_INDEX_COUNT"
echo "Exact DAT matches:      $DAT_MATCHED"
echo
echo "Created in $AUDIT:"
echo "  game_library.txt"
echo "  library_catalog.csv"
echo "  hash_cache.tsv  (internal incremental cache; full library is still rescanned)"
echo "  proposed_renames.csv"
echo "  proposed_save_renames.csv"
echo "  hash_duplicates.csv"
echo "  dat_matches.csv"
echo "  unmatched_hashes.csv"
echo "  MiSTer_Library_Audit.txt  <-- upload this one for review"
echo
echo "READ-ONLY: your ROMs and saves were not changed."
echo
echo "----------------------------------------"
echo " SUMMARY OF WHAT WAS DONE"
echo "----------------------------------------"
echo "- Scanned /media/fat/games and cataloged $TOTAL game/disc files."
echo "- Skipped $SKIPPED detected BIOS/support files."
echo "- Full-library scan completed: $GAME_SCAN_COUNT files discovered and $TOTAL games/discs cataloged."
echo "- Reused $HASH_REUSED unchanged SHA-1 hashes from cache."
echo "- Calculated $HASH_CALCULATED new/changed SHA-1 hashes."
echo "- Skipped hashing $HASH_SKIPPED unsupported formats while still cataloging them."
echo "- Matched $DAT_MATCHED files against $HASH_INDEX_COUNT reference hash records."
echo "- Found $COLLISIONS collision-affected catalog rows."
echo "- Matched $SAVE_MATCHES save files to game basenames."
echo "- Generated audit reports and cleanup proposals in $AUDIT."
echo "- Displayed a live 1-second activity indicator and 30-second progress checkpoints."
echo "- Created MiSTer_Library_Audit.txt for easy upload/review."
echo "- No games or saves were renamed, moved, or deleted."
echo
echo "This screen will close automatically in 60 seconds."
echo "Press Enter to close now."
read -t 60 -r _ || true