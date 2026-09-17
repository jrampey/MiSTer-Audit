#!/usr/bin/env python3
from pathlib import Path
import re

p = Path('Export_Game_Library.sh')
s = p.read_text()

new_csv = '''csv_row() { local dest="$1" out="" v fd=""; shift; for v in "$@"; do v="${v//\"/\"\"}"; [ -n "$out" ] && out+=","; out+="\\\"$v\\\""; done; case "$dest" in "$STAGE_CSV") fd=10 ;; "$STAGE_REN") fd=11 ;; "$STAGE_SAVE_REN") fd=12 ;; "$STAGE_DAT_MATCH") fd=14 ;; "$STAGE_DAT_UNMATCHED") fd=15 ;; "$STAGE_LOCATION_AUDIT") fd=16 ;; esac; if [ -n "$fd" ]; then printf '%s\\n' "$out" >&"$fd"; else printf '%s\\n' "$out" >> "$dest"; fi; }'''
s, n = re.subn(r'^csv_row\(\) \{.*$', lambda m: new_csv, s, count=1, flags=re.M)
if n != 1: raise SystemExit('csv_row anchor not found')

s, n = re.subn(r'(: > "\$HASH_ROWS"; : > "\$COLLISION_ROWS"\n)', r'\1# Keep hot report files open during the per-ROM loop to avoid repeated FAT open/close I/O.\nexec 9>>"$STAGE_OUT" 10>>"$STAGE_CSV" 11>>"$STAGE_REN" 12>>"$STAGE_SAVE_REN" 14>>"$STAGE_DAT_MATCH" 15>>"$STAGE_DAT_UNMATCHED" 16>>"$STAGE_LOCATION_AUDIT" 17>>"$HASH_ROWS" 20>>"$HASH_CACHE_NEW" 21>>"$COLLISION_ROWS"\n', s, count=1)
if n != 1: raise SystemExit('report-open anchor not found')

for old,new in [
(' >> "$HASH_ROWS"; hkey=',' >&17; hkey='),
(' >> "$HASH_CACHE_NEW"\n',' >&20\n'),
(' >> "$COLLISION_ROWS"\n',' >&21\n'),
(' >> "$STAGE_OUT"\n  csv_row',' >&9\n  csv_row')]:
    s=s.replace(old,new,1)

s, n = re.subn(r'(done\nexec 3<&-\n)', r'\1exec 9>&- 10>&- 11>&- 12>&- 14>&- 15>&- 16>&- 17>&- 20>&- 21>&-\n', s, count=1)
if n != 1: raise SystemExit('report-close anchor not found')

s, n = re.subn(r'(  : > "\$DISCOVERY_CHANGED"\n)', r'\1  exec 22>>"$DISCOVERY_SNAPSHOT_NEW" 23>>"$DISCOVERY_CHANGED"\n', s, count=1)
if n != 1: raise SystemExit('discovery-open anchor not found')
s=s.replace(' >> "$DISCOVERY_SNAPSHOT_NEW"\n    DISCOVERY_CURRENT_PATH',' >&22\n    DISCOVERY_CURRENT_PATH',1)
s=s.replace(' >> "$DISCOVERY_CHANGED"\n      DISCOVERY_CHANGED_COUNT',' >&23\n      DISCOVERY_CHANGED_COUNT',1)
s, n = re.subn(r'(  done < "\$GAME_LIST"\n)(  if \[ "\$USE_HASH_CACHE" -eq 1 \]; then)', r'\1  exec 22>&- 23>&-\n\2', s, count=1)
if n != 1: raise SystemExit('discovery-close anchor not found')

required=['exec 9>>"$STAGE_OUT"','printf \'%s\\n\' "$out" >&"$fd"','exec 22>>"$DISCOVERY_SNAPSHOT_NEW"','exec 9>&- 10>&-']
for token in required:
    if token not in s: raise SystemExit('missing generated token: '+token)
p.write_text(s)

note='Fast Audit hot-loop output is buffered through persistent file descriptors, avoiding thousands of repeated FAT file open/close operations during discovery and report generation. This is a performance-only optimization; audit results and safety semantics are unchanged.'
for name in ('README.md','PROJECT_CONTEXT.md'):
    d=Path(name); t=d.read_text()
    if note not in t: d.write_text(t.rstrip()+'\n\n'+note+'\n')
