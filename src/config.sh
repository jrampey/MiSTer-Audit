trim_policy_value() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  printf '%s' "$v"
}

canonical_region() {
  case "${1,,}" in
    usa|us|u) printf USA ;; europe|eu|eur|e) printf Europe ;;
    japan|jp|jpn|j) printf Japan ;; world|w) printf World ;;
    canada|can) printf Canada ;; australia|aus) printf Australia ;;
    korea|kor|k) printf Korea ;; brazil|bra|b) printf Brazil ;;
    *) return 1 ;;
  esac
}

load_preferences() {
  local dir="$1" line key value region rest normalized section="" file i
  PARENT_REGION=USA; WORLD_IN_PARENT=0; GROUP_SPECIAL_RELEASES=1
  GROUP_OTHER_REGIONS=1; GROUP_UNKNOWN_REGION=1; STRIP_PARENT_REGION_TAG=1
  RENAME_PAIRED_SAVES=1; CLEANUP_EMPTY_MANAGED_DIRS=1
  COMPLETION_REGIONS=(PARENT); COMPLETION_INCLUDE_WORLD=1; COMPLETION_RETAIL_ONLY=1
  COMPLETION_INCLUDE_PROTOTYPES=0; COMPLETION_INCLUDE_BETA=0; COMPLETION_INCLUDE_DEMOS=0
  local -a parsed_regions=()
  PREFERENCES_FILE="$dir/MiSTer_Audit.ini"
  # Legacy completion settings remain supported only when the INI is absent.
  file="$PREFERENCES_FILE"
  if [ ! -e "$file" ]; then file="$dir/AUDIT_POLICY.conf"; fi
  if [ -e "$file" ] && [ ! -r "$file" ]; then echo "ERROR: Cannot read $file" >&2; return 1; fi
  if [ -r "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="$(trim_policy_value "$line")"
      case "$line" in ''|\#*|\;*) continue ;; '[organization]'|'[completion]'|'[update]') section="$line"; continue ;; '['*) echo "ERROR: Unknown INI section $line" >&2; return 1 ;; esac
      case "$line" in *=*) ;; *) echo "ERROR: Invalid preference: $line" >&2; return 1 ;; esac
      key="$(trim_policy_value "${line%%=*}")"; value="${line#*=}"
      value="${value%%;*}"; value="${value%%#*}"; value="$(trim_policy_value "$value")"
      case "$key" in
        PARENT_REGION) PARENT_REGION="$(canonical_region "$value")" || { echo "ERROR: Invalid PARENT_REGION: $value" >&2; return 1; } ;;
        COMPLETION_REGIONS)
          parsed_regions=(); rest="$value"
          while :; do
            case "$rest" in *,*) region="${rest%%,*}"; rest="${rest#*,}" ;; *) region="$rest"; rest="" ;; esac
            region="$(trim_policy_value "$region")"
            if [ "${region,,}" = parent ]; then normalized=PARENT
            else normalized="$(canonical_region "$region")" || { echo "ERROR: Invalid completion region: $region" >&2; return 1; }; fi
            parsed_regions+=("$normalized"); [ -n "$rest" ] || break
          done
          COMPLETION_REGIONS=("${parsed_regions[@]}") ;;
        WORLD_IN_PARENT|GROUP_SPECIAL_RELEASES|GROUP_OTHER_REGIONS|GROUP_UNKNOWN_REGION|STRIP_PARENT_REGION_TAG|RENAME_PAIRED_SAVES|CLEANUP_EMPTY_MANAGED_DIRS|COMPLETION_RETAIL_ONLY|COMPLETION_INCLUDE_WORLD|COMPLETION_INCLUDE_PROTOTYPES|COMPLETION_INCLUDE_BETA|COMPLETION_INCLUDE_DEMOS)
          case "$value" in 0|1) printf -v "$key" '%s' "$value" ;; *) echo "ERROR: $key must be 0 or 1" >&2; return 1 ;; esac ;;
        *) echo "ERROR: Unknown preference: $key" >&2; return 1 ;;
      esac
    done < "$file"
  fi
  for ((i=0;i<${#COMPLETION_REGIONS[@]};i++)); do
    [ "${COMPLETION_REGIONS[i]}" != PARENT ] || COMPLETION_REGIONS[i]="$PARENT_REGION"
  done
  PREFERENCES_SIGNATURE="$PARENT_REGION|$WORLD_IN_PARENT|$GROUP_SPECIAL_RELEASES|$GROUP_OTHER_REGIONS|$GROUP_UNKNOWN_REGION|$STRIP_PARENT_REGION_TAG|$RENAME_PAIRED_SAVES|$CLEANUP_EMPTY_MANAGED_DIRS|${COMPLETION_REGIONS[*]}|$COMPLETION_INCLUDE_WORLD|$COMPLETION_RETAIL_ONLY|$COMPLETION_INCLUDE_PROTOTYPES|$COMPLETION_INCLUDE_BETA|$COMPLETION_INCLUDE_DEMOS"
}

ensure_preferences_file() {
  local dir="$1"
  [ ! -e "$dir/MiSTer_Audit.ini" ] || return 0
  # noclobber also protects a file created concurrently by another invocation.
  (set -o noclobber; default_preferences > "$dir/MiSTer_Audit.ini") || return 1
  if [ -r "$dir/AUDIT_POLICY.conf" ]; then
    # Preserve legacy settings as last-value overrides on first migration.
    printf '\n; Migrated completion preferences\n[completion]\n' >> "$dir/MiSTer_Audit.ini"
    cat "$dir/AUDIT_POLICY.conf" >> "$dir/MiSTer_Audit.ini"
  fi
}

parent_region_matches() {
  local region="${1// /}" selected="${PARENT_REGION// /}"
  [[ ",$region," == *",$selected,"* ]] || { [ "$WORLD_IN_PARENT" = 1 ] && [ "$region" = World ]; }
}
strip_parent_tag() {
  local stem="$1" tag rest="$1" result="" token matches
  # Only remove a complete region group; never strip revisions or languages.
  while [[ "$rest" == *'('*')'* ]]; do
    result+="${rest%%(*}"; rest="${rest#*(}"; tag="${rest%%)*}"; rest="${rest#*)}"
    matches=0
    token="$(canonical_region "$tag")" && [ "$token" = "$PARENT_REGION" ] && matches=1
    [ "$matches" = 1 ] || result+="($tag)"
  done
  result+="$rest"
  printf '%s' "$result" | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+|[[:space:]]+$//g'
}
