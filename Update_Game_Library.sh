#!/bin/bash
# Update_Game_Library_v1.3.sh
# Companion updater for MiSTer ROM Library Auditor v1.3
# Diagnostic build marker helps confirm which installed updater copy is executing.

ROOT="/media/fat"
GAMES="$ROOT/games"
SAVES="$ROOT/saves"
AUDIT="$ROOT/GameLibraryAudit"
GAME_CSV="$AUDIT/proposed_renames.csv"
SAVE_CSV="$AUDIT/proposed_save_renames.csv"
CATALOG="$AUDIT/library_catalog.csv"
BUNDLE="$AUDIT/MiSTer_Library_Audit.txt"
HISTORY="$AUDIT/RenameHistory"
PLAN="$AUDIT/apply_preview.tsv"
SKIPS="$AUDIT/apply_skipped.tsv"
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
EXPORTER="$SCRIPT_DIR/Export_Game_Library.sh"
HASH_DB="$SCRIPT_DIR/mister_hash_database.tsv"
EXPECTED_SCHEMA="4"
EXPECTED_EXPORTER_VERSION="1.3"
COLLISION_INPUT="/tmp/mister_updater_collision_input.$$"
BLOCKLIST="/tmp/mister_updater_blocked.$$"
HEARTBEAT_EVERY=500
UPDATER_BUILD="preview-debug-2026-09-13a"

cleanup() { rm -f "$COLLISION_INPUT" "$BLOCKLIST"; }
trap cleanup EXIT INT TERM
mkdir -p "$HISTORY" || exit 1

hash_file() {
  local p="$1"
  if command -v sha1sum >/dev/null 2>&1; then sha1sum "$p" 2>/dev/null | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then openssl sha1 "$p" 2>/dev/null | awk '{print $NF}'
  else printf 'UNAVAILABLE'; fi
}

