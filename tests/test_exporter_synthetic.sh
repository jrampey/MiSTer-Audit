#!/usr/bin/env bash
set -euo pipefail

ROOT="${RUNNER_TEMP:-/tmp}/mister-synthetic"
AUDIT="$ROOT/GameLibraryAudit"
BUNDLE="$AUDIT/MiSTer_Library_Audit.txt"
CATALOG="$AUDIT/library_catalog.csv"
EXPECTED_DISCOVERED=6576
EXPECTED_SKIPPED=107
EXPECTED_CATALOGED=6469

fail() { echo "ERROR: $*" >&2; exit 1; }

# This test is intended for a disposable CI runner and uses a writable temp
# root rather than the production MiSTer path /media/fat.
[ "${CI:-}" = "true" ] || fail "Synthetic integration test requires CI=true"
rm -rf "$ROOT"
mkdir -p "$ROOT"
python3 tests/build_synthetic_library.py "$ROOT"
# Unknown Region safety regressions.
mv "$ROOT/games/NES/Synthetic NES 0001 (USA).nes" "$ROOT/games/NES/Synthetic NES 0001 [Unknown Region].nes"
printf 'project documentation\n' > "$ROOT/games/MegaDrive/README.md"

before_games=$(find "$ROOT/games" -type f -printf '%P\t%s\n' | LC_ALL=C sort | sha256sum | awk '{print $1}')
before_saves=$(find "$ROOT/saves" -type f -printf '%P\t%s\n' | LC_ALL=C sort | sha256sum | awk '{print $1}')

# Exercise the production exporter code from an isolated copy, changing only
# its fixed MiSTer root so the GitHub-hosted runner never needs /media/fat.
# Keep the hash database beside the copy because the exporter resolves it
# relative to its own script directory.
TEST_BIN="$ROOT/test-bin"
mkdir -p "$TEST_BIN"
cp ./MiSTer_Audit.sh "$TEST_BIN/MiSTer_Audit.sh"
cp ./mister_hash_database.tsv "$TEST_BIN/mister_hash_database.tsv"
cp ./game_identity_aliases.tsv "$TEST_BIN/game_identity_aliases.tsv"
cp ./historical_us_retail.tsv "$TEST_BIN/historical_us_retail.tsv"
cp ./historical_console_eras.tsv "$TEST_BIN/historical_console_eras.tsv"
printf 'SNES\t1991-01-01\t2000-12-31\thttps://example.org/ci-fixture\n' >> "$TEST_BIN/historical_console_eras.tsv"
# Fixture-only history, not a claim about actual SNES release dates.
printf 'SNES\tCanonical Variant (USA)\tSNES-CANONICAL-VARIANT\n' >> "$TEST_BIN/game_identity_aliases.tsv"
printf 'SNES\tSNES-CANONICAL-VARIANT\tCanonical Variant\tYES\t1994-01-01\tSNES\thttps://example.org/ci-fixture\n' >> "$TEST_BIN/historical_us_retail.tsv"


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

# Dedicated Unknown-region routing regression. Give one synthetic ROM an authoritative
# DAT record with Unknown region so the generated proposal can be asserted end-to-end.
unknown_path="$ROOT/games/NES/Synthetic NES 0000 (USA).nes"; unknown_sha=$(sha1sum "$unknown_path" | awk '{print $1}')
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$unknown_sha" "Synthetic Unknown Region" "Synthetic Unknown Region.nes" "Synthetic Unknown Region regression" "20" "00000000" "00000000000000000000000000000000" "NES" "NES" "NES" "Unknown" "Retail/Standard" "Licensed/Official" >> "$TEST_BIN/mister_hash_database.tsv"

for rev in 1 2; do
  vp="$ROOT/games/SNES/Canonical Variant (USA) (Rev $rev).sfc"; vh=$(sha1sum "$vp" | awk '{print $1}')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$vh" "Canonical Variant (USA) (Rev $rev)" "Canonical Variant (USA) (Rev $rev).sfc" "Synthetic Issue #7" "12" "00000000" "00000000000000000000000000000000" "SNES" "SNES" "SNES" "USA" "Revision" "Licensed" >> "$TEST_BIN/mister_hash_database.tsv"
done
python3 - "$TEST_BIN/MiSTer_Audit.sh" "$ROOT" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
root = sys.argv[2]
text = p.read_text()
needle = 'ROOT="/media/fat"'
if text.count(needle) < 1:
    raise SystemExit('ERROR: production ROOT assignment not found')
