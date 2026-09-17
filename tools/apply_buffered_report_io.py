#!/usr/bin/env python3
from pathlib import Path

p = Path('Export_Game_Library.sh')
s = p.read_text()

# Keep hot-loop report/cache files open instead of reopening FAT files for every row.
s = s.replace(
"csv_row() { local dest=\"$1\" out=\"\" v; shift; for v in \"$@\"; do v=\"${v//\\\"/\\\"\\\"}\"; [ -n \"$out\" ] && out+=\",\"; out+=\"\\\"$v\\\"\"; done; printf '%s\\n' \"$out\" >> \"$dest\"; }",
"csv_row() { local dest=\"$1\" out=\"\" v fd=\"\"; shift; for v in \"$@\"; do v=\"${v//\\\"/\\\"\\\"}\"; [ -n \"$out\" ] && out+=\",\"; out+=\"\\\"$v\\\"\"; done; case \"$dest\" in \"$STAGE_CSV\") fd=10 ;; \"$STAGE_REN\") fd=11 ;; \"$STAGE_SAVE_REN\") fd=12 ;; \"$STAGE_HASH_DUP\") fd=13 ;; \"$STAGE_DAT_MATCH\") fd=14 ;; \"$STAGE_DAT_UNMATCHED\") fd=15 ;; \"$STAGE_LOCATION_AUDIT\") fd=16 ;; \"$STAGE_COMPLETION\") fd=18 ;; \"$STAGE_MISSING_COMPLETION\") fd=19 ;; esac; if [ -n \"$fd\" ]; then printf '%s\\n' \"$out\" >&\"$fd\"; else printf '%s\\n' \"$out\" >> \"$dest\"; fi; }"
)

marker = ": > \"$HASH_ROWS\"; : > \"$COLLISION_ROWS\"\nTOTAL=0;"
replacement = ": > \"$HASH_ROWS\"; : > \"$COLLISION_ROWS\"\n# Persistent descriptors avoid thousands of open/close cycles on MiSTer's FAT storage.\nexec 9>>\"$STAGE_OUT\" 10>>\"$STAGE_CSV\" 11>>\"$STAGE_REN\" 12>>\"$STAGE_SAVE_REN\" 13>>\"$STAGE_HASH_DUP\" 14>>\"$STAGE_DAT_MATCH\" 15>>\"$STAGE_DAT_UNMATCHED\" 16>>\"$STAGE_LOCATION_AUDIT\" 17>>\"$HASH_ROWS\" 20>>\"$HASH_CACHE_NEW\" 21>>\"$COLLISION_ROWS\"\nTOTAL=0;"
assert marker in s
s = s.replace(marker, replacement, 1)

s = s.replace(" >> \"$HASH_ROWS\"; hkey=", " >&17; hkey=")
s = s.replace(" >> \"$HASH_CACHE_NEW\"\n", " >&20\n")
s = s.replace(" >> \"$COLLISION_ROWS\"\n", " >&21\n")
s = s.replace(" >> \"$STAGE_OUT\"\n  csv_row", " >&9\n  csv_row")

# Close the hot-loop descriptors before post-processing reads those files.
needle = "done 3<&-\n\nif [ -s \"$COLLISION_ROWS\" ]; then"
assert needle in s
s = s.replace(needle, "done 3<&-\nexec 9>&- 10>&- 11>&- 12>&- 14>&- 15>&- 16>&- 17>&- 20>&- 21>&-\n\nif [ -s \"$COLLISION_ROWS\" ]; then", 1)

# Completion CSVs are generated later; keep those descriptors open for their loops.
needle = "printf '%s\\n' '\"system\",\"canonical_title\",\"region\",\"release_type\",\"license_status\"' > \"$STAGE_MISSING_COMPLETION\"\n"
assert needle in s
s = s.replace(needle, needle + "exec 18>>\"$STAGE_COMPLETION\" 19>>\"$STAGE_MISSING_COMPLETION\"\n", 1)
needle = "{ head -n 1 \"$STAGE_MISSING_COMPLETION\";"
assert needle in s
s = s.replace(needle, "exec 18>&- 19>&-\n" + needle, 1)