audit_meta() {
  local key="$1"
  awk -F= -v k="$key" '
    /^\[AUDIT_METADATA\]$/ {inmeta=1; next}
    /^\[/ && inmeta {exit}
    inmeta && $1==k {sub(/^[^=]*=/, ""); print; exit}
  ' "$BUNDLE" 2>/dev/null
}

trim_spaces() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

validate_audit() {
  local mode="${1:-preview}"
  local schema exporter_version build_sha database_sha metadata_layer self_check verdict recommendation notes notes_trimmed
  local current_exporter_sha current_database_sha errors=0 collision_only=0
  if [[ ! -f "$BUNDLE" ]]; then echo "ERROR: Missing $BUNDLE"; echo "Run Export_Game_Library.sh v1.3 before previewing or applying renames."; return 1; fi
  schema="$(audit_meta schema_version)"; exporter_version="$(audit_meta exporter_version)"; build_sha="$(audit_meta build_sha1)"
  database_sha="$(audit_meta database_sha1)"; metadata_layer="$(audit_meta metadata_layer)"; self_check="$(audit_meta self_check)"
  verdict="$(audit_meta integrity_verdict)"; recommendation="$(audit_meta apply_recommendation)"; notes="$(audit_meta integrity_notes)"; notes_trimmed="$(trim_spaces "$notes")"
  [[ "$verdict" == "PASS WITH WARNINGS" && "$notes_trimmed" == "collision-review-required" ]] && collision_only=1
  [[ "$recommendation" == "APPLY WITH SKIPS" && "$notes_trimmed" == *"collision"* ]] && collision_only=1
  echo; echo "Audit compatibility check"; echo "-------------------------"
  echo "Schema:               ${schema:-MISSING}"; echo "Exporter version:     ${exporter_version:-MISSING}"; echo "Self-check:           ${self_check:-MISSING}"
  echo "Metadata layer:       ${metadata_layer:-MISSING}"; echo "Integrity verdict:    ${verdict:-MISSING}"; echo "Apply recommendation: ${recommendation:-MISSING}"; echo "Integrity notes:      ${notes:-MISSING}"
  [[ "$schema" == "$EXPECTED_SCHEMA" ]] || { echo "ERROR: Expected audit schema $EXPECTED_SCHEMA."; errors=1; }
  [[ "$exporter_version" == "$EXPECTED_EXPORTER_VERSION" ]] || { echo "ERROR: Expected exporter v$EXPECTED_EXPORTER_VERSION."; errors=1; }
  [[ "$self_check" == "PASS" ]] || { echo "ERROR: Auditor startup self-check did not pass."; errors=1; }
  [[ "$metadata_layer" == "MiSTer-aware" ]] || { echo "ERROR: MiSTer-aware metadata layer was not validated."; errors=1; }
  [[ -n "$build_sha" && "$build_sha" != "UNAVAILABLE" ]] || { echo "ERROR: Audit exporter build fingerprint is missing."; errors=1; }
  [[ -n "$database_sha" && "$database_sha" != "missing" && "$database_sha" != "UNAVAILABLE" ]] || { echo "ERROR: Audit database fingerprint is missing."; errors=1; }
  [[ -n "$verdict" ]] || { echo "ERROR: Audit integrity verdict is missing."; errors=1; }; [[ -n "$recommendation" ]] || { echo "ERROR: Audit apply recommendation is missing."; errors=1; }
  if [[ "$mode" == "apply" ]]; then
    if [[ "$verdict" == "FAIL" ]]; then echo "ERROR: Apply is blocked by integrity_verdict=FAIL."; errors=1
    elif [[ "$verdict" == "PASS" ]]; then [[ "$recommendation" != "DO NOT APPLY" ]] || { echo "ERROR: Auditor explicitly recommends DO NOT APPLY."; errors=1; }
    elif (( collision_only )); then echo "WARNING: Audit contains collision-only warnings."; echo "         Blocking collision rows will be skipped automatically."
    else echo "ERROR: Apply warnings are not limited to skippable collision rows."; errors=1; fi
    if [[ ! -f "$EXPORTER" ]]; then echo "ERROR: Current exporter not found at $EXPORTER."; errors=1
    else current_exporter_sha="$(hash_file "$EXPORTER")"; [[ "$current_exporter_sha" != "UNAVAILABLE" && "$current_exporter_sha" == "$build_sha" ]] || { echo "ERROR: Exporter changed since this audit was generated. Re-run the audit."; errors=1; }; fi
    if [[ ! -f "$HASH_DB" ]]; then echo "ERROR: Current hash database not found at $HASH_DB."; errors=1
    else current_database_sha="$(hash_file "$HASH_DB")"; [[ "$current_database_sha" != "UNAVAILABLE" && "$current_database_sha" == "$database_sha" ]] || { echo "ERROR: Hash database changed since this audit was generated. Re-run the audit."; errors=1; }; fi
  else
    if [[ "$verdict" == "FAIL" ]]; then echo "ERROR: Audit integrity failed. Generate a fresh audit before previewing renames."; errors=1
    elif (( collision_only )); then echo "WARNING: Collision-only warnings detected; blocking rows will be shown as skipped."
    elif [[ "$verdict" == "PASS WITH WARNINGS" || "$recommendation" == "DO NOT APPLY" ]]; then echo "WARNING: Preview is allowed for review, but Apply remains blocked by non-collision warnings."; fi
  fi
  if (( errors )); then echo "Audit compatibility check: BLOCKED"; return 1; fi
  echo "Audit compatibility check: PASS"; return 0
}

parse_csv() {
  local s="$1" c field="" quoted=0 i; CSV_FIELDS=()
  for ((i=0; i<${#s}; i++)); do c="${s:i:1}"; if (( quoted )); then if [[ "$c" == '"' ]]; then if [[ "${s:i+1:1}" == '"' ]]; then field+='"'; ((i++)); else quoted=0; fi; else field+="$c"; fi; else case "$c" in '"') quoted=1 ;; ',') CSV_FIELDS+=("$field"); field="" ;; *) field+="$c" ;; esac; fi; done
  CSV_FIELDS+=("$field")
}

safe_under() { case "$1" in "$2"/*) return 0;; *) return 1;; esac; }
unsafe_name() { [[ -z "$1" || "$1" == */* || "$1" == "." || "$1" == ".." ]]; }
trim_title() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
region_of() { local s="${1,,}"; if [[ "$s" =~ \((usa|us|u)(,|\)|[[:space:]]) ]] || [[ "$s" =~ \((ue|u,e|u\+e)\) ]]; then echo USA; elif [[ "$s" =~ \((world|w)\) ]]; then echo World; elif [[ "$s" =~ \((europe|eur|e)\) ]]; then echo Europe; elif [[ "$s" =~ \((japan|jpn|j)\) ]]; then echo Japan; elif [[ "$s" =~ \((canada|can)\) ]]; then echo Canada; elif [[ "$s" =~ \((australia|aus)\) ]]; then echo Australia; elif [[ "$s" =~ \((korea|kor|k)\) ]]; then echo Korea; elif [[ "$s" =~ \((brazil|bra|b)\) ]]; then echo Brazil; else echo Unknown; fi; }
kind_of() { local s="${1,,}"; if [[ "$s" =~ \((proto|prototype|beta|demo|sample)([^a-z]|$) ]] || [[ "$s" =~ \[(proto|prototype|beta|demo|sample)([^a-z]|$) ]]; then echo Prototype/Beta/Demo; elif [[ "$s" =~ \((rev|revision)[[:space:]._-]*[0-9a-z]+\) ]] || [[ "$s" =~ \[(rev|revision)[[:space:]._-]*[0-9a-z]+\] ]]; then echo Revision; elif [[ "$s" =~ \((unl|unlicensed|homebrew|aftermarket)\) ]] || [[ "$s" =~ \[(unl|unlicensed|homebrew|aftermarket)\] ]] || [[ "$s" == *" homebrew "* ]] || [[ "$s" == *" aftermarket "* ]]; then echo Homebrew/Unlicensed; elif [[ "$s" =~ \[t[^]]*\] ]] || [[ "$s" == *"(translation"* ]] || [[ "$s" == *"(translated"* ]] || [[ "$s" == *"(eng)"* ]] || [[ "$s" == *"(english"* ]] || [[ "$s" == *"translation"* ]] || [[ "$s" == *"english patched"* ]]; then echo Translation; elif [[ "$s" =~ \[h[^]]*\] ]] || [[ "$s" == *"(hack"* ]] || [[ "$s" == *"(hacked"* ]] || [[ "$s" == *"(improvement"* ]] || [[ "$s" == *"(redux"* ]] || [[ "$s" == *"(randomizer"* ]] || [[ "$s" == *" hack "* ]] || [[ "$s" == *" improvement "* ]] || [[ "$s" == *" randomizer "* ]]; then echo Hack/Modified; else echo Retail/Standard; fi; }
clean_title() { local s="$1" before; local re_region='^(.*)[[:space:]]+\((USA|US|U|World|W|Europe|EUR|E|Japan|JPN|J|Canada|CAN|Australia|AUS|Korea|KOR|Brazil|BRA|UE|U,E|U\+E)\)(.*)$'; local re_meta='^(.*)[[:space:]]+\((Rev(ision)?[[:space:]._-]*[0-9A-Za-z]+|Proto(type)?|Beta|Demo|Sample|Unl(icensed)?|Homebrew|Aftermarket|Translation|Translated|Eng(lish)?[^)]*)\)(.*)$'; local re_bracket='^(.*)[[:space:]]+\[([tThH][^]]*|!|[bBoOfFpPaA][0-9]*|[cCxX])\](.*)$'; while :; do before="$s"; if [[ "$s" =~ $re_region ]]; then s="${BASH_REMATCH[1]}${BASH_REMATCH[3]}"; elif [[ "$s" =~ $re_meta ]]; then s="${BASH_REMATCH[1]}${BASH_REMATCH[7]}"; elif [[ "$s" =~ $re_bracket ]]; then s="${BASH_REMATCH[1]}${BASH_REMATCH[3]}"; else break; fi; [[ "$s" == "$before" ]] && break; done; s="$(trim_title "$s")"; while [[ "$s" == *"  "* ]]; do s="${s//  / }"; done; s="${s% -}"; s="${s% _}"; s="$(trim_title "$s")"; [[ -z "$s" ]] && s="$1"; printf '%s' "$s"; }
suffix_for() { local region="$1" kind="$2" suffix=""; [[ "$region" != "USA" && "$region" != "Unknown" ]] && suffix=" [$region]"; [[ "$region" == "Unknown" ]] && suffix=" [Unknown Region]"; [[ "$kind" != "Retail/Standard" ]] && suffix="$suffix [$kind]"; printf '%s' "$suffix"; }

classify_blocking_games() {
  echo "DEBUG: entered classify_blocking_games"
  : > "$COLLISION_INPUT"; : > "$BLOCKLIST"
  [[ -f "$CATALOG" ]] || { echo "Missing $CATALOG"; return 1; }
  local line system original proposed path dat_status ext stem clean region kind fallback group authoritative final_target processed=0 total=0
  total=$(( $(wc -l < "$CATALOG") - 1 )); (( total < 0 )) && total=0
  echo "Building collision safety map..."; echo "  Catalog rows: $total"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == '"system"'* ]] && continue; parse_csv "$line"; ((${#CSV_FIELDS[@]} >= 21)) || continue; processed=$((processed+1)); (( processed % HEARTBEAT_EVERY == 0 )) && echo "  Processed $processed / $total catalog rows..."
    system="${CSV_FIELDS[0]}"; original="${CSV_FIELDS[4]}"; proposed="${CSV_FIELDS[5]}"; path="${CSV_FIELDS[6]}"; dat_status="${CSV_FIELDS[10]}"; ext="${original##*.}"; ext="${ext,,}"; stem="${original%.*}"; clean="$(clean_title "$stem")"; region="$(region_of "$stem")"; kind="$(kind_of "$stem")"; fallback="$clean$(suffix_for "$region" "$kind").$ext"; group="${system,,}|${fallback,,}"; authoritative=0; case "$dat_status" in "Exact SHA-1"|"Normalized SHA-1") authoritative=1 ;; esac; final_target="${system,,}|${proposed,,}"; printf '%s\t%s\t%s\t%s\n' "$path" "$group" "$authoritative" "$final_target" >> "$COLLISION_INPUT"
  done < "$CATALOG"
  echo "  Processed $processed / $total catalog rows."; echo "  Resolving global collision groups..."
  awk -F '\t' '{path[NR]=$1; group[NR]=$2; auth[NR]=$3+0; target[NR]=$4; final_count[$4]++; group_rows[$2]++; group_auth[$2]+=auth[NR]; group_target[$2 SUBSEP $4]++} END {for (g in group_rows) {duplicate=0; prefix=g SUBSEP; for (k in group_target) {if (index(k,prefix)==1 && group_target[k]>1) {duplicate=1; break}} group_safe[g]=(group_auth[g]==group_rows[g] && !duplicate)} for (i=1; i<=NR; i++) {pre=(group_rows[group[i]]>1); if (final_count[target[i]]>1) print path[i] "\tblocking collision: duplicate final target"; else if (pre && !group_safe[group[i]]) print path[i] "\tblocking collision: unresolved pre-DAT group"}}' "$COLLISION_INPUT" > "$BLOCKLIST"
  echo "  Collision safety map complete: $(wc -l < "$BLOCKLIST") blocking rows."
}

build_plan() {
  echo "DEBUG: entered build_plan"
  : > "$PLAN"; : > "$SKIPS"; printf 'type\told_path\tnew_path\n' >> "$PLAN"; printf 'type\tpath\treason\n' >> "$SKIPS"
  declare -A TARGETS BLOCKED_GAMES; local line old proposed new dir ext type block_path block_reason game_path processed=0 total=0
  echo "DEBUG: calling classify_blocking_games"
  classify_blocking_games || return 1
  echo "DEBUG: classify_blocking_games returned"
  while IFS=$'\t' read -r block_path block_reason; do [[ -n "$block_path" ]] || continue; BLOCKED_GAMES["$block_path"]="$block_reason"; done < "$BLOCKLIST"
  [[ -f "$GAME_CSV" ]] || { echo "Missing $GAME_CSV"; return 1; }; total=$(( $(wc -l < "$GAME_CSV") - 1 )); (( total < 0 )) && total=0; processed=0; echo "Building safe game rename plan..."; echo "  Game proposals: $total"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == '"system"'* ]] && continue; parse_csv "$line"; processed=$((processed+1)); (( processed % HEARTBEAT_EVERY == 0 )) && echo "  Processed $processed / $total game proposals..."; old="${CSV_FIELDS[1]}"; proposed="${CSV_FIELDS[2]}"; type="GAME"
    if [[ -n "${BLOCKED_GAMES["$old"]+x}" ]]; then printf '%s\t%s\t%s\n' "$type" "$old" "${BLOCKED_GAMES["$old"]}" >> "$SKIPS"; continue; fi
    safe_under "$old" "$GAMES" || { printf '%s\t%s\t%s\n' "$type" "$old" "outside games root" >> "$SKIPS"; continue; }; unsafe_name "$proposed" && { printf '%s\t%s\t%s\n' "$type" "$old" "unsafe proposed filename" >> "$SKIPS"; continue; }; ext="${old##*.}"; ext="${ext,,}"; [[ "$ext" == "cue" ]] && { printf '%s\t%s\t%s\n' "$type" "$old" "CUE/BIN set rename disabled" >> "$SKIPS"; continue; }; [[ -e "$old" ]] || { printf '%s\t%s\t%s\n' "$type" "$old" "source missing" >> "$SKIPS"; continue; }; dir="${old%/*}"; new="$dir/$proposed"; [[ "$old" == "$new" ]] && continue; if [[ -e "$new" ]]; then printf '%s\t%s\t%s\n' "$type" "$old" "target already exists: $new" >> "$SKIPS"; continue; fi; if [[ -n "${TARGETS["$new"]+x}" ]]; then printf '%s\t%s\t%s\n' "$type" "$old" "duplicate proposed target: $new" >> "$SKIPS"; continue; fi; TARGETS["$new"]="$old"; printf '%s\t%s\t%s\n' "$type" "$old" "$new" >> "$PLAN"
  done < "$GAME_CSV"
  echo "  Processed $processed / $total game proposals."
  if [[ -f "$SAVE_CSV" ]]; then total=$(( $(wc -l < "$SAVE_CSV") - 1 )); (( total < 0 )) && total=0; processed=0; echo "Building paired save rename plan..."; echo "  Save proposals: $total"; while IFS= read -r line || [[ -n "$line" ]]; do [[ "$line" == '"system"'* ]] && continue; parse_csv "$line"; processed=$((processed+1)); (( processed % HEARTBEAT_EVERY == 0 )) && echo "  Processed $processed / $total save proposals..."; game_path="${CSV_FIELDS[1]}"; old="${CSV_FIELDS[2]}"; proposed="${CSV_FIELDS[3]}"; type="SAVE"; if [[ -n "${BLOCKED_GAMES["$game_path"]+x}" ]]; then printf '%s\t%s\t%s\n' "$type" "$old" "game rename skipped: ${BLOCKED_GAMES["$game_path"]}" >> "$SKIPS"; continue; fi; safe_under "$old" "$SAVES" || { printf '%s\t%s\t%s\n' "$type" "$old" "outside saves root" >> "$SKIPS"; continue; }; unsafe_name "$proposed" && { printf '%s\t%s\t%s\n' "$type" "$old" "unsafe proposed filename" >> "$SKIPS"; continue; }; [[ -e "$old" ]] || { printf '%s\t%s\t%s\n' "$type" "$old" "source missing" >> "$SKIPS"; continue; }; dir="${old%/*}"; new="$dir/$proposed"; [[ "$old" == "$new" ]] && continue; if [[ -e "$new" ]]; then printf '%s\t%s\t%s\n' "$type" "$old" "target already exists: $new" >> "$SKIPS"; continue; fi; if [[ -n "${TARGETS["$new"]+x}" ]]; then printf '%s\t%s\t%s\n' "$type" "$old" "duplicate proposed target: $new" >> "$SKIPS"; continue; fi; TARGETS["$new"]="$old"; printf '%s\t%s\t%s\n' "$type" "$old" "$new" >> "$PLAN"; done < "$SAVE_CSV"; echo "  Processed $processed / $total save proposals."; fi
  echo "Rename plan build complete."
}

