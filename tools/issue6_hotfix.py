#!/usr/bin/env python3
"""One-shot repository patch for Issue #6. Removed by its workflow after use."""
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if text.count(old) != 1:
        raise SystemExit(f"ERROR: expected exactly one patch target in {path}, found {text.count(old)}")
    p.write_text(text.replace(old, new, 1))


# Root cause: FINAL_PROPOSAL_COUNTS was dead state, but its duplicate increment
# referenced a filename-derived associative subscript directly inside Bash
# arithmetic expansion. On the MiSTer shell the second canonical duplicate with
# an apostrophe (Super Noah's Ark 3D) aborts the current report row and exhausts
# the report loop, leaving the remaining PLAN rows uncataloged.
replace_once(
    "Export_Game_Library.sh",
    '''  # DAT-driven canonical names can create a collision not visible to the\n  # filename-only first pass. Never invent a variant name for an Apply candidate.\n  final_key="${system,,}|${proposed,,}"\n  if [ -n "${FINAL_PROPOSAL_COUNTS[$final_key]+x}" ]; then\n    FINAL_PROPOSAL_COUNTS["$final_key"]=$((FINAL_PROPOSAL_COUNTS["$final_key"]+1))\n  else\n    FINAL_PROPOSAL_COUNTS["$final_key"]=1\n  fi\n\n''',
    '''  # Do not perform arithmetic on filename-derived associative-array\n  # subscripts here. Canonical duplicate safety is enforced later by the\n  # updater's preview/apply validation; the exporter only records proposals.\n\n''',
)
replace_once(
    "Export_Game_Library.sh",
    "declare -A SEEN_NAMES FINAL_PROPOSAL_COUNTS\n",
    "declare -A SEEN_NAMES\n",
)

# Strengthen the synthetic fixture with the exact shape that exposed the real
# MiSTer failure: two differently named files resolving to one canonical title
# containing an apostrophe and unlicensed metadata.
replace_once(
    "tests/build_synthetic_library.py",
    '''    # The bulk profile uses an intentionally unsupported hash extension that is\n    # still part of exporter discovery. This keeps the 6,575-file regression\n    # test fast while exercising the same classification/report accounting path.\n    bulk = games / "GameGear"\n''',
    '''    # Canonical-collision regression for Issue #6. The test harness adds the\n    # shared synthetic SHA-1 to its temporary hash database so both source names\n    # resolve to the same apostrophe-bearing canonical ROM name.\n    special = games / "SNES"\n    special_payload = b"synthetic canonical collision for issue 6\\n"\n    for name in ("Super 3D Noah's Ark.sfc", "Super Noah's Ark 3D (U) .smc"):\n        (special / name).write_bytes(special_payload)\n        created += 1\n\n    # The bulk profile uses an intentionally unsupported hash extension that is\n    # still part of exporter discovery. This keeps the 6,575-file regression\n    # test fast while exercising the same classification/report accounting path.\n    bulk = games / "GameGear"\n''',
)

replace_once(
    "tests/test_exporter_synthetic.sh",
    '''cp ./Export_Game_Library.sh "$TEST_BIN/Export_Game_Library.sh"\ncp ./mister_hash_database.tsv "$TEST_BIN/mister_hash_database.tsv"\npython3 - "$TEST_BIN/Export_Game_Library.sh" "$ROOT" <<'PY'\n''',
    '''cp ./Export_Game_Library.sh "$TEST_BIN/Export_Game_Library.sh"\ncp ./mister_hash_database.tsv "$TEST_BIN/mister_hash_database.tsv"\n\n# Add one synthetic DAT identity used by two source filenames. This mirrors the\n# real Super Noah's Ark 3D canonical collision without including ROM data.\ncollision_sha=$(sha1sum "$ROOT/games/SNES/Super 3D Noah's Ark.sfc" | awk '{print $1}')\nprintf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' \\
  "$collision_sha" \\
  "Super Noah's Ark 3D (USA) (Unl)" \\
  "Super Noah's Ark 3D (USA) (Unl).sfc" \\
  "Synthetic Issue #6 regression" \\
  "44" "00000000" "00000000000000000000000000000000" \\
  "SNES" "SNES" "SNES" "USA" "Homebrew/Unlicensed" "Unlicensed" \\
  >> "$TEST_BIN/mister_hash_database.tsv"\n\npython3 - "$TEST_BIN/Export_Game_Library.sh" "$ROOT" <<'PY'\n''',
)

replace_once(
    "tests/test_exporter_synthetic.sh",
    '''grep -Fq 'Synthetic TGFX16 0119' "$CATALOG" || fail "hashed-system sentinel missing"\ngrep -Fq 'Synthetic GameGear 05748' "$CATALOG" || fail "tail sentinel missing"\n\necho "Synthetic Full Verification regression test passed."\n''',
    '''grep -Fq 'Synthetic TGFX16 0119' "$CATALOG" || fail "hashed-system sentinel missing"\ngrep -Fq 'Super 3D Noah' "$CATALOG" || fail "first canonical-collision source missing"\ngrep -Fq "Super Noah's Ark 3D (U) .smc" "$CATALOG" || fail "second canonical-collision source missing"\ngrep -Fq 'Synthetic GameGear 05746' "$CATALOG" || fail "tail sentinel missing"\n\n# The MiSTer regression came from direct arithmetic evaluation of a filename-\n# derived associative-array subscript. Keep that unsafe pattern out permanently.\nif grep -Fq 'FINAL_PROPOSAL_COUNTS["$final_key"]=$((FINAL_PROPOSAL_COUNTS["$final_key"]+1))' ./Export_Game_Library.sh; then\n    fail "unsafe filename-derived associative arithmetic returned"\nfi\n\necho "Synthetic Full Verification regression test passed."\n''',
)

# Documentation consistency guard requires README, PROJECT_CONTEXT, and wiki
# coverage whenever runtime behavior changes.
for path, heading, body in [
    (
        "README.md",
        "### Issue #6 catalog-accounting hardening",
        "The v1.3 exporter avoids arithmetic evaluation of filename-derived associative-array subscripts during canonical proposal handling. A real MiSTer library exposed this when two SNES source files resolved to the same apostrophe-bearing canonical No-Intro name; the second row could truncate report generation. The synthetic Full Verification regression now includes that canonical-duplicate shape and still requires every discovered file to be accounted for.\n",
    ),
    (
        "PROJECT_CONTEXT.md",
        "## Issue #6 canonical-collision regression",
        "Real MiSTer evidence localized the 267-row catalog loss to the second source file resolving to `Super Noah's Ark 3D (USA) (Unl).sfc`. The DAT-match row was emitted, but the catalog row was not. The cause was dead `FINAL_PROPOSAL_COUNTS` bookkeeping that performed Bash arithmetic through a filename-derived associative subscript. That bookkeeping was removed; canonical collision safety remains enforced by preview/apply validation, and the synthetic regression now covers duplicate canonical identities with apostrophe-bearing names.\n",
    ),
    (
        "wiki/Audit-Safety.md",
        "## Canonical duplicate accounting",
        "Audit generation must never evaluate canonical filenames as arithmetic expressions. The exporter records every source row even when multiple source files resolve to the same canonical DAT filename. Integrity accounting still requires `cataloged + skipped = discovered`, and the regression suite includes the duplicate canonical pattern that exposed Issue #6 on real MiSTer hardware.\n",
    ),
]:
    p = Path(path)
    text = p.read_text()
    marker = f"\n{heading}\n"
    if marker not in text:
        p.write_text(text.rstrip() + "\n\n" + heading + "\n\n" + body)

print("Issue #6 hotfix applied")