text = text.replace(needle, f'ROOT="{root}"', 1)
p.write_text(text)
PY

# Shortcut 2 selects Full Verification immediately, avoiding the 15-second menu timeout.
printf '2' | bash "$TEST_BIN/MiSTer_Audit.sh" audit

[ -f "$BUNDLE" ] || fail "audit bundle was not published"
[ -f "$CATALOG" ] || fail "catalog CSV was not published"

[ -f "$AUDIT/curation_preferred.csv" ] || fail "preferred-retail report missing"
[ -f "$AUDIT/disc_sets.csv" ] || fail "disc-set inventory missing"
python3 - "$CATALOG" "$AUDIT/curation_preferred.csv" "$AUDIT/library_completion.csv" <<'PY'
import csv,sys
def read(p):
    with open(p,newline='') as f: return list(csv.DictReader(f))
catalog,preferred,completion=map(read,sys.argv[1:])
variant=[r for r in catalog if r['dat_canonical_name'].startswith('Canonical Variant (USA)')]
if len(variant)!=2: raise SystemExit(f'expected two synthetic revisions; got {len(variant)}')
parent=[r for r in variant if r['special_release_category']=='Retail/Standard']
alternates=[r for r in variant if r['special_release_category']=='Revision']
if len(parent)!=1 or len(alternates)!=1:
    raise SystemExit(f'preferred revision selection failed: {[(r["original_filename"],r["special_release_category"]) for r in variant]}')
if '(Rev 2)' not in parent[0]['dat_canonical_name'] or parent[0]['curated_destination'] != 'SNES':
    raise SystemExit('latest verified revision not selected as parent copy')
if alternates[0]['curated_destination']!='SNES/!Revision':
    raise SystemExit('nonpreferred revision not routed to shared revision folder')
prefs=[r for r in preferred if r['game_id']=='SNES-CANONICAL-VARIANT']
if len(prefs)!=1 or prefs[0]['eligible_copies']!='2' or prefs[0]['alternate_copies']!='1':
    raise SystemExit('curation preferred summary failed to reconcile')
snes=[r for r in completion if r['system']=='SNES']
if len(snes)!=1 or int(snes[0]['historically_verified_titles'])<1:
    raise SystemExit('historical manifest evidence was not reflected in completion report')
print('Preferred rev2, alternate rev1, and historical manifest fixture validated')
PY
grep -Fq 'Historically sourced decisions: 1' "$BUNDLE" || fail "historical manifest load result missing"
grep -Fq 'Disc-media groups:' "$BUNDLE" || fail "disc sets not inventoried"
grep -Fq 'disc media: set-aware routing not yet verified' "$TEST_BIN/MiSTer_Audit.sh" || fail "disc media mutation guard missing"


[ -f "$AUDIT/release_families.csv" ] || fail "release-family CSV was not published"
python3 - "$AUDIT/release_families.csv" "$AUDIT/dat_matches.csv" <<'PY'
import csv, sys
with open(sys.argv[1], newline='') as f:
    families = list(csv.DictReader(f))
with open(sys.argv[2], newline='') as f:
    matched = list(csv.DictReader(f))
if not families:
    raise SystemExit('release-family report is empty despite DAT matches')
if len(families) > len(matched):
    raise SystemExit('release-family grouping produced too many rows')
required = {'system', 'canonical_title', 'owned_release_count', 'retail_count', 'special_count', 'release_categories'}
if set(families[0]) != required:
    raise SystemExit('release-family CSV header malformed')
for row in families:
    if None in row or any(v is None for v in row.values()):
        raise SystemExit('release-family CSV has invalid column structure')
    if not row['system'].strip() or not row['canonical_title'].strip():
        raise SystemExit('release-family CSV missing identity')
    for key in ('owned_release_count', 'retail_count', 'special_count'):
        if not row[key].isdigit():
            raise SystemExit(f'release-family numeric field corrupt: {key}')
    if int(row['owned_release_count']) != int(row['retail_count']) + int(row['special_count']):
        raise SystemExit('release-family total does not reconcile')
if not any('Canonical Variant' in row['canonical_title'] for row in families):
    raise SystemExit('revision family missing from report')
