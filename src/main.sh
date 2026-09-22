runtime_build_id() {
  local runtime_dir runtime_path digest
  runtime_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
  runtime_path="$runtime_dir/MiSTer_Audit.sh"
  [ -f "$runtime_path" ] || runtime_path="$0"
  if command -v sha1sum >/dev/null 2>&1; then
    digest="$(sha1sum "$runtime_path" 2>/dev/null)"; digest="${digest%% *}"
  elif command -v openssl >/dev/null 2>&1; then
    digest="$(openssl sha1 "$runtime_path" 2>/dev/null)"; digest="${digest##* }"
  else
    digest="UNAVAILABLE"
  fi
  printf '%.8s' "$digest"
}

main_menu() {
  local selection=1 key key2 key3 choice update_choice
  while :; do
    printf '\033[2J\033[H'
    echo "MiSTer ROM Library Auditor v1.4"
    echo "================================"
    echo "Build: $(runtime_build_id)"
    [ "$selection" -eq 1 ] && echo "> 1) Run library audit" || echo "  1) Run library audit"
    [ "$selection" -eq 2 ] && echo "> 2) Preview / Apply / Rollback" || echo "  2) Preview / Apply / Rollback"
    [ "$selection" -eq 3 ] && echo "> 3) Exit" || echo "  3) Exit"
    echo
    echo "Up/Down selects | Enter accepts | 1/2/3 shortcuts"
    key=""
    IFS= read -rsn1 key
    case "$key" in
      "") choice="$selection" ;;
      1|2|3) choice="$key" ;;
      $'\x1b')
        IFS= read -rsn1 -t 0.15 key2 || key2=""
        if [ "$key2" = "[" ]; then
          IFS= read -rsn1 -t 0.15 key3 || key3=""
          case "$key3" in
            A) selection=$((selection > 1 ? selection - 1 : 3)) ;;
            B) selection=$((selection < 3 ? selection + 1 : 1)) ;;
          esac
        fi
        continue
        ;;
      *) continue ;;
    esac
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
        IFS= read -rsn1 update_choice
        echo
        case "${update_choice:-1}" in
          2) run_update_tools; trap - EXIT INT TERM ;;
          *) continue ;;
        esac
        ;;
      3) exit 0 ;;
    esac
  done
}

case "${1:-}" in
  audit) run_audit ;;
  update|rename) run_update_tools ;;
  *) main_menu ;;
esac
