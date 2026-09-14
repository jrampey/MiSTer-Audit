from pathlib import Path

path = Path('Export_Game_Library.sh')
text = path.read_text()
start = text.index('AUDIT_MENU_SELECTION=1\n')
end = text.index('if [ "$AUDIT_MENU_SELECTION" -eq 2 ]; then', start)
new = '''AUDIT_MENU_SELECTION=1
render_audit_menu() {
  printf "+--------------------------------------------------+\\n"
  printf "| SELECT AUDIT MODE                                |\\n"
  printf "+--------------------------------------------------+\\n"
  printf "|  UP / LEFT    FAST AUDIT                         |\\n"
  printf "|               Recommended - reuses cached hashes |\\n"
  printf "|                                                  |\\n"
  printf "|  DOWN / RIGHT FULL VERIFICATION                  |\\n"
  printf "|               Recalculates every supported SHA-1 |\\n"
  printf "+--------------------------------------------------+\\n"
  printf "| D-pad selects and starts immediately             |\\n"
  printf "| Keyboard: 1 = Fast | 2 = Full | Auto Fast: 15s  |\\n"
  printf "+--------------------------------------------------+\\n"
}
render_audit_menu
while :; do
  AUDIT_KEY=""
  if ! IFS= read -rsn1 -t 15 AUDIT_KEY; then
    AUDIT_MENU_SELECTION=1
    break
  fi
  case "$AUDIT_KEY" in
    ""|1|f|F)
      AUDIT_MENU_SELECTION=1
      break
      ;;
    2|v|V)
      AUDIT_MENU_SELECTION=2
      break
      ;;
    $'\\x1b')
      IFS= read -rsn1 -t 0.15 AUDIT_KEY2 || AUDIT_KEY2=""
      if [ "$AUDIT_KEY2" = "[" ]; then
        IFS= read -rsn1 -t 0.15 AUDIT_KEY3 || AUDIT_KEY3=""
        case "$AUDIT_KEY3" in
          A|D) AUDIT_MENU_SELECTION=1; break ;;
          B|C) AUDIT_MENU_SELECTION=2; break ;;
        esac
      fi
      ;;
  esac
done
'''
path.write_text(text[:start] + new + text[end:])

note = 'The audit-mode selector is controller-first: D-pad/arrow input selects and starts Fast Audit or Full Verification immediately, with no Enter confirmation required; keyboard 1/2 remains available and Fast Audit auto-starts after 15 seconds.'
for doc in (Path('README.md'), Path('PROJECT_CONTEXT.md'), Path('wiki/Audit-Workflow.md')):
    if doc.exists():
        body = doc.read_text()
        if note not in body:
            doc.write_text(body.rstrip() + '\n\n' + note + '\n')
