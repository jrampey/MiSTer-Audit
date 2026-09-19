from pathlib import Path

p=Path('MiSTer_Audit.sh')
s=p.read_text()
old='is_support_file() { local path="${1,,}" file="${2,,}" stem="${2%.*}"; stem="${stem,,}";'
new='is_support_file() { local path="${1,,}" file="${2,,}" stem="${2%.*}"; stem="${stem,,}"; case "$file" in readme.md|readme.txt|readme.nfo) return 0 ;; esac;'
if old not in s: raise SystemExit('support-file anchor not found')
s=s.replace(old,new,1)
old='''    else SYSTEM_UNMATCHED["$system"]=$(( ${SYSTEM_UNMATCHED["$system"]:-0} + 1 )); unmatched_class="$(expected_unmatched_class "$file" "$kind")"; csv_row "$STAGE_DAT_UNMATCHED" "$sha1" "$system" "$p" "$file" "$unmatched_class"; fi
    printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "$p" "$sig" "${sha1,,}" "${matched_hkey:-${sha1,,}}" "$dat_status" "$dat_name" "$dat_rom" "$dat_source" >> "$HASH_CACHE_NEW"
  fi

  # Record every final target so canonical duplicates are detected even when fallback names differ.
  authoritative=0; case "$dat_status" in "Exact SHA-1"|"Normalized SHA-1") [ -n "$proposed" ] && authoritative=1 ;; esac
  printf '%s\\t%s\\t%s\\t%s\\t%s\\n' "$p" "$key" "$pre_collision" "$authoritative" "${system,,}|${proposed,,}" >> "$COLLISION_ROWS"
  if [ "$pre_collision" -eq 1 ]; then if [ "$authoritative" -eq 1 ]; then collision="Canonical DAT variant candidate"; else collision="Blocking collision candidate"; fi; fi

  save_count=0; save_key="${stem,,}"
  if [ -n "${SAVES_BY_STEM[$save_key]:-}" ]; then while IFS= read -r sp; do [ -z "$sp" ] && continue; sf="${sp##*/}"; sext="${sf##*.}"; proposed_save="${proposed%.*}.$sext"; csv_row "$STAGE_SAVE_REN" "$system" "$p" "$sp" "$proposed_save" "Exact original basename" "REVIEW ONLY"; save_count=$((save_count+1)); SAVE_MATCHES=$((SAVE_MATCHES+1)); done <<< "${SAVES_BY_STEM[$save_key]}"; fi

  printf '[%s] %s | Region: %s | Type: %s | Saves: %s | File: %s | Collision: %s\\n' "$system" "$clean" "$region" "$kind" "$save_count" "$file" "$collision" >> "$STAGE_OUT"
  csv_row "$STAGE_CSV" "$system" "$clean" "$region" "$kind" "$file" "$proposed" "$p" "$save_count" "$collision" "$sha1" "$dat_status" "$dat_name" "$dat_rom" "$dat_source" "$meta_system" "$meta_core" "$meta_folder" "$meta_region" "$meta_release" "$meta_license" "$loc_status"
  csv_row "$STAGE_REN" "$system" "$p" "$proposed" "$region" "$kind" "REVIEW ONLY"'''
new='''    else SYSTEM_UNMATCHED["$system"]=$(( ${SYSTEM_UNMATCHED["$system"]:-0} + 1 )); unmatched_class="Unmatched"; csv_row "$STAGE_DAT_UNMATCHED" "$sha1" "$system" "$p" "$file" "$unmatched_class"; proposed=""; collision="Not applicable (unmatched)"; fi
    printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "$p" "$sig" "${sha1,,}" "${matched_hkey:-${sha1,,}}" "$dat_status" "$dat_name" "$dat_rom" "$dat_source" >> "$HASH_CACHE_NEW"
  fi

  # Only authoritative DAT matches participate in rename/collision planning.
  authoritative=0; case "$dat_status" in "Exact SHA-1"|"Normalized SHA-1") [ -n "$proposed" ] && authoritative=1 ;; esac
  if [ "$authoritative" -eq 1 ]; then
    printf '%s\\t%s\\t%s\\t%s\\t%s\\n' "$p" "$key" "$pre_collision" "$authoritative" "${system,,}|${proposed,,}" >> "$COLLISION_ROWS"
    if [ "$pre_collision" -eq 1 ]; then collision="Canonical DAT variant candidate"; fi
  fi

  save_count=0; save_key="${stem,,}"
  if [ "$authoritative" -eq 1 ] && [ -n "${SAVES_BY_STEM[$save_key]:-}" ]; then while IFS= read -r sp; do [ -z "$sp" ] && continue; sf="${sp##*/}"; sext="${sf##*.}"; proposed_save="${proposed%.*}.$sext"; csv_row "$STAGE_SAVE_REN" "$system" "$p" "$sp" "$proposed_save" "Exact original basename" "REVIEW ONLY"; save_count=$((save_count+1)); SAVE_MATCHES=$((SAVE_MATCHES+1)); done <<< "${SAVES_BY_STEM[$save_key]}"; fi

  printf '[%s] %s | Region: %s | Type: %s | Saves: %s | File: %s | Collision: %s\\n' "$system" "$clean" "$region" "$kind" "$save_count" "$file" "$collision" >> "$STAGE_OUT"
  csv_row "$STAGE_CSV" "$system" "$clean" "$region" "$kind" "$file" "$proposed" "$p" "$save_count" "$collision" "$sha1" "$dat_status" "$dat_name" "$dat_rom" "$dat_source" "$meta_system" "$meta_core" "$meta_folder" "$meta_region" "$meta_release" "$meta_license" "$loc_status"
  if [ "$authoritative" -eq 1 ]; then csv_row "$STAGE_REN" "$system" "$p" "$proposed" "$region" "$kind" "REVIEW ONLY"; fi'''
if old not in s: raise SystemExit('rename-policy anchor not found')
s=s.replace(old,new,1)
s=s.replace('- Exact DAT matches use canonical DAT filenames; filename parsing is fallback-only for unmatched ROMs.','- Only exact/normalized DAT matches participate in rename and save-rename planning.\n- Unmatched ROMs are inventory-only: they are reported simply as Unmatched and never receive rename targets.\n- Unmatched ROMs do not change retail library completion; completion is calculated only from canonical eligible DAT titles.')
p.write_text(s)
for doc in ['README.md','PROJECT_CONTEXT.md']:
    q=Path(doc); t=q.read_text()
    note='\n- Unmatched ROM policy: unmatched hashes are inventory-only, display simply as `Unmatched`, are excluded from ROM/save rename and collision planning, and do not affect canonical retail completion percentages.\n'
    if 'Unmatched ROM policy:' not in t: q.write_text(t.rstrip()+note)
