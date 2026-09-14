from pathlib import Path
p=Path('Export_Game_Library.sh')
s=p.read_text()
def rep(a,b):
    global s
    if a not in s: raise SystemExit('pattern missing: '+a[:120])
    s=s.replace(a,b,1)

# Add in-process setters used by hot loops. Existing output functions remain for compatibility.
anchor="suffix_for() { local region=\"$1\" kind=\"$2\" suffix=\"\"; [ \"$region\" != \"USA\" ] && [ \"$region\" != \"Unknown\" ] && suffix=\" [$region]\"; [ \"$region\" = \"Unknown\" ] && suffix=\" [Unknown Region]\"; [ \"$kind\" != \"Retail/Standard\" ] && suffix=\"$suffix [$kind]\"; printf '%s' \"$suffix\"; }\n"
insert=anchor+r'''region_of_set() { local s="${1,,}"; if [[ "$s" =~ \((usa|us|u)(,|\)|[[:space:]]) ]] || [[ "$s" =~ \((ue|u,e|u\+e)\) ]]; then HOT_RESULT=USA; elif [[ "$s" =~ \((world|w)\) ]]; then HOT_RESULT=World; elif [[ "$s" =~ \((europe|eur|e)\) ]]; then HOT_RESULT=Europe; elif [[ "$s" =~ \((japan|jpn|j)\) ]]; then HOT_RESULT=Japan; elif [[ "$s" =~ \((canada|can)\) ]]; then HOT_RESULT=Canada; elif [[ "$s" =~ \((australia|aus)\) ]]; then HOT_RESULT=Australia; elif [[ "$s" =~ \((korea|kor|k)\) ]]; then HOT_RESULT=Korea; elif [[ "$s" =~ \((brazil|bra|b)\) ]]; then HOT_RESULT=Brazil; else HOT_RESULT=Unknown; fi; }
kind_of_set() { local s="${1,,}"; if [[ "$s" =~ \((proto|prototype|beta|demo|sample)([^a-z]|$) ]] || [[ "$s" =~ \[(proto|prototype|beta|demo|sample)([^a-z]|$) ]]; then HOT_RESULT='Prototype/Beta/Demo'; elif [[ "$s" =~ \((rev|revision)[[:space:]._-]*[0-9a-z]+\) ]] || [[ "$s" =~ \[(rev|revision)[[:space:]._-]*[0-9a-z]+\] ]]; then HOT_RESULT=Revision; elif [[ "$s" =~ \((unl|unlicensed|homebrew|aftermarket)\) ]] || [[ "$s" =~ \[(unl|unlicensed|homebrew|aftermarket)\] ]] || [[ "$s" == *" homebrew "* ]] || [[ "$s" == *" aftermarket "* ]]; then HOT_RESULT='Homebrew/Unlicensed'; elif [[ "$s" =~ \[t[^]]*\] ]] || [[ "$s" == *"(translation"* ]] || [[ "$s" == *"(translated"* ]] || [[ "$s" == *"(eng)"* ]] || [[ "$s" == *"(english"* ]] || [[ "$s" == *"translation"* ]] || [[ "$s" == *"english patched"* ]]; then HOT_RESULT=Translation; elif [[ "$s" =~ \[h[^]]*\] ]] || [[ "$s" == *"(hack"* ]] || [[ "$s" == *"(hacked"* ]] || [[ "$s" == *"(improvement"* ]] || [[ "$s" == *"(redux"* ]] || [[ "$s" == *"(randomizer"* ]] || [[ "$s" == *" hack "* ]] || [[ "$s" == *" improvement "* ]] || [[ "$s" == *" randomizer "* ]]; then HOT_RESULT='Hack/Modified'; else HOT_RESULT='Retail/Standard'; fi; }
trim_set() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; HOT_RESULT="$s"; }
clean_title_set() { local s="$1" original="$1" before; local re_region='^(.*)[[:space:]]+\((USA|US|U|World|W|Europe|EUR|E|Japan|JPN|J|Canada|CAN|Australia|AUS|Korea|KOR|Brazil|BRA|UE|U,E|U\+E)\)(.*)$'; local re_meta='^(.*)[[:space:]]+\((Rev(ision)?[[:space:]._-]*[0-9A-Za-z]+|Proto(type)?|Beta|Demo|Sample|Unl(icensed)?|Homebrew|Aftermarket|Translation|Translated|Eng(lish)?[^)]*)\)(.*)$'; local re_bracket='^(.*)[[:space:]]+\[([tThH][^]]*|!|[bBoOfFpPaA][0-9]*|[cCxX])\](.*)$'; while :; do before="$s"; if [[ "$s" =~ $re_region ]]; then s="${BASH_REMATCH[1]}${BASH_REMATCH[3]}"; elif [[ "$s" =~ $re_meta ]]; then s="${BASH_REMATCH[1]}${BASH_REMATCH[7]}"; elif [[ "$s" =~ $re_bracket ]]; then s="${BASH_REMATCH[1]}${BASH_REMATCH[3]}"; else break; fi; done; trim_set "$s"; s="$HOT_RESULT"; while [[ "$s" == *"  "* ]]; do s="${s//  / }"; done; s="${s% -}"; s="${s% _}"; trim_set "$s"; s="$HOT_RESULT"; [ -z "$s" ] && s="$original"; HOT_RESULT="$s"; }
suffix_for_set() { local region="$1" kind="$2" suffix=""; [ "$region" != "USA" ] && [ "$region" != "Unknown" ] && suffix=" [$region]"; [ "$region" = "Unknown" ] && suffix=" [Unknown Region]"; [ "$kind" != "Retail/Standard" ] && suffix="$suffix [$kind]"; HOT_RESULT="$suffix"; }
location_status_set() { local current="${1,,}" expected="${2,,}"; if [ -z "$expected" ]; then HOT_RESULT=Unknown; return; fi; if [ "$current" = "$expected" ]; then HOT_RESULT=OK; return; fi; case "$expected" in nes) case "$current" in nes|fds|famicom) HOT_RESULT='OK (compatible folder)'; return;; esac ;; gameboy) case "$current" in gameboy|game\ boy|gb) HOT_RESULT='OK (compatible folder)'; return;; esac ;; n64) case "$current" in n64|nintendo64|nintendo\ 64) HOT_RESULT='OK (compatible folder)'; return;; esac ;; esac; HOT_RESULT=MISFILED; }
'''
rep(anchor,insert)