print(f'Validated {len(families)} well-formed release families')
PY
grep -Fq 'Completion reference: bundled hash database' "$BUNDLE" || fail "completion denominator provenance missing"
grep -Fq 'Unmatched identities: hash-eligible' "$BUNDLE" || fail "unmatched identity limitation missing"
grep -Fq 'Collision interpretation:' "$BUNDLE" || fail "collision safety explanation missing"


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
# Unmatched ROMs are inventory-only and do not participate in rename collision planning.
[ "$blocking" -eq 2 ] || fail "blocking collision rows=$blocking expected=2"

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
# Curated naming: USA Retail/Standard lives in the system root with the USA
# region marker removed, while special releases retain their identifying marker.
grep -Fq '"Canonical Variant (Rev 1).sfc"' "$AUDIT/proposed_renames.csv" || fail "USA retail canonical filename was not cleaned"
grep -Fq '"Canonical Variant (Rev 2).sfc"' "$AUDIT/proposed_renames.csv" || fail "USA retail revision marker was not preserved"
grep -Fq '"Super Noah' "$AUDIT/proposed_renames.csv" || fail "special-release canonical proposal missing"
grep -Fq '(Unl).sfc' "$AUDIT/proposed_renames.csv" || fail "special-release category marker was not preserved"
grep -Fq 'Synthetic GameGear 05742' "$CATALOG" || fail "tail sentinel missing"
grep -Eq '"(Homebrew|Unlicensed)","SNES/!(Homebrew|Unlicensed)"' "$AUDIT/proposed_renames.csv" || fail "special-release curated destination missing from rename proposals"
# Curated folders are release-type buckets only: <system>/<ROM type>. Retail/Standard
# remains directly in the system folder. Never create genre or per-ROM directories.
python3 - "$AUDIT/proposed_renames.csv" <<'PY'
import csv, sys
allowed = {"Homebrew", "Unlicensed", "Aftermarket", "Prototype", "Beta", "Demo/Sample", "Translation", "Hack/Modified", "Revision", "Alternate Retail", "Reissue/Compilation", "Unofficial/Pirate", "Development/Diagnostic", "Non-Retail", "Historical Exclusion"}
with open(sys.argv[1], newline="") as f:
    for row in csv.DictReader(f):
        category = row.get("special_release_category", "")
        destination = row.get("curated_destination", "")
        system = row.get("system", "")
        if category == "Retail/Standard":
            if destination not in ("", "Unknown", system, f"{system}/!Unknown Region", *(f"{system}/!{r}" for r in ("World", "Japan", "Europe", "Canada", "Australia", "Korea", "Brazil", "Other Regions"))):
                raise SystemExit(f"ERROR: retail ROM routed outside system root: {destination}")
            continue
        if category not in allowed:
            raise SystemExit(f"ERROR: non-ROM-type curated category: {category}")
        parts = destination.split("/")
        if len(parts) != 2 or parts[0] != system or parts[1] != "!" + category.replace("/", "-"):
            raise SystemExit(f"ERROR: curated destination must be exactly <system>/<ROM type>: {destination}")
PY
grep -Fq '"special_release_category","curated_destination"' "$AUDIT/dat_matches.csv" || fail "DAT match report missing ROM-type reporting columns"
for category in "Retail/Standard" "Homebrew" "Unlicensed" "Aftermarket" "Prototype" "Beta" "Demo/Sample" "Translation" "Hack/Modified"; do
    grep -Fq "$category" "$AUDIT/game_library.txt" || fail "human-readable report missing ROM-type category: $category"
done
grep -Fq 'dir="$GAMES/$curated_destination"' "$TEST_BIN/MiSTer_Audit.sh" || fail "updater curated-destination routing missing"
# Unknown-region rows must be reported and applied into a dedicated system bucket.
grep -Eq '"Unknown","[^"]+","[^"]+","Retail/Standard","[^"]+/!Unknown Region"' "$AUDIT/proposed_renames.csv" || fail "Unknown-region curated destination missing"
grep -Fq 'dir="$GAMES/$curated_destination"' "$TEST_BIN/MiSTer_Audit.sh" || fail "updater regional curated-destination routing missing"
grep -Fq '!Unknown Region' "$AUDIT/proposed_renames.csv" || fail "Unknown-region folder is not sort-prefixed"
python3 - "$AUDIT/proposed_renames.csv" "$AUDIT/library_catalog.csv" "$AUDIT/support_files.csv" <<'PY'
import csv, sys
renames, catalog, support = sys.argv[1:]
with open(renames, newline="") as f:
    rows = list(csv.DictReader(f))
legacy = next((r for r in rows if r["current_path"].endswith("Synthetic NES 0001 [Unknown Region].nes")), None)
if legacy is None:
    raise SystemExit("ERROR: legacy Unknown Region fixture missing")