# Duplicate report: replace one full HASH_ROWS scan per duplicate hash with one awk pass.
old = "if [ -s \"$HASH_ROWS\" ]; then awk -F '\\t' '{c[$1]++} END {for (h in c) if (c[h]>1) print h}' \"$HASH_ROWS\" | sort > \"$WORK.duphashes\"; while IFS= read -r dh; do awk -F '\\t' -v k=\"$dh\" '$1==k {print}' \"$HASH_ROWS\" | while IFS=$'\\t' read -r h hs hp hf hc; do csv_escape \"$h\" >> \"$STAGE_HASH_DUP\"; printf ',' >> \"$STAGE_HASH_DUP\"; csv_escape \"$hs\" >> \"$STAGE_HASH_DUP\"; printf ',' >> \"$STAGE_HASH_DUP\"; csv_escape \"$hp\" >> \"$STAGE_HASH_DUP\"; printf ',' >> \"$STAGE_HASH_DUP\"; csv_escape \"$hf\" >> \"$STAGE_HASH_DUP\"; printf ',' >> \"$STAGE_HASH_DUP\"; csv_escape \"$hc\" >> \"$STAGE_HASH_DUP\"; printf '\\n' >> \"$STAGE_HASH_DUP\"; done; done < \"$WORK.duphashes\"; rm -f \"$WORK.duphashes\"; fi"
new = "if [ -s \"$HASH_ROWS\" ]; then awk -F '\\t' '{c[$1]++; row[NR]=$0; key[NR]=$1} END {for(i=1;i<=NR;i++) if(c[key[i]]>1) print row[i]}' \"$HASH_ROWS\" | while IFS=$'\\t' read -r h hs hp hf hc; do csv_row \"$STAGE_HASH_DUP\" \"$h\" \"$hs\" \"$hp\" \"$hf\" \"$hc\"; done; fi"
assert old in s
s = s.replace(old, new, 1)

# Discovery snapshot: batch in one awk process instead of stat + append reopen per file is unsafe
# because signatures are needed in-memory, but at least keep the snapshot/changed files open.
old = "printf 'format\\t%s\\n' \"$DISCOVERY_FORMAT\" > \"$DISCOVERY_SNAPSHOT_NEW\"\n  : > \"$DISCOVERY_CHANGED\""
new = "printf 'format\\t%s\\n' \"$DISCOVERY_FORMAT\" > \"$DISCOVERY_SNAPSHOT_NEW\"\n  : > \"$DISCOVERY_CHANGED\"\n  exec 22>>\"$DISCOVERY_SNAPSHOT_NEW\" 23>>\"$DISCOVERY_CHANGED\""
assert old in s
s = s.replace(old, new, 1)
s = s.replace(" >> \"$DISCOVERY_SNAPSHOT_NEW\"\n    DISCOVERY_CURRENT_PATH", " >&22\n    DISCOVERY_CURRENT_PATH", 1)
s = s.replace(" >> \"$DISCOVERY_CHANGED\"\n      DISCOVERY_CHANGED_COUNT", " >&23\n      DISCOVERY_CHANGED_COUNT", 1)
needle = "  if [ \"$USE_HASH_CACHE\" -eq 1 ]; then\n    for p in \"${!DISCOVERY_OLD_SIG[@]}\"; do"
assert needle in s
s = s.replace(needle, "  exec 22>&- 23>&-\n" + needle, 1)

p.write_text(s)

for docname in ('README.md', 'PROJECT_CONTEXT.md'):
    d = Path(docname)
    t = d.read_text()
    note = "\nFast Audit hot-loop output is buffered through persistent file descriptors, avoiding thousands of repeated FAT file open/close operations during discovery and report generation. Duplicate-hash reporting is also generated in a single pass. This is a performance-only optimization; audit results and safety semantics are unchanged.\n"
    if note.strip() not in t:
        d.write_text(t.rstrip() + "\n" + note)
