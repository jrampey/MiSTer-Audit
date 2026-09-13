#!/bin/bash
# Update_Game_Library_v1.3.sh
# Companion updater for MiSTer ROM Library Auditor v1.3
# Safely previews/applies reviewed game + save rename proposals and can roll back the last run.
# Preview validates the v1.3 audit handshake. Apply additionally requires a clean integrity verdict
# and verifies that the audit was produced by the currently installed exporter/hash database.

ROOT="/media/fat"
GAMES="$ROOT/games"
SAVES="$ROOT/saves"
AUDIT="$ROOT/GameLibraryAudit"
GAME_CSV="$AUDIT/proposed_renames.csv"
SAVE_CSV="$AUDIT/proposed_save_renames.csv"
BUNDLE="$AUDIT/MiSTer_Library_Audit.txt"
HISTORY="$AUDIT/RenameHistory"
PLAN="$AUDIT/apply_preview.tsv"
SKIPS="$AUDIT/apply_skipped.tsv"
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
EXPORTER="$SCRIPT_DIR/Export_Game_Library.sh"
HASH_DB="$SCRIPT_DIR/mister_hash_database.tsv"
EXPECTED_SCHEMA="4"
EXPECTED_EXPORTER_VERSION="1.3"

mkdir -p "$HISTORY" || exit 1

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

audit_meta() {
  local key="$1"
  awk -F= -v k="$key" '
    /^\[AUDIT_METADATA\]$/ {inmeta=1; next}
    /^\[/ && inmeta {exit}
    inmeta && $1==k {sub(/^[^=]*=/, ""); print; exit}
  ' "$BUNDLE" 2>/dev/null
}

validate_audit() {
  local mode="${1:-preview}"
  local schema exporter_version build_sha database_sha metadata_layer self_check verdict recommendation notes
  local current_exporter_sha current_database_sha errors=0

  if [[ ! -f "$BUNDLE" ]]; then
    echo "ERROR: Missing $BUNDLE"
    echo "Run Export_Game_Library.sh v1.3 before previewing or applying renames."
    return 1
  fi

  schema="$(audit_meta schema_version)"
  exporter_version="$(audit_meta exporter_version)"
  build_sha="$(audit_meta build_sha1)"
  database_sha="$(audit_meta database_sha1)"
  metadata_layer="$(audit_meta metadata_layer)"
  self_check="$(audit_meta self_check)"
  verdict="$(audit_meta integrity_verdict)"
  recommendation="$(audit_meta apply_recommendation)"
  notes="$(audit_meta integrity_notes)"

  echo
  echo "Audit compatibility check"
  echo "-------------------------"
  echo "Schema:               ${schema:-MISSING}"
  echo "Exporter version:     ${exporter_version:-MISSING}"
  echo "Self-check:           ${self_check:-MISSING}"
  echo "Metadata layer:       ${metadata_layer:-MISSING}"
  echo "Integrity verdict:    ${verdict:-MISSING}"
  echo "Apply recommendation: ${recommendation:-MISSING}"
  echo "Integrity notes:      ${notes:-MISSING}"

  [[ "$schema" == "$EXPECTED_SCHEMA" ]] || { echo "ERROR: Expected audit schema $EXPECTED_SCHEMA."; errors=1; }
  [[ "$exporter_version" == "$EXPECTED_EXPORTER_VERSION" ]] || { echo "ERROR: Expected exporter v$EXPECTED_EXPORTER_VERSION."; errors=1; }
  [[ "$self_check" == "PASS" ]] || { echo "ERROR: Auditor startup self-check did not pass."; errors=1; }
  [[ "$metadata_layer" == "MiSTer-aware" ]] || { echo "ERROR: MiSTer-aware metadata layer was not validated."; errors=1; }
  [[ -n "$build_sha" && "$build_sha" != "UNAVAILABLE" ]] || { echo "ERROR: Audit exporter build fingerprint is missing."; errors=1; }
  [[ -n "$database_sha" && "$database_sha" != "missing" && "$database_sha" != "UNAVAILABLE" ]] || { echo "ERROR: Audit database fingerprint is missing."; errors=1; }
  [[ -n "$verdict" ]] || { echo "ERROR: Audit integrity verdict is missing."; errors=1; }
  [[ -n "$recommendation" ]] || { echo "ERROR: Audit apply recommendation is missing."; errors=1; }

  if [[ "$mode" == "apply" ]]; then
    [[ "$verdict" == "PASS" ]] || { echo "ERROR: Apply requires integrity_verdict=PASS."; errors=1; }
    [[ "$recommendation" != "DO NOT APPLY" ]] || { echo "ERROR: Auditor explicitly recommends DO NOT APPLY."; errors=1; }

    if [[ ! -f "$EXPORTER" ]]; then
      echo "ERROR: Current exporter not found at $EXPORTER."
      errors=1
    else
      current_exporter_sha="$(hash_file "$EXPORTER")"
      [[ "$current_exporter_sha" != "UNAVAILABLE" && "$current_exporter_sha" == "$build_sha" ]] || {
        echo "ERROR: Exporter changed since this audit was generated. Re-run the audit."
        errors=1
      }
    fi

    if [[ ! -f "$HASH_DB" ]]; then
      echo "ERROR: Current hash database not found at $HASH_DB."
      errors=1
    else
      current_database_sha="$(hash_file "$HASH_DB")"
      [[ "$current_database_sha" != "UNAVAILABLE" && "$current_database_sha" == "$database_sha" ]] || {
        echo "ERROR: Hash database changed since this audit was generated. Re-run the audit."
        errors=1
      }
    fi
  else
    if [[ "$verdict" == "FAIL" ]]; then
      echo "ERROR: Audit integrity failed. Generate a fresh audit before previewing renames."
      errors=1
    elif [[ "$verdict" == "PASS WITH WARNINGS" || "$recommendation" == "DO NOT APPLY" ]]; then
      echo "WARNING: Preview is allowed for review, but Apply will remain blocked."
    fi
  fi

  if (( errors )); then
    echo "Audit compatibility check: BLOCKED"
    return 1
  fi
  echo "Audit compatibility check: PASS"
  return 0
}

# Parse one RFC4180-ish CSV row generated by our auditor into CSV_FIELDS[].
parse_csv() {
  local s="$1" c field="" quoted=0 i
  CSV_FIELDS=()
  for ((i=0; i<${#s}; i++)); do
    c="${s:i:1}"
    if (( quoted )); then
      if [[ "$c" == '"' ]]; then
        if [[ "${s:i+1:1}" == '"' ]]; then field+='"'; ((i++)); else quoted=0; fi
      else field+="$c"; fi
    else
      case "$c" in
        '"') quoted=1 ;;
        ',') CSV_FIELDS+=("$field"); field="" ;;
        *) field+="$c" ;;
      esac
    fi
  done
  CSV_FIELDS+=("$field")
}

safe_under() { case "$1" in "$2"/*) return 0;; *) return 1;; esac; }
unsafe_name() { [[ -z "$1" || "$1" == */* || "$1" == "." || "$1" == ".." ]]; }