# Classification misses no longer spawn subshells for pure Bash metadata parsing.
rep('region="$(region_of "$stem")"; kind="$(kind_of "$stem")"; clean="$(clean_title "$stem")"; suffix="$(suffix_for "$region" "$kind")"; proposed="$clean$suffix.$ext"; CLASS_CACHE_MISSES=$((CLASS_CACHE_MISSES+1))', 'region_of_set "$stem"; region="$HOT_RESULT"; kind_of_set "$stem"; kind="$HOT_RESULT"; clean_title_set "$stem"; clean="$HOT_RESULT"; suffix_for_set "$region" "$kind"; suffix="$HOT_RESULT"; proposed="$clean$suffix.$ext"; CLASS_CACHE_MISSES=$((CLASS_CACHE_MISSES+1))')

# Report loop uses carried fallback proposal and in-process canonical metadata transforms.
rep('proposed="${fallback_proposed:-}"; if [ -z "$proposed" ]; then suffix="$(suffix_for "$region" "$kind")"; proposed="$clean$suffix.$ext"; fi; base="${proposed%.$ext}";', 'proposed="${fallback_proposed:-}"; if [ -z "$proposed" ]; then suffix_for_set "$region" "$kind"; suffix="$HOT_RESULT"; proposed="$clean$suffix.$ext"; fi; base="${proposed%.$ext}";')
rep('[ -n "$canonical_stem" ] && clean="$(clean_title "$canonical_stem")";', '[ -n "$canonical_stem" ] && { clean_title_set "$canonical_stem"; clean="$HOT_RESULT"; };')
rep('proposed="$clean$(suffix_for "$region" "$kind").$ext";', 'suffix_for_set "$region" "$kind"; proposed="$clean$HOT_RESULT.$ext";')
rep('loc_status="$(location_status "$system" "$meta_folder")";', 'location_status_set "$system" "$meta_folder"; loc_status="$HOT_RESULT";')

# Portable derived-cache cleanup; avoid find -delete on MiSTer/BusyBox variants.
rep("  find \"$DAT_CACHE_DIR\" -maxdepth 1 -type f -name '*.tsv' -delete 2>/dev/null || true", "  local old_cache\n  for old_cache in \"$DAT_CACHE_DIR\"/*.tsv; do [ -f \"$old_cache\" ] && rm -f \"$old_cache\"; done")

assert 'Export_Game_Library_v1.3.sh' in s
assert 'FULL_VERIFY_WORKERS=2' in s
assert "find \"$DAT_CACHE_DIR\" -maxdepth 1 -type f -name '*.tsv' -delete" not in s
p.write_text(s)
