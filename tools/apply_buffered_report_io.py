#!/usr/bin/env python3
from pathlib import Path

p = Path('Export_Game_Library.sh')
s = p.read_text()

# Do not rewrite csv_row's quote-escaping logic. Instead, keep that proven helper
# intact and optimize the high-volume append paths directly with persistent FDs.
marker = ': > "$HASH_ROWS"; : > "$COLLISION_ROWS"\nTOTAL=0;'
assert marker in s
s = s.replace(marker, ': > "$HASH_ROWS"; : > "$COLLISION_ROWS"\n# Keep hot append targets open during the per-ROM loop to reduce FAT open/close I/O.\nexec 17>>"$HASH_ROWS" 20>>"$HASH_CACHE_NEW" 21>>"$COLLISION_ROWS"\nTOTAL=0;', 1)
s = s.replace(' >> "$HASH_ROWS"; hkey=', ' >&17; hkey=', 1)
s = s.replace(' >> "$HASH_CACHE_NEW"\n', ' >&20\n', 1)
s = s.replace(' >> "$COLLISION_ROWS"\n', ' >&21\n', 1)

# Close before collision/duplicate post-processing reads these files.
needle = 'done\nexec 3<&-\n\n# Issue #7: evaluate both pre-DAT groups and duplicate final targets.'
assert needle in s
s = s.replace(needle, 'done\nexec 3<&-\nexec 17>&- 20>&- 21>&-\n\n# Issue #7: evaluate both pre-DAT groups and duplicate final targets.', 1)

# Discovery snapshot writes are another hot append path on FAT storage.
old = '  : > "$DISCOVERY_CHANGED"\n  while IFS= read -r p; do'
assert old in s
s = s.replace(old, '  : > "$DISCOVERY_CHANGED"\n  exec 22>>"$DISCOVERY_SNAPSHOT_NEW" 23>>"$DISCOVERY_CHANGED"\n  while IFS= read -r p; do', 1)
s = s.replace(' >> "$DISCOVERY_SNAPSHOT_NEW"\n    DISCOVERY_CURRENT_PATH', ' >&22\n    DISCOVERY_CURRENT_PATH', 1)
s = s.replace(' >> "$DISCOVERY_CHANGED"\n      DISCOVERY_CHANGED_COUNT', ' >&23\n      DISCOVERY_CHANGED_COUNT', 1)
needle = '  done < "$GAME_LIST"\n  if [ "$USE_HASH_CACHE" -eq 1 ]; then'
assert needle in s
s = s.replace(needle, '  done < "$GAME_LIST"\n  exec 22>&- 23>&-\n  if [ "$USE_HASH_CACHE" -eq 1 ]; then', 1)

p.write_text(s)

note = 'Fast Audit hot-loop cache and discovery output uses persistent file descriptors, avoiding repeated FAT file open/close operations. This is a performance-only optimization; audit results and safety semantics are unchanged.'
for name in ('README.md', 'PROJECT_CONTEXT.md'):
    d = Path(name)
    t = d.read_text()
    if note not in t:
        d.write_text(t.rstrip() + '\n\n' + note + '\n')