if legacy["proposed_filename"] != "Synthetic NES 0001 [Unknown Region].nes":
    raise SystemExit("ERROR: unmatched Unknown Region filename was changed or stacked")
if legacy["curated_destination"] != "NES/!Unknown Region":
    raise SystemExit("ERROR: unmatched eligible ROM not routed to !Unknown Region")
for r in rows:
    if r["system"] == "GameGear":
        if r["proposed_filename"] != r["current_path"].rsplit("/", 1)[-1]:
            raise SystemExit("ERROR: unsupported inventory received a rename proposal")
        if r["curated_destination"] not in ("", "Unknown"):
            raise SystemExit("ERROR: unsupported inventory received a curated destination")
with open(catalog, newline="") as f:
    if any(r["original_filename"].lower() == "readme.md" for r in csv.DictReader(f)):
        raise SystemExit("ERROR: README.md was cataloged as a Mega Drive ROM")
with open(support, newline="") as f:
    if not any(r.get("original_filename","").lower() == "readme.md" for r in csv.DictReader(f)):
        raise SystemExit("ERROR: README.md was not classified as support")
PY

# The MiSTer regression came from direct arithmetic evaluation of a filename-
# derived associative-array subscript. Keep that unsafe pattern out permanently.
if grep -Fq 'FINAL_PROPOSAL_COUNTS["$final_key"]=$((FINAL_PROPOSAL_COUNTS["$final_key"]+1))' ./MiSTer_Audit.sh; then
    fail "unsafe filename-derived associative arithmetic returned"
fi

echo "Synthetic Full Verification regression test passed."
echo "Accounting: $cataloged cataloged + $skipped skipped = $discovered discovered"
echo "Integrity verdict: $verdict"


# Issue #9: unchanged Fast Audit must reuse row metadata and preserve the Full catalog.
cp "$CATALOG" "$ROOT/full-library_catalog.csv"
printf '1' | bash "$TEST_BIN/MiSTer_Audit.sh" audit
grep -Eq '^DAT/classification row metadata reused: [1-9][0-9]*$' "$BUNDLE" || fail "Fast Audit did not reuse row metadata"
python3 - "$ROOT/full-library_catalog.csv" "$CATALOG" <<'PY'
import csv,sys
def rows(p):
    with open(p,newline='') as f:
        return {r.get('full_path',''): r for r in csv.DictReader(f)}
full, fast = rows(sys.argv[1]), rows(sys.argv[2])
diffs = []
for path in sorted(set(full) | set(fast)):
    if path not in full:
        diffs.append((path, '<row>', '<missing>', 'present'))
        continue
    if path not in fast:
        diffs.append((path, '<row>', 'present', '<missing>'))
        continue
    for field in full[path]:
        if full[path].get(field) != fast[path].get(field):
            diffs.append((path, field, full[path].get(field,''), fast[path].get(field,'')))
if diffs:
    print(f'ERROR: Fast catalog differs from Full Verification in {len(diffs)} field(s)', file=sys.stderr)
    for path, field, a, b in diffs[:30]:
        print(f'  {path} | {field}: Full={a!r} Fast={b!r}', file=sys.stderr)
    raise SystemExit(1)
PY
probe="$ROOT/games/NES/Issue 9 Cache Probe (USA).nes"; printf 'issue9-probe' > "$probe"
printf '1' | bash "$TEST_BIN/MiSTer_Audit.sh" audit
grep -Fq 'New library records: 1' "$BUNDLE" || fail "added ROM not detected"
mv "$probe" "$ROOT/games/NES/Issue 9 Cache Probe Renamed (USA).nes"; printf '1' | bash "$TEST_BIN/MiSTer_Audit.sh" audit
grep -Fq 'New library records: 1' "$BUNDLE" || fail "rename new path not detected"; grep -Fq 'Deleted library records: 1' "$BUNDLE" || fail "rename old path not detected"
rm "$ROOT/games/NES/Issue 9 Cache Probe Renamed (USA).nes"; printf '1' | bash "$TEST_BIN/MiSTer_Audit.sh" audit
grep -Fq 'Deleted library records: 1' "$BUNDLE" || fail "deleted ROM not detected"
printf '# issue9 fingerprint invalidation\n' >> "$TEST_BIN/mister_hash_database.tsv"; printf '1' | bash "$TEST_BIN/MiSTer_Audit.sh" audit
grep -Fq 'DAT/classification row metadata reused: 0' "$BUNDLE" || fail "DB change did not invalidate row metadata"
grep -Eq '^Hashes reused from cache: [1-9][0-9]*$' "$BUNDLE" || fail "DB change invalidated reusable hashes"

