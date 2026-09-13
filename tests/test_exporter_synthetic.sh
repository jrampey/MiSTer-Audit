#!/usr/bin/env bash
set -euo pipefail

ROOT="/media/fat"
AUDIT="$ROOT/GameLibraryAudit"
BUNDLE="$AUDIT/MiSTer_Library_Audit.txt"
CATALOG="$AUDIT/library_catalog.csv"
EXPECTED_DISCOVERED=6575
EXPECTED_SKIPPED=106
EXPECTED_CATALOGED=6469

fail() { echo "ERROR: $*" >&2; exit 1; }

# This test is intended for a disposable GitHub-hosted runner. Never overlay a
# real MiSTer installation or an existing /media/fat tree.
[ "${CI:-}" = "true" ] || fail "Synthetic integration test requires CI=true"
[ ! -e "$ROOT/games" ] || fail "$ROOT/games already exists; refusing to continue"
[ ! -e "$ROOT/saves" ] || fail "$ROOT/saves already exists; refusing to continue"
[ ! -e "$AUDIT" ] || fail "$AUDIT already exists; refusing to continue"

mkdir -p "$ROOT"
python3 tests/build_synthetic_library.py "$ROOT"

before_games=$(find "$ROOT/games" -type f -printf '%P\t%s\n' | LC_ALL=C sort | sha256sum | awk '{print $1}')
before_saves=$(find "$ROOT/saves" -type f -printf '%P\t%s\n' | LC_ALL=C sort | sha256sum | awk '{print $1}')

# Shortcut 2 selects Full Verification immediately, avoiding the 15-second menu timeout.
printf '2' | bash ./Export_Game_Library.sh

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

[ "$discovered" = "$EXPECTED_DISCOVERED" ] || fail "discovered=$discovered expected=$EXPECTED_DISCOVERED"
[ "$cataloged" = "$EXPECTED_CATALOGED" ] || fail "cataloged=$cataloged expected=$EXPECTED_CATALOGED"
[ "$skipped" = "$EXPECTED_SKIPPED" ] || fail "skipped=$skipped expected=$EXPECTED_SKIPPED"
[ $((cataloged + skipped)) -eq "$discovered" ] || fail "discovery accounting does not balance"
[ "$verdict" != "FAIL" ] || fail "audit integrity verdict is FAIL"

catalog_rows=$(( $(wc -l < "$CATALOG") - 1 ))
[ "$catalog_rows" -eq "$EXPECTED_CATALOGED" ] || fail "catalog CSV rows=$catalog_rows expected=$EXPECTED_CATALOGED"

if grep -qE 'catalog-count-mismatch|discovery-accounting-mismatch' "$BUNDLE"; then
    fail "catalog accounting integrity note present"
fi

# Spot-check records from the beginning, middle-system mix, and end of the
# generated profile so a truncated PLAN/report loop cannot pass on counts alone.
grep -Fq 'Synthetic NES 0000' "$CATALOG" || fail "first-system sentinel missing"
grep -Fq 'Synthetic TGFX16 0119' "$CATALOG" || fail "hashed-system sentinel missing"
grep -Fq 'Synthetic GameGear 05748' "$CATALOG" || fail "tail sentinel missing"

echo "Synthetic Full Verification regression test passed."
echo "Accounting: $cataloged cataloged + $skipped skipped = $discovered discovered"
echo "Integrity verdict: $verdict"
