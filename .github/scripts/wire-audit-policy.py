from pathlib import Path

p = Path('MiSTer-Audit-Export.sh')
s = p.read_text()

old = '''# ---------------------------------------------------------------------------
# LIBRARY COMPLETION REGIONS
# ---------------------------------------------------------------------------
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
'''

new = r'''# ---------------------------------------------------------------------------
# AUDIT POLICY
# ---------------------------------------------------------------------------
# Defaults intentionally preserve v1.3 behavior. AUDIT_POLICY.conf is optional;
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
'''

if old not in s:
    raise SystemExit('Expected completion policy block not found')
s = s.replace(old, new, 1)
p.write_text(s)
