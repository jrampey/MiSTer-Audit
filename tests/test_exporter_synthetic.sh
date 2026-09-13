#!/usr/bin/env bash
set -euo pipefail

ROOT="${RUNNER_TEMP:-/tmp}/mister-synthetic"
AUDIT="$ROOT/GameLibraryAudit"
BUNDLE="$AUDIT/MiSTer_Library_Audit.txt"
CATALOG="$AUDIT/library_catalog.csv"
EXPECTED_DISCOVERED=6575
EXPECTED_SKIPPED=106
EXPECTED_CATALOGED=6469

fail() { echo "ERROR: $*" >&2; exit 1; }

# This test is intended for a disposable CI runner and uses a writable temp
# root rather than the production MiSTer path /media/fat.
[ "${CI:-}" = "true" ] || fail "Synthetic integration test requires CI=true"
rm -rf "$ROOT"
mkdir -p "$ROOT"
python3 tests/build_synthetic_library.py "$ROOT"

before_games=$(find "$ROOT/games" -type f -printf '%P\t%s\n' | LC_ALL=C sort | sha256sum | awk '{print $1}')
before_saves=$(find "$ROOT/saves" -type f -printf '%P\t%s\n' | LC_ALL=C sort | sha256sum | awk '{print $1}')

# Exercise the production exporter code from an isolated copy, changing only
# its fixed MiSTer root so the GitHub-hosted runner never needs /media/fat.
# Keep the hash database beside the copy because the exporter resolves it
# relative to its own script directory.
TEST_BIN="$ROOT/test-bin"
mkdir -p "$TEST_BIN"
cp ./Export_Game_Library.sh "$TEST_BIN/Export_Game_Library.sh"
cp ./mister_hash_database.tsv "$TEST_BIN/mister_hash_database.tsv"

# Add one synthetic DAT identity used by two source filenames. This mirrors the
# real Super Noah's Ark 3D canonical collision without including ROM data.
collision_sha=$(sha1sum "$ROOT/games/SNES/Super 3D Noah's Ark.sfc" | awk '{print $1}')
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$collision_sha" \
  "Super Noah's Ark 3D (USA) (Unl)" \
  "Super Noah's Ark 3D (USA) (Unl).sfc" \
  "Synthetic Issue #6 regression" \
  "44" "00000000" "00000000000000000000000000000000" \
  "SNES" "SNES" "SNES" "USA" "Homebrew/Unlicensed" "Unlicensed" \
  >> "$TEST_BIN/mister_hash_database.tsv"

for rev in 1 2; do
  vp="$ROOT/games/SNES/Canonical Variant (USA) (Rev $rev).sfc"; vh=$(sha1sum "$vp" | awk '{print $1}')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$vh" "Canonical Variant (USA) (Rev $rev)" "Canonical Variant (USA) (Rev $rev).sfc" "Synthetic Issue #7" "12" "00000000" "00000000000000000000000000000000" "SNES" "SNES" "SNES" "USA" "Revision" "Licensed" >> "$TEST_BIN/mister_hash_database.tsv"
done
python3 - "$TEST_BIN/Export_Game_Library.sh" "$ROOT" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
root = sys.argv[2]
text = p.read_text()
needle = 'ROOT="/media/fat"'
if text.count(needle) != 1:
    raise SystemExit('ERROR: expected exactly one production ROOT assignment')
text = text.replace(needle, f'ROOT="{root}"', 1)
p.write_text(text)
PY

# Shortcut 2 selects Full Verification immediately, avoiding the 15-second menu timeout.
printf '2' | bash "$TEST_BIN/Export_Game_Library.sh"

[ -f "$BUNDLE" ] || fail "audit bundle was not published"
[ -f "$CATALOG" ] || fail "catalog CSV was not published"

after_games=$(find "$ROOT/games" -type f -printf '%P\t%s\n' | LC_ALL=C sort | sha256sum | awk '{print $1}')
after_saves=$(find "$ROOT/saves" -type f -printf '%P\t%s\n' | LC_ALL=C sort | sha256sum | awk '{print $1}')
[ "$before_games" = "$after_games" ] || fail "game library changed during read-only audit"
[ "$before_saves" = "$after_saves" ] || fail "save library changed during read-only audit"

value_after_colon() { grep -m1 "^$1:" "$BUNDLE" | sed 's/^[^:]*:[[:space:]]*//'; }

discovered=$(value_after_colon "Files discovered")
cataloged=$(value_after_colon "Games/discs cataloged")
skipped=$(value_after_colon "BIOS/support files skipped")
verdict=$(value_after_colon "Audit integrity verdict")
blocking=$(value_after_colon "Blocking collision rows")
resolved=$(value_after_colon "Canonical DAT variant rows resolved safely")

[ "$discovered" = "$EXPECTED_DISCOVERED" ] || fail "discovered=$discovered expected=$EXPECTED_DISCOVERED"
[ "$cataloged" = "$EXPECTED_CATALOGED" ] || fail "cataloged=$cataloged expected=$EXPECTED_CATALOGED"
[ "$skipped" = "$EXPECTED_SKIPPED" ] || fail "skipped=$skipped expected=$EXPECTED_SKIPPED"
[ $((cataloged + skipped)) -eq "$discovered" ] || fail "discovery accounting does not balance"
[ "$verdict" != "FAIL" ] || fail "audit integrity verdict is FAIL"
[ "$resolved" -eq 2 ] || fail "resolved canonical variants=$resolved expected=2"
[ "$blocking" -eq 4 ] || fail "blocking collision rows=$blocking expected=4"

catalog_rows=$(( $(wc -l < "$CATALOG") - 1 ))
[ "$catalog_rows" -eq "$EXPECTED_CATALOGED" ] || fail "catalog CSV rows=$catalog_rows expected=$EXPECTED_CATALOGED"

if grep -qE 'catalog-count-mismatch|discovery-accounting-mismatch' "$BUNDLE"; then
    fail "catalog accounting integrity note present"
fi

# Spot-check records from the beginning, middle-system mix, and end of the
# generated profile so a truncated PLAN/report loop cannot pass on counts alone.
grep -Fq 'Synthetic NES 0000' "$CATALOG" || fail "first-system sentinel missing"
grep -Fq 'Synthetic TGFX16 0119' "$CATALOG" || fail "hashed-system sentinel missing"
grep -Fq 'Super 3D Noah' "$CATALOG" || fail "first canonical-collision source missing"
grep -Fq "Super Noah's Ark 3D (U) .smc" "$CATALOG" || fail "second canonical-collision source missing"
grep -Fq 'Synthetic GameGear 05742' "$CATALOG" || fail "tail sentinel missing"

# The MiSTer regression came from direct arithmetic evaluation of a filename-
# derived associative-array subscript. Keep that unsafe pattern out permanently.
if grep -Fq 'FINAL_PROPOSAL_COUNTS["$final_key"]=$((FINAL_PROPOSAL_COUNTS["$final_key"]+1))' ./Export_Game_Library.sh; then
    fail "unsafe filename-derived associative arithmetic returned"
fi

echo "Synthetic Full Verification regression test passed."
echo "Accounting: $cataloged cataloged + $skipped skipped = $discovered discovered"
echo "Integrity verdict: $verdict"
