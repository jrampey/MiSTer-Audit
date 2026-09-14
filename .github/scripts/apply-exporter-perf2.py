from pathlib import Path
p=Path('Export_Game_Library.sh')
s=p.read_text()
# Cache format changes because normalized hash is now persisted.
s=s.replace('CACHE_FORMAT="4"','CACHE_FORMAT="5"')
# Avoid hashing the 11MB DB merely for cache invalidation.
s=s.replace('HASH_DB_SOURCE="mister_hash_database.tsv"; HASH_DB_FINGERPRINT="$(hash_file "$HASH_DB_TSV")"','HASH_DB_SOURCE="mister_hash_database.tsv"; HASH_DB_FINGERPRINT="$(file_signature "$HASH_DB_TSV")"')
# Extend cache with normalized hash.
s=s.replace('declare -A CACHE_SHA CACHE_DAT_STATUS CACHE_DAT_NAME CACHE_DAT_ROM CACHE_DAT_SOURCE','declare -A CACHE_SHA CACHE_NORMALIZED_SHA CACHE_DAT_STATUS CACHE_DAT_NAME CACHE_DAT_ROM CACHE_DAT_SOURCE')
s=s.replace('local old_format="" old_db="" p sig sha ds dn dr dsrc k','local old_format="" old_db="" p sig sha normalized_sha ds dn dr dsrc k')
s=s.replace("while IFS=$'\\t' read -r p sig sha ds dn dr dsrc; do [ \"$p\" = \"path\" ] && continue; k=\"$p|$sig\"; CACHE_SHA[\"$k\"]=\"$sha\"; CACHE_ENTRIES_LOADED=$((CACHE_ENTRIES_LOADED+1));", "while IFS=$'\\t' read -r p sig sha normalized_sha ds dn dr dsrc; do [ \"$p\" = \"path\" ] && continue; k=\"$p|$sig\"; CACHE_SHA[\"$k\"]=\"$sha\"; CACHE_NORMALIZED_SHA[\"$k\"]=\"$normalized_sha\"; CACHE_ENTRIES_LOADED=$((CACHE_ENTRIES_LOADED+1));")
s=s.replace("printf 'path\\tsignature\\tsha1\\tdat_status\\tdat_name\\tdat_rom\\tdat_source\\n' > \"$HASH_CACHE_NEW\"", "printf 'path\\tsignature\\tsha1\\tnormalized_sha1\\tdat_status\\tdat_name\\tdat_rom\\tdat_source\\n' > \"$HASH_CACHE_NEW\"")
# Use cached normalized hash when available; otherwise compute once and persist.
s=s.replace('hkey="${sha1,,}"; matched_hkey="$(normalized_dat_hash "$p" "$ext" "$hkey" "$file_size")";', 'hkey="${sha1,,}"; matched_hkey="${CACHE_NORMALIZED_SHA[$cache_key]:-}"; [ -n "$matched_hkey" ] || matched_hkey="$(normalized_dat_hash "$p" "$ext" "$hkey" "$file_size")";')
s=s.replace("printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' \"$p\" \"$sig\" \"${sha1,,}\" \"$dat_status\" \"$dat_name\" \"$dat_rom\" \"$dat_source\" >> \"$HASH_CACHE_NEW\"", "printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' \"$p\" \"$sig\" \"${sha1,,}\" \"${matched_hkey:-${sha1,,}}\" \"$dat_status\" \"$dat_name\" \"$dat_rom\" \"$dat_source\" >> \"$HASH_CACHE_NEW\"")
# Replace awk in hash_stream_skip with shell parsing, avoiding one process per normalization.
s=s.replace("dd if=\"$p\" bs=\"$block\" skip=1 2>/dev/null | sha1sum 2>/dev/null | awk '{print $1}'", "local digest rest; read -r digest rest < <(dd if=\"$p\" bs=\"$block\" skip=1 2>/dev/null | sha1sum 2>/dev/null); printf '%s' \"$digest\"")
s=s.replace("dd if=\"$p\" bs=\"$block\" skip=1 2>/dev/null | openssl sha1 2>/dev/null | awk '{print $NF}'", "local line digest; IFS= read -r line < <(dd if=\"$p\" bs=\"$block\" skip=1 2>/dev/null | openssl sha1 2>/dev/null); digest=\"${line##* }\"; printf '%s' \"$digest\"")
p.write_text(s)
