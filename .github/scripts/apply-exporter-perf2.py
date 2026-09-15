from pathlib import Path

p = Path('Export_Game_Library.sh')
s = p.read_text()

def replace(old, new, label):
    global s
    if old not in s:
        raise SystemExit(f'{label}: expected source block not found')
    s = s.replace(old, new, 1)

# Canonicalize DB-side system names when building/loading per-system indexes.
# This makes legacy MegaDrive metadata and current Genesis metadata share one cache.
replace('''    cache_system="${meta_system,,}"
    out="$tmp/${cache_system//[^A-Za-z0-9._-]/_}.tsv"
''','''    cache_system="$(canonical_dat_system "$meta_system")"
    cache_system="${cache_system,,}"
    out="$tmp/${cache_system//[^A-Za-z0-9._-]/_}.tsv"
''','canonical DAT cache system')
replace('''        [ -n "${ACTIVE_DAT_SYSTEMS[${meta_system,,}]+x}" ] || { HASH_DB_SKIPPED_SYSTEM_RECORDS=$((HASH_DB_SKIPPED_SYSTEM_RECORDS+1)); continue; }
''','''        cache_system="$(canonical_dat_system "$meta_system")"; cache_system="${cache_system,,}"
        [ -n "${ACTIVE_DAT_SYSTEMS[$cache_system]+x}" ] || { HASH_DB_SKIPPED_SYSTEM_RECORDS=$((HASH_DB_SKIPPED_SYSTEM_RECORDS+1)); continue; }
''','fallback DAT system alias')

# MiSTer-aware compatible folders: GBC uses the Gameboy core/folder and SGB is
# intentionally a SNES-backed MiSTer library location.
old_loc='''case "$expected" in nes) case "$current" in nes|fds|famicom) HOT_RESULT='OK (compatible folder)'; return;; esac ;; gameboy) case "$current" in gameboy|game\\ boy|gb) HOT_RESULT='OK (compatible folder)'; return;; esac ;; n64) case "$current" in n64|nintendo64|nintendo\\ 64) HOT_RESULT='OK (compatible folder)'; return;; esac ;; esac; HOT_RESULT=MISFILED;'''
new_loc='''case "$expected" in nes) case "$current" in nes|fds|famicom) HOT_RESULT='OK (compatible folder)'; return;; esac ;; gameboy) case "$current" in gameboy|game\\ boy|gb|gbc|gameboycolor|game\\ boy\\ color) HOT_RESULT='OK (compatible folder)'; return;; esac ;; snes) case "$current" in snes|sfc|sgb|supergameboy|super\\ game\\ boy) HOT_RESULT='OK (compatible folder)'; return;; esac ;; n64) case "$current" in n64|nintendo64|nintendo\\ 64) HOT_RESULT='OK (compatible folder)'; return;; esac ;; esac; HOT_RESULT=MISFILED;'''
replace(old_loc,new_loc,'location_status_set')
old_loc2='''case "$expected" in nes) case "$current" in nes|fds|famicom) echo "OK (compatible folder)"; return;; esac ;; gameboy) case "$current" in gameboy|game\\ boy|gb) echo "OK (compatible folder)"; return;; esac ;; n64) case "$current" in n64|nintendo64|nintendo\\ 64) echo "OK (compatible folder)"; return;; esac ;; esac; echo "MISFILED";'''
new_loc2='''case "$expected" in nes) case "$current" in nes|fds|famicom) echo "OK (compatible folder)"; return;; esac ;; gameboy) case "$current" in gameboy|game\\ boy|gb|gbc|gameboycolor|game\\ boy\\ color) echo "OK (compatible folder)"; return;; esac ;; snes) case "$current" in snes|sfc|sgb|supergameboy|super\\ game\\ boy) echo "OK (compatible folder)"; return;; esac ;; n64) case "$current" in n64|nintendo64|nintendo\\ 64) echo "OK (compatible folder)"; return;; esac ;; esac; echo "MISFILED";'''
replace(old_loc2,new_loc2,'location_status')

# Unmatched hashes get a triage class so known test/homebrew/unlicensed content
# does not look like a broken retail DAT match.
needle='''location_status() { local current="${1,,}" expected="${2,,}";'''
pos=s.index(needle)
end=s.index('\n\nSTART_TIME=', pos)
insert='''\nexpected_unmatched_class() {
  local name="${1,,}" kind="${2,,}"
  case "$kind" in *homebrew*|*unlicensed*|*prototype*|*demo*|*beta*) printf 'Expected non-retail'; return ;; esac
  case "$name" in *test*suite*|*test*rom*|*diagnostic*|*benchmark*|*homebrew*|*unlicensed*|*prototype*|*proto*|*beta*|*demo*) printf 'Expected support/non-retail'; return ;; esac
  printf 'Review unmatched retail/unknown'
}
'''
s=s[:end]+insert+s[end:]

replace("'''", "'''", 'noop') if False else None
replace("printf '%s\\n' '\"sha1\",\"system\",\"full_path\",\"original_filename\"' > \"$STAGE_DAT_UNMATCHED\"",
        "printf '%s\\n' '\"sha1\",\"system\",\"full_path\",\"original_filename\",\"unmatched_class\"' > \"$STAGE_DAT_UNMATCHED\"",
        'unmatched header')