# Guard helper required by clean_title_set on the MiSTer runtime.
grep -q '^trim_set() {' "$TEST_BIN/MiSTer_Audit.sh" || fail "trim_set helper missing from runtime"

# Menu regression: non-shortcut keys are parsed as possible ANSI arrow sequences.
grep -Fq 'IFS= read -rsn1 -t 0.15 AUDIT_KEY2' "$TEST_BIN/MiSTer_Audit.sh" || fail "audit menu ANSI arrow sequence handler missing"
grep -Fq 'if [ "$AUDIT_KEY2" = "[" ]; then' "$TEST_BIN/MiSTer_Audit.sh" || fail "audit menu ANSI CSI handler missing"
grep -Fq 'IFS= read -rsn1 -t 0.15 AUDIT_KEY2' "$TEST_BIN/MiSTer_Audit.sh" || fail "audit menu ANSI arrow sequence handler missing"

# Progress elapsed time must use Bash SECONDS, not wall-clock epoch subtraction.
grep -Fq 'AUDIT_START_SECONDS=$SECONDS' "$TEST_BIN/MiSTer_Audit.sh" || fail "monotonic audit timer missing"
grep -Fq 'now=$SECONDS' "$TEST_BIN/MiSTer_Audit.sh" || fail "progress timer is not monotonic"
if grep -Fq 'now=$(date +%s)' "$TEST_BIN/MiSTer_Audit.sh"; then fail "wall-clock progress timer regression returned"; fi

# Apply compatibility must accept the auditor's collision-only recommendation contract.
grep -Fq '"SAFE TO PREVIEW (COLLISIONS SKIPPED)"' "$TEST_BIN/MiSTer_Audit.sh" || fail "Apply does not recognize collision-only audit recommendation"

# Regional routing regression: authoritative retail uses resolved No-Intro geography.
grep -Fq 'Japan) region_folder="Japan"' "$TEST_BIN/MiSTer_Audit.sh" || fail "Japan retail routing missing"
grep -Fq 'Europe) region_folder="Europe"' "$TEST_BIN/MiSTer_Audit.sh" || fail "Europe retail routing missing"
grep -Fq 'World) region_folder="World"' "$TEST_BIN/MiSTer_Audit.sh" || fail "World retail routing missing"
grep -Fq '*) region_folder="Other Regions"' "$TEST_BIN/MiSTer_Audit.sh" || fail "Other-region retail routing missing"
# Special-release precedence under alternative regions is exercised by test_preferences.py.

# Virtual Console regression: VC ROM images are a distinct curated release type. Classification must inspect both canonical ROM filename and canonical title because No-Intro sources may carry the VC qualifier in either field.
grep -Fq 'HOT_RESULT="Virtual Console"' "$TEST_BIN/MiSTer_Audit.sh" || fail "Virtual Console category classification missing"
grep -Fq 'special_release_category_set "$meta_release" "$meta_license" "$dat_rom $dat_name"' "$TEST_BIN/MiSTer_Audit.sh" || fail "Virtual Console classification does not inspect both canonical DAT identity fields"
grep -Fq 'case "$category" in Retail/Standard|Revision)' "$TEST_BIN/MiSTer_Audit.sh" || fail "Virtual Console variants still count toward retail completion"

# Apply cleanup regression: only known MiSTer-Audit category buckets may be pruned,
# and cleanup must use rmdir so non-empty directories are never deleted.
grep -Fq 'cleanup_empty_managed_dirs(){' "$TEST_BIN/MiSTer_Audit.sh" || fail "managed empty-directory cleanup helper missing"
grep -Fq '"!Virtual Console"' "$TEST_BIN/MiSTer_Audit.sh" || fail "Virtual Console missing from managed cleanup whitelist"
grep -Fq '"!Unknown Region"' "$TEST_BIN/MiSTer_Audit.sh" || fail "Unknown Region missing from managed cleanup whitelist"
grep -Fq 'rmdir -- "$dir"' "$TEST_BIN/MiSTer_Audit.sh" || fail "managed cleanup is not using safe empty-only rmdir"
grep -Fq 'done;cleanup_empty_managed_dirs;cp "$manifest"' "$TEST_BIN/MiSTer_Audit.sh" || fail "Apply does not clean empty managed directories after moves"
if grep -Eq 'rm[[:space:]]+-r[f]?[[:space:]].*\$dir' "$TEST_BIN/MiSTer_Audit.sh"; then fail "recursive managed-directory deletion is unsafe"; fi
