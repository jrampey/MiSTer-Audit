from pathlib import Path

path = Path('Export_Game_Library.sh')
text = path.read_text()

def replace_once(old, new, label):
    global text
    if old not in text:
        raise SystemExit(f'Expected block not found: {label}')
    text = text.replace(old, new, 1)

replace_once("""stop_spinner() {
  if [ -n \"$SPINNER_PID\" ]; then
    kill \"$SPINNER_PID\" 2>/dev/null || true
    wait \"$SPINNER_PID\" 2>/dev/null || true
    SPINNER_PID=\"\"
    printf '\\r\\033[K'
  fi
}
""", """stop_spinner() {
  if [ -n \"$SPINNER_PID\" ]; then
    kill \"$SPINNER_PID\" 2>/dev/null || true
    wait \"$SPINNER_PID\" 2>/dev/null || true
    SPINNER_PID=\"\"
    printf '\\r%79s\\r' ' '
  fi
}
""", 'spinner ANSI clear')

replace_once("""    printf '\\r\\033[K'
    printf '[%02d:%02d] [OK] %s - %s / %s (%s%%)' $((elapsed/60)) $((elapsed%60)) \"$stage\" \"$current\" \"$total\" \"$pct\"
""", """    printf '\\r%79s\\r' ' '
    printf '[%02d:%02d] %s: %s / %s (%s%%)' $((elapsed/60)) $((elapsed%60)) \"$stage\" \"$current\" \"$total\" \"$pct\"
""", 'progress ANSI clear')

replace_once("""echo \"MiSTer Game Library Export v1.3\"
echo \"================================\"
""", """echo \"+--------------------------------------------------+\"
echo \"| MiSTer ROM Library Auditor v1.3                 |\"
echo \"| Read-only audit - no ROMs or saves are changed  |\"
echo \"+--------------------------------------------------+\"
echo
""", 'startup banner')

replace_once("""render_audit_menu() {
  local fast_prefix=\"  \" full_prefix=\"  \"
  [ \"$AUDIT_MENU_SELECTION\" -eq 1 ] && fast_prefix=\"> \" || full_prefix=\"> \"
  printf \"Select audit mode (Up = run Fast, Down = run Full, Enter = Fast):\\n\"
  printf \"Fast Audit will start automatically in 15 seconds.\\n\"
  printf \"%s1) Fast Audit (recommended)\\n\" \"$fast_prefix\"
  printf \"     Full-library scan; reuses valid cached hashes.\\n\"
  printf \"%s2) Full Verification\\n\" \"$full_prefix\"
  printf \"     Full-library scan; recalculates every supported SHA-1.\\n\"
}
""", """render_audit_menu() {
  local fast_prefix=\"  \" full_prefix=\"  \"
  [ \"$AUDIT_MENU_SELECTION\" -eq 1 ] && fast_prefix=\"> \" || full_prefix=\"> \"
  printf \"+--------------------------------------------------+\\n\"
  printf \"| AUDIT MODE                                       |\\n\"
  printf \"+--------------------------------------------------+\\n\"
  printf \"%s1) Fast Audit - recommended\\n\" \"$fast_prefix\"
  printf \"     Reuse valid cached hashes.\\n\"
  printf \"%s2) Full Verification\\n\" \"$full_prefix\"
  printf \"     Recalculate every supported SHA-1.\\n\"
  printf \"----------------------------------------------------\\n\"
  printf \"1/2 or arrows select | Enter = Fast | Auto = 15s\\n\"
}
""", 'audit menu')

replace_once('echo "Audit mode: $AUDIT_MODE"\necho\n', 'echo "Selected: $AUDIT_MODE"\necho "----------------------------------------------------"\necho\n', 'selected mode')

for old, new in [
    ('echo "1/5 Scanning games..."', 'echo "[1/5] Scanning game library..."'),
    ('echo "2/5 Indexing saves once..."', 'echo "[2/5] Indexing save files..."'),
    ('echo "3/5 Loading bundled hash database..."', 'echo "[3/5] Loading hash database..."'),
    ('echo "4/5 Classifying titles and checking collisions..."', 'echo "[4/5] Classifying titles and collisions..."'),
    ('echo "5/5 Building reports..."', 'echo "[5/5] Building audit reports..."'),
]:
    replace_once(old, new, old)

start = '''echo
echo "========================================"
echo " MiSTer LIBRARY EXPORT v1.3 COMPLETE"
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
echo "DAT-eligible ROMs:      $HASH_ELIGIBLE"
echo "Cache hit rate:         $CACHE_HIT_RATE%"
echo "Self-check:             $SELF_CHECK_STATUS"
echo "Integrity verdict:      $AUDIT_VERDICT"
echo "Apply recommendation:   $APPLY_RECOMMENDATION"
echo "Build SHA-1:             $EXPORTER_BUILD_SHA1"
echo
echo "Created in $AUDIT:"
echo "  game_library.txt"
echo "  library_catalog.csv"
echo "  hash_cache.tsv  (internal incremental cache; full library is still rescanned)"
echo "  proposed_renames.csv"
echo "  proposed_save_renames.csv"
echo "  hash_duplicates.csv"
echo "  dat_matches.csv"
echo "  location_audit.csv"
echo "  unmatched_hashes.csv"
echo "  library_completion.csv"
echo "  missing_library_titles.csv"
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
echo "- Audit mode: $AUDIT_MODE."
echo "- Reused $HASH_REUSED unchanged SHA-1 hashes from cache."
echo "- Calculated $HASH_CALCULATED new/changed SHA-1 hashes."
echo "- Skipped hashing $HASH_SKIPPED unsupported formats while still cataloging them."
echo "- Matched $DAT_MATCHED files against $HASH_INDEX_COUNT reference hash records."
echo "- Found $COLLISIONS collision-affected catalog rows."
echo "- Matched $SAVE_MATCHES save files to game basenames."
echo "- Generated audit reports and cleanup proposals in $AUDIT."
echo "- Displayed a live 1-second activity indicator and 30-second progress checkpoints."
echo "- Created MiSTer_Library_Audit.txt for easy upload/review."
echo "- Timing: discovery $((DISCOVERY_END-DISCOVERY_START))s; saves $((SAVE_END-SAVE_START))s; DB/cache $((DB_END-DB_START))s; classification $((CLASSIFY_END-CLASSIFY_START))s; report/hash $((REPORT_END-REPORT_START))s; total $((TOTAL_END-START_TIME))s."
echo "- No games or saves were renamed, moved, or deleted."
echo
echo "This screen will close automatically in 60 seconds."
echo "Press Enter to close now."
read -t 60 -r _ || true'''

end = '''echo
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
read -t 60 -r _ || true'''
replace_once(start, end, 'completion screen')

# Ensure the script source itself contains only ASCII characters.
try:
    text.encode('ascii')
except UnicodeEncodeError as exc:
    raise SystemExit(f'Non-ASCII character remains at offset {exc.start}')

path.write_text(text)
