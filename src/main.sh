main_menu() {
  while :; do
    echo
    echo "MiSTer ROM Library Auditor v1.4"
    echo "================================"
    echo "1) Run library audit"
    echo "2) Preview / Apply / Rollback"
    echo "3) Exit"
    read -r choice
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
        read -r update_choice
        case "${update_choice:-1}" in
          2) run_update_tools; trap - EXIT INT TERM ;;
          *) continue ;;
        esac
        ;;
      3|*) exit 0 ;;
    esac
  done
}

case "${1:-}" in
  audit) run_audit ;;
  update|rename) run_update_tools ;;
  *) main_menu ;;
esac
