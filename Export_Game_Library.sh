#!/bin/bash
# Export_Game_Library_v1.0.sh
# Fast MiSTer inventory with ONE game scan + ONE save scan.
# Generates ROM/save rename proposals. It NEVER renames, moves, or deletes anything.

ROOT="/media/fat"
GAMES="$ROOT/games"
SAVES="$ROOT/saves"

OUT="$ROOT/game_library.txt"
CSV="$ROOT/library_catalog.csv"
REN="$ROOT/proposed_renames.csv"
SAVE_REN="$ROOT/proposed_save_renames.csv"

WORK="/tmp/mister_library_v10.$$"
GAME_LIST="$WORK.games"
SAVE_LIST="$WORK.saves"
SAVE_INDEX="$WORK.saveindex"

cleanup() { rm -f "$GAME_LIST" "$SAVE_LIST" "$SAVE_INDEX"; }
trap cleanup EXIT INT TERM

if [ ! -d "$GAMES" ]; then
  echo "ERROR: $GAMES was not found."
  read -p "Press Enter to exit..."
  exit 1
fi

csv_escape() {
  local s="$1"
  s="${s//\"/\"\"}"
  printf '"%s"' "$s"
}

echo
echo "MiSTer Game Library Export v1.0"
echo "================================"
echo "1/3 Scanning games..."

find "$GAMES" -type f \( \
  -iname "*.nes" -o -iname "*.fds" \
  -o -iname "*.sfc" -o -iname "*.smc" \
  -o -iname "*.gb" -o -iname "*.gbc" -o -iname "*.gba" \
  -o -iname "*.md" -o -iname "*.gen" -o -iname "*.32x" \
  -o -iname "*.sms" -o -iname "*.gg" -o -iname "*.sg" \
  -o -iname "*.pce" -o -iname "*.sgx" \
  -o -iname "*.a26" -o -iname "*.a52" -o -iname "*.a78" \
  -o -iname "*.col" -o -iname "*.int" \
  -o -iname "*.cue" -o -iname "*.chd" \
  -o -iname "*.d64" -o -iname "*.d81" -o -iname "*.g64" \
  -o -iname "*.adf" -o -iname "*.hdf" \
  -o -iname "*.dsk" -o -iname "*.tap" -o -iname "*.tzx" \
  -o -iname "*.rom" \
\) -print 2>/dev/null | sort > "$GAME_LIST"

echo "2/3 Indexing saves ONCE..."

: > "$SAVE_LIST"
: > "$SAVE_INDEX"

if [ -d "$SAVES" ]; then
  find "$SAVES" -type f \( \
    -iname "*.sav" -o -iname "*.srm" -o -iname "*.ram" \
    -o -iname "*.eep" -o -iname "*.fla" -o -iname "*.sra" \
    -o -iname "*.mcd" -o -iname "*.nv" \
  \) -print 2>/dev/null | sort > "$SAVE_LIST"

  # index format: lowercase basename-without-extension<TAB>full save path
  while IFS= read -r sp; do
    [ -z "$sp" ] && continue
    sf="${sp##*/}"
    sstem="${sf%.*}"
    printf '%s\t%s\n' "${sstem,,}" "$sp" >> "$SAVE_INDEX"
  done < "$SAVE_LIST"
  sort -o "$SAVE_INDEX" "$SAVE_INDEX"
fi

cat > "$OUT" <<EOF
MiSTer Game Library v1.0
Generated: $(date)
READ-ONLY EXPORT â no games or saves were modified.
============================================================
EOF

printf '%s\n' '"system","clean_title","region","version_type","original_filename","proposed_filename","full_path","save_match_count"' > "$CSV"
printf '%s\n' '"system","current_path","proposed_filename","region","version_type","status"' > "$REN"
printf '%s\n' '"system","game_path","save_path","proposed_save_filename","match_type","status"' > "$SAVE_REN"

TOTAL=0
SKIPPED=0
SAVE_MATCHES=0

echo "3/3 Building catalog..."