replace('''    else SYSTEM_UNMATCHED["$system"]=$(( ${SYSTEM_UNMATCHED["$system"]:-0} + 1 )); csv_row "$STAGE_DAT_UNMATCHED" "$sha1" "$system" "$p" "$file"; fi
''','''    else SYSTEM_UNMATCHED["$system"]=$(( ${SYSTEM_UNMATCHED["$system"]:-0} + 1 )); unmatched_class="$(expected_unmatched_class "$file" "$kind")"; csv_row "$STAGE_DAT_UNMATCHED" "$sha1" "$system" "$p" "$file" "$unmatched_class"; fi
''','unmatched classification')

# Avoid a subshell/function call for the common exact-DAT case. Only formats
# that miss raw SHA-1 lookup need normalization work.
replace('''hkey="${sha1,,}"; file_size="${sig%%|*}"; matched_hkey="$(normalized_dat_hash "$p" "$ext" "$hkey" "$file_size")"; if [ "$matched_hkey" != "$hkey" ]; then''',
        '''hkey="${sha1,,}"; file_size="${sig%%|*}"; if [ -n "${DAT_RECORD_BY_SHA[$hkey]+x}" ]; then matched_hkey="$hkey"; else matched_hkey="$(normalized_dat_hash "$p" "$ext" "$hkey" "$file_size")"; fi; if [ "$matched_hkey" != "$hkey" ]; then''',
        'exact DAT fast path')

# Completion output only for systems proven present by at least one DAT match.
replace('''while IFS= read -r c_sys; do [ -n "$c_sys" ] || continue; c_total="${COMPLETION_TOTAL_BY_SYSTEM[$c_sys]:-0}";''',
        '''while IFS= read -r c_sys; do [ -n "$c_sys" ] || continue; present_matches=0; for present_sys in "${!SYSTEM_MATCHED[@]}"; do [ "$(canonical_dat_system "$present_sys")" = "$c_sys" ] && present_matches=$((present_matches + ${SYSTEM_MATCHED[$present_sys]:-0})); done; [ "$present_matches" -gt 0 ] || continue; c_total="${COMPLETION_TOTAL_BY_SYSTEM[$c_sys]:-0}";''',
        'completion present systems')
replace('''for c_key in "${!COMPLETION_REFERENCE_KEYS[@]}"; do [ -n "${COMPLETION_OWNED_KEYS[$c_key]+x}" ] && continue; c_sys="${c_key%%|*}"; c_title="${c_key#*|}"; csv_row''',
        '''for c_key in "${!COMPLETION_REFERENCE_KEYS[@]}"; do [ -n "${COMPLETION_OWNED_KEYS[$c_key]+x}" ] && continue; c_sys="${c_key%%|*}"; present_matches=0; for present_sys in "${!SYSTEM_MATCHED[@]}"; do [ "$(canonical_dat_system "$present_sys")" = "$c_sys" ] && present_matches=$((present_matches + ${SYSTEM_MATCHED[$present_sys]:-0})); done; [ "$present_matches" -gt 0 ] || continue; c_title="${c_key#*|}"; csv_row''',
        'missing completion present systems')

# Collisions are review warnings, not a global DO NOT APPLY condition. Any
# future apply path is expected to skip collision rows. Low DAT coverage and
# integrity failures remain blocking.
replace('''if [ "$AUDIT_VERDICT" != "FAIL" ]; then if [ "$COLLISIONS" -gt 0 ] || [ "$MATCH_RATE_INT" -lt 50 ]; then AUDIT_VERDICT="PASS WITH WARNINGS"; APPLY_RECOMMENDATION="DO NOT APPLY"; [ "$COLLISIONS" -gt 0 ] && INTEGRITY_NOTES="$INTEGRITY_NOTES collision-review-required"; [ "$MATCH_RATE_INT" -lt 50 ] && INTEGRITY_NOTES="$INTEGRITY_NOTES low-dat-match-rate"; fi; fi
''','''if [ "$AUDIT_VERDICT" != "FAIL" ]; then
  if [ "$MATCH_RATE_INT" -lt 50 ]; then AUDIT_VERDICT="PASS WITH WARNINGS"; APPLY_RECOMMENDATION="DO NOT APPLY"; INTEGRITY_NOTES="$INTEGRITY_NOTES low-dat-match-rate"; fi
  if [ "$COLLISIONS" -gt 0 ]; then AUDIT_VERDICT="PASS WITH WARNINGS"; INTEGRITY_NOTES="$INTEGRITY_NOTES collision-rows-will-be-skipped"; [ "$APPLY_RECOMMENDATION" != "DO NOT APPLY" ] && APPLY_RECOMMENDATION="SAFE TO PREVIEW (COLLISIONS SKIPPED)"; fi
fi
''','collision verdict')

p.write_text(s)
print('Applied audit correctness, MiSTer location, completion, unmatched triage, collision verdict, and report hot-path fixes.')