build_plan() {
  : > "$PLAN"; : > "$SKIPS"
  printf 'type\told_path\tnew_path\n' >> "$PLAN"
  printf 'type\tpath\treason\n' >> "$SKIPS"
  declare -A TARGETS
  local line old proposed new dir ext type

  if [[ ! -f "$GAME_CSV" ]]; then echo "Missing $GAME_CSV"; return 1; fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == '"system"'* ]] && continue
    parse_csv "$line"
    old="${CSV_FIELDS[1]}"; proposed="${CSV_FIELDS[2]}"; type="GAME"
    safe_under "$old" "$GAMES" || { printf '%s\t%s\t%s\n' "$type" "$old" "outside games root" >> "$SKIPS"; continue; }
    unsafe_name "$proposed" && { printf '%s\t%s\t%s\n' "$type" "$old" "unsafe proposed filename" >> "$SKIPS"; continue; }
    ext="${old##*.}"; ext="${ext,,}"
    [[ "$ext" == "cue" ]] && { printf '%s\t%s\t%s\n' "$type" "$old" "CUE/BIN set rename disabled" >> "$SKIPS"; continue; }
    [[ -e "$old" ]] || { printf '%s\t%s\t%s\n' "$type" "$old" "source missing" >> "$SKIPS"; continue; }
    dir="${old%/*}"; new="$dir/$proposed"
    [[ "$old" == "$new" ]] && continue
    if [[ -e "$new" ]]; then printf '%s\t%s\t%s\n' "$type" "$old" "target already exists: $new" >> "$SKIPS"; continue; fi
    if [[ -n "${TARGETS[$new]}" ]]; then printf '%s\t%s\t%s\n' "$type" "$old" "duplicate proposed target: $new" >> "$SKIPS"; continue; fi
    TARGETS["$new"]="$old"
    printf '%s\t%s\t%s\n' "$type" "$old" "$new" >> "$PLAN"
  done < "$GAME_CSV"

  if [[ -f "$SAVE_CSV" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" == '"system"'* ]] && continue
      parse_csv "$line"
      old="${CSV_FIELDS[2]}"; proposed="${CSV_FIELDS[3]}"; type="SAVE"
      safe_under "$old" "$SAVES" || { printf '%s\t%s\t%s\n' "$type" "$old" "outside saves root" >> "$SKIPS"; continue; }
      unsafe_name "$proposed" && { printf '%s\t%s\t%s\n' "$type" "$old" "unsafe proposed filename" >> "$SKIPS"; continue; }
      [[ -e "$old" ]] || { printf '%s\t%s\t%s\n' "$type" "$old" "source missing" >> "$SKIPS"; continue; }
      dir="${old%/*}"; new="$dir/$proposed"
      [[ "$old" == "$new" ]] && continue
      if [[ -e "$new" ]]; then printf '%s\t%s\t%s\n' "$type" "$old" "target already exists: $new" >> "$SKIPS"; continue; fi
      if [[ -n "${TARGETS[$new]}" ]]; then printf '%s\t%s\t%s\n' "$type" "$old" "duplicate proposed target: $new" >> "$SKIPS"; continue; fi
      TARGETS["$new"]="$old"
      printf '%s\t%s\t%s\n' "$type" "$old" "$new" >> "$PLAN"
    done < "$SAVE_CSV"
  fi
}

preview() {
  validate_audit preview || return 1
  build_plan || return 1
  local n s
  n=$(( $(wc -l < "$PLAN") - 1 )); s=$(( $(wc -l < "$SKIPS") - 1 ))
  echo; echo "Safe rename candidates: $n"; echo "Skipped/review items: $s"
  echo "Preview: $PLAN"; echo "Skipped: $SKIPS"; echo
  sed -n '1,21p' "$PLAN"
  (( n > 20 )) && echo "... see $PLAN for the full preview."
}

apply_plan() {
  validate_audit apply || return 1
  build_plan || return 1
  local n stamp manifest type old new
  n=$(( $(wc -l < "$PLAN") - 1 ))
  (( n > 0 )) || { echo "Nothing safe to rename."; return 0; }
  echo; echo "Safe rename candidates: $n"
  echo "Preview: $PLAN"; echo "Skipped: $SKIPS"
  sed -n '1,21p' "$PLAN"
  (( n > 20 )) && echo "... see $PLAN for the full preview."
  echo; echo "This will rename $n files. No ROM/save contents are modified."
  echo "Type APPLY exactly to continue:"
  read -r confirm
  [[ "$confirm" == "APPLY" ]] || { echo "Cancelled."; return 0; }

  # Revalidate immediately before mutation in case the audit, exporter, or DB changed
  # while the plan was being reviewed.
  validate_audit apply || { echo "Apply cancelled because the audit handshake changed."; return 1; }

  stamp=$(date +%Y%m%d-%H%M%S)
  manifest="$HISTORY/rename-$stamp.tsv"
  printf 'type\told_path\tnew_path\tresult\n' > "$manifest"
  tail -n +2 "$PLAN" | while IFS=$'\t' read -r type old new; do
    if [[ -e "$old" && ! -e "$new" ]]; then
      if mv -- "$old" "$new"; then printf '%s\t%s\t%s\tOK\n' "$type" "$old" "$new" >> "$manifest"; else printf '%s\t%s\t%s\tFAILED\n' "$type" "$old" "$new" >> "$manifest"; fi
    else printf '%s\t%s\t%s\tSKIPPED_AT_APPLY\n' "$type" "$old" "$new" >> "$manifest"; fi
  done
  cp "$manifest" "$HISTORY/last_manifest.tsv"
  echo "Finished. Rollback manifest: $manifest"
  echo "Run the auditor again before making another cleanup pass."
}

rollback() {
  local manifest="$HISTORY/last_manifest.tsv" type old new result
  [[ -f "$manifest" ]] || { echo "No last rollback manifest found."; return 1; }
  echo "Rollback will restore successful renames from:"; echo "$manifest"
  echo "Type ROLLBACK exactly to continue:"
  read -r confirm
  [[ "$confirm" == "ROLLBACK" ]] || { echo "Cancelled."; return 0; }
  # Reverse order to reduce dependency/collision risk. Rollback intentionally does
  # not require a current audit because it restores a recorded prior mutation.
  tail -n +2 "$manifest" | tac | while IFS=$'\t' read -r type old new result; do
    [[ "$result" == "OK" ]] || continue
    if [[ -e "$new" && ! -e "$old" ]]; then mv -- "$new" "$old" || echo "FAILED: $new"; else echo "SKIP: cannot safely restore $old"; fi
  done
  echo "Rollback pass finished. Re-run the auditor to verify the library."
}

echo "MiSTer ROM Library Updater v1.3"
echo "================================="
echo "1) Preview safe renames"
echo "2) Apply safe renames"
echo "3) Roll back last applied cleanup"
echo "4) Exit"
read -r choice
case "$choice" in
  1) preview ;;
  2) apply_plan ;;
  3) rollback ;;
  *) exit 0 ;;
esac
