#!/usr/bin/env python3
"""Direct unit checks for tag-sensitive retail classifier and completion scope."""
from pathlib import Path
import subprocess

text = Path("src/audit.sh").read_text()
def segment(first, end):
    return text[text.index(first):text.index(end, text.index(first))]
functions = segment("special_release_category_set() {", "curated_destination_set() {")
functions += segment("completion_release_selected() {", "completion_record_eligible() {")
checks = r'''
COMPLETION_RETAIL_ONLY=1
COMPLETION_INCLUDE_PROTOTYPES=0
COMPLETION_INCLUDE_BETA=0
COMPLETION_INCLUDE_DEMOS=0
category() {
  special_release_category_set "$2" "Licensed" "$1"
  [ "$HOT_RESULT" = "$3" ] || { echo "Category mismatch: $1 ($HOT_RESULT, expected $3)" >&2; exit 1; }
}
include() {
  completion_release_selected "Retail/Standard" "Licensed" "$1" || { echo "Original retail wrongly excluded: $1" >&2; exit 1; }
}
exclude() {
  if completion_release_selected "Retail/Standard" "Licensed" "$1"; then
    echo "Special release wrongly included as retail: $1" >&2; exit 1
  fi
}
category "Demolition Man (USA)" "Retail/Standard" "Retail/Standard"
category "Demon Attack (USA)" "Retail/Standard" "Retail/Standard"
category "Sid Meier's Pirates! (USA)" "Retail/Standard" "Retail/Standard"
category "Hacker II (USA)" "Retail/Standard" "Retail/Standard"
category "Dragon King (World) (Pirate)" "Retail/Standard" "Unofficial/Pirate"
category "40 Winks (USA) (Piko Interactive)" "Retail/Standard" "Reissue/Compilation"
category "Test Game (USA) (Rev 2)" "Revision" "Revision"
category "Test Game (USA) (Demo)" "Retail/Standard" "Demo/Sample"
include "Demolition Man (USA)"
include "Sid Meier's Pirates! (USA)"
include "Hacker II (USA)"
include "Test Game (USA) (Rev 2)"
exclude "Dragon King (World) (Pirate)"
exclude "40 Winks (USA) (Piko Interactive)"
exclude "Test Game (USA) (Demo)"
echo "Retail-title qualifier/classification regression passed"
'''
subprocess.run(["bash", "-ec", functions + "\n" + checks], check=True)