while IFS= read -r p; do
  [ -z "$p" ] && continue

  rel="${p#$GAMES/}"
  system="${rel%%/*}"
  [ "$system" = "$rel" ] && system="Unknown"

  file="${p##*/}"
  ext="${file##*.}"
  stem="${file%.*}"
  lower_path="${p,,}"
  lower_file="${file,,}"

  # Conservative support-file filter.
  case "$lower_path" in
    */bios/*|*/firmware/*|*/kickstart/*|*/system_rom/*|*/system-rom/*|*/machine_rom/*|*/machine-rom/*)
      SKIPPED=$((SKIPPED+1)); continue ;;
  esac
  case "$lower_file" in
    boot.rom|bios.rom|firmware.rom|kickstart.rom|boot.bin|bios.bin|firmware.bin)
      SKIPPED=$((SKIPPED+1)); continue ;;
  esac

  region="Unknown"
  case "$stem" in
    *"(USA)"*|*"(US)"*) region="USA" ;;
    *"(World)"*) region="World" ;;
    *"(Europe)"*|*"(EUR)"*) region="Europe" ;;
    *"(Japan)"*|*"(JPN)"*) region="Japan" ;;
    *"(Canada)"*) region="Canada" ;;
    *"(Australia)"*) region="Australia" ;;
    *"(Korea)"*) region="Korea" ;;
    *"(Brazil)"*) region="Brazil" ;;
  esac

  low="${stem,,}"
  kind="Retail/Standard"
  case "$low" in
    *translation*|*translated*|*"english patched"*|*"[t+eng"*|*"(eng"*) kind="Translation" ;;
    *homebrew*|*aftermarket*) kind="Homebrew/Aftermarket" ;;
    *hack*|*improvement*|*redux*|*randomizer*) kind="Hack/Modified" ;;
    *proto*|*prototype*|*beta*|*demo*|*sample*) kind="Prototype/Beta/Demo" ;;
    *"(rev "*|*" revision "*|*" rev "*) kind="Revision" ;;
  esac

  # Remove parenthetical/bracket metadata from display title.
  clean="$stem"
  while [[ "$clean" == *"("*")"* ]]; do
    pre="${clean%%(*}"
    rest="${clean#*(}"
    post="${rest#*)}"
    clean="$pre$post"
  done
  while [[ "$clean" == *"["*"]"* ]]; do
    pre="${clean%%[*}"
    rest="${clean#*[}"
    post="${rest#*]}"
    clean="$pre$post"
  done

  clean="${clean#"${clean%%[![:space:]]*}"}"
  clean="${clean%"${clean##*[![:space:]]}"}"
  while [[ "$clean" == *"  "* ]]; do clean="${clean//  / }"; done
  clean="${clean% -}"
  clean="${clean% _}"
  [ -z "$clean" ] && clean="$stem"

  proposed="$clean.$ext"
  save_count=0
  key="${stem,,}"

  # SAVE_INDEX is already sorted. awk scans the index without recursively
  # traversing the save directory for every game.
  if [ -s "$SAVE_INDEX" ]; then
    while IFS=$'\t' read -r dummy sp; do
      [ -z "$sp" ] && continue
      sf="${sp##*/}"
      sext="${sf##*.}"
      proposed_save="$clean.$sext"

      csv_escape "$system" >> "$SAVE_REN"; printf ',' >> "$SAVE_REN"
      csv_escape "$p" >> "$SAVE_REN"; printf ',' >> "$SAVE_REN"
      csv_escape "$sp" >> "$SAVE_REN"; printf ',' >> "$SAVE_REN"
      csv_escape "$proposed_save" >> "$SAVE_REN"; printf ',' >> "$SAVE_REN"
      csv_escape "Exact original basename" >> "$SAVE_REN"; printf ',' >> "$SAVE_REN"
      csv_escape "REVIEW ONLY" >> "$SAVE_REN"; printf '\n' >> "$SAVE_REN"

      save_count=$((save_count+1))
      SAVE_MATCHES=$((SAVE_MATCHES+1))
    done < <(awk -F '\t' -v k="$key" '$1==k {print $0}' "$SAVE_INDEX")
  fi

  printf '[%s] %s | Region: %s | Type: %s | Saves: %s | File: %s\n' \
    "$system" "$clean" "$region" "$kind" "$save_count" "$file" >> "$OUT"

  csv_escape "$system" >> "$CSV"; printf ',' >> "$CSV"
  csv_escape "$clean" >> "$CSV"; printf ',' >> "$CSV"
  csv_escape "$region" >> "$CSV"; printf ',' >> "$CSV"
  csv_escape "$kind" >> "$CSV"; printf ',' >> "$CSV"
  csv_escape "$file" >> "$CSV"; printf ',' >> "$CSV"
  csv_escape "$proposed" >> "$CSV"; printf ',' >> "$CSV"
  csv_escape "$p" >> "$CSV"; printf ',' >> "$CSV"
  csv_escape "$save_count" >> "$CSV"; printf '\n' >> "$CSV"

  csv_escape "$system" >> "$REN"; printf ',' >> "$REN"
  csv_escape "$p" >> "$REN"; printf ',' >> "$REN"
  csv_escape "$proposed" >> "$REN"; printf ',' >> "$REN"
  csv_escape "$region" >> "$REN"; printf ',' >> "$REN"
  csv_escape "$kind" >> "$REN"; printf ',' >> "$REN"
  csv_escape "REVIEW ONLY" >> "$REN"; printf '\n' >> "$REN"

  TOTAL=$((TOTAL+1))
  if (( TOTAL % 1000 == 0 )); then
    echo "    Processed $TOTAL games..."
  fi
done < "$GAME_LIST"

cat >> "$OUT" <<EOF

============================================================
Candidate game/disc files: $TOTAL
Obvious BIOS/support files skipped: $SKIPPED
Corresponding save-file matches found: $SAVE_MATCHES

Created:
  game_library.txt
  library_catalog.csv
  proposed_renames.csv
  proposed_save_renames.csv

IMPORTANT:
- Nothing was renamed, moved, or deleted.
- Save matching uses the original ROM basename.
- Rename proposals preserve the save extension.
- CUE/BIN and other multi-file disc sets require coordinated renaming.
- Review duplicate/collision cases before applying a future rename plan.
EOF

sync

echo
echo "========================================"
echo " MiSTer LIBRARY EXPORT v1.0 COMPLETE"
echo "========================================"
echo "Games/discs cataloged: $TOTAL"
echo "Support files skipped: $SKIPPED"
echo "Save matches:          $SAVE_MATCHES"
echo
echo "Created in /media/fat:"
echo "  game_library.txt"
echo "  library_catalog.csv"
echo "  proposed_renames.csv"
echo "  proposed_save_renames.csv"
echo
echo "READ-ONLY: your ROMs and saves were not changed."
echo
read -p "Press Enter to exit..."