show_plan_summary() { local n s c; n=$(( $(wc -l < "$PLAN") - 1 )); s=$(( $(wc -l < "$SKIPS") - 1 )); c=$(awk -F '\t' 'NR>1 && $3 ~ /^blocking collision:|^game rename skipped: blocking collision:/ {n++} END{print n+0}' "$SKIPS"); echo; echo "Safe rename candidates: $n"; echo "Skipped/review items: $s"; echo "Collision-blocked rows skipped: $c"; echo "Preview: $PLAN"; echo "Skipped: $SKIPS"; echo; sed -n '1,21p' "$PLAN"; (( n > 20 )) && echo "... see $PLAN for the full preview."; }

preview() { echo "DEBUG: preview entered"; validate_audit preview || return 1; echo "DEBUG: compatibility passed; entering build_plan"; build_plan || return 1; echo "DEBUG: build_plan returned; showing summary"; show_plan_summary; }

apply_plan() {
  validate_audit apply || return 1; build_plan || return 1; local n stamp manifest type old new; n=$(( $(wc -l < "$PLAN") - 1 )); (( n > 0 )) || { echo "Nothing safe to rename."; return 0; }; show_plan_summary; echo; echo "This will rename $n safe files. Collision-blocked rows and their saves remain untouched."; echo "No ROM/save contents are modified."; echo "Type APPLY exactly to continue:"; read -r confirm; [[ "$confirm" == "APPLY" ]] || { echo "Cancelled."; return 0; }; validate_audit apply || { echo "Apply cancelled because the audit handshake changed."; return 1; }; build_plan || { echo "Apply cancelled because the safe plan could not be rebuilt."; return 1; }; stamp=$(date +%Y%m%d-%H%M%S); manifest="$HISTORY/rename-$stamp.tsv"; printf 'type\told_path\tnew_path\tresult\n' > "$manifest"; tail -n +2 "$PLAN" | while IFS=$'\t' read -r type old new; do if [[ -e "$old" && ! -e "$new" ]]; then if mv -- "$old" "$new"; then printf '%s\t%s\t%s\tOK\n' "$type" "$old" "$new" >> "$manifest"; else printf '%s\t%s\t%s\tFAILED\n' "$type" "$old" "$new" >> "$manifest"; fi; else printf '%s\t%s\t%s\tSKIPPED_AT_APPLY\n' "$type" "$old" "$new" >> "$manifest"; fi; done; cp "$manifest" "$HISTORY/last_manifest.tsv"; echo "Finished. Rollback manifest: $manifest"; echo "Blocking collision rows were left unchanged. Run the auditor again before another cleanup pass."
}

rollback() { local manifest="$HISTORY/last_manifest.tsv" type old new result; [[ -f "$manifest" ]] || { echo "No last rollback manifest found."; return 1; }; echo "Rollback will restore successful renames from:"; echo "$manifest"; echo "Type ROLLBACK exactly to continue:"; read -r confirm; [[ "$confirm" == "ROLLBACK" ]] || { echo "Cancelled."; return 0; }; tail -n +2 "$manifest" | tac | while IFS=$'\t' read -r type old new result; do [[ "$result" == "OK" ]] || continue; if [[ -e "$new" && ! -e "$old" ]]; then mv -- "$new" "$old" || echo "FAILED: $new"; else echo "SKIP: cannot safely restore $old"; fi; done; echo "Rollback pass finished. Re-run the auditor to verify the library."; }

echo "MiSTer ROM Library Updater v1.3"
echo "================================="
echo "Updater build: $UPDATER_BUILD"
echo "Script path:   $0"
echo "1) Preview safe renames"
echo "2) Apply safe renames (blocking collisions auto-skipped)"
echo "3) Roll back last applied cleanup"
echo "4) Exit"
read -r choice
case "$choice" in 1) preview ;; 2) apply_plan ;; 3) rollback ;; *) exit 0 ;; esac
