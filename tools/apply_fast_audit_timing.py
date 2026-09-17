from pathlib import Path

p = Path('Export_Game_Library.sh')
s = p.read_text()

old = '''PUBLISH_END=$(date +%s); TOTAL_END=$PUBLISH_END; sync
echo; echo "+--------------------------------------------------+"; echo "| AUDIT COMPLETE                                   |"; echo "+--------------------------------------------------+"; echo " Mode              : $AUDIT_MODE"; echo " Games cataloged   : $TOTAL"; echo " DAT matches       : $DAT_MATCHED / $HASHED"; echo " Blocking collisions: $COLLISIONS"; echo " DAT variants safe : $RESOLVED_COLLISIONS"; echo " Save matches      : $SAVE_MATCHES"; echo " Fast delta        : new=$DISCOVERY_ADDED modified=$((DISCOVERY_CHANGED_COUNT-DISCOVERY_ADDED)) deleted=$DISCOVERY_REMOVED"; echo " Cache hit rate    : $CACHE_HIT_RATE%"; echo " Integrity         : $AUDIT_VERDICT"; echo " Apply             : $APPLY_RECOMMENDATION"; echo "----------------------------------------------------"; echo " Reports: $AUDIT"; echo " Review : MiSTer_Library_Audit.txt"; echo " Missing: missing_library_titles.csv"; echo "----------------------------------------------------"; echo " READ ONLY: no ROMs or saves were changed."; echo "----------------------------------------------------"; echo; echo "Press Enter to close, or wait 60 seconds."; read -t 60 -r _ || true'''

new = '''PUBLISH_END=$(date +%s); TOTAL_END=$PUBLISH_END; sync
DISCOVERY_SECONDS=$((DISCOVERY_END-DISCOVERY_START))
SAVE_INDEX_SECONDS=$((SAVE_END-SAVE_START))
DATABASE_CACHE_SECONDS=$((DB_END-DB_START))
CLASSIFICATION_SECONDS=$((CLASSIFY_END-CLASSIFY_START))
REPORT_PROCESSING_SECONDS=$((REPORT_END-REPORT_START))
PUBLISH_SECONDS=$((PUBLISH_END-PUBLISH_START))
TOTAL_SECONDS=$((TOTAL_END-START_TIME))
# Final timing telemetry is appended after atomic publication so the uploaded
# audit contains the same stage timings shown on-screen. This is diagnostic
# metadata only and does not affect audit/rename decisions.
{
  echo
  echo "[FINAL TIMING]"
  echo "discovery_seconds=$DISCOVERY_SECONDS"
  echo "save_index_seconds=$SAVE_INDEX_SECONDS"
  echo "database_cache_seconds=$DATABASE_CACHE_SECONDS"
  echo "classification_seconds=$CLASSIFICATION_SECONDS"
  echo "parallel_full_verify_hash_seconds=$FULL_VERIFY_PARALLEL_SECONDS"
  echo "report_processing_seconds=$REPORT_PROCESSING_SECONDS"
  echo "publish_seconds=$PUBLISH_SECONDS"
  echo "total_seconds=$TOTAL_SECONDS"
} >> "$BUNDLE"
echo; echo "+--------------------------------------------------+"; echo "| AUDIT COMPLETE                                   |"; echo "+--------------------------------------------------+"; echo " Mode              : $AUDIT_MODE"; echo " Games cataloged   : $TOTAL"; echo " DAT matches       : $DAT_MATCHED / $HASHED"; echo " Blocking collisions: $COLLISIONS"; echo " DAT variants safe : $RESOLVED_COLLISIONS"; echo " Save matches      : $SAVE_MATCHES"; echo " Fast delta        : new=$DISCOVERY_ADDED modified=$((DISCOVERY_CHANGED_COUNT-DISCOVERY_ADDED)) deleted=$DISCOVERY_REMOVED"; echo " Cache hit rate    : $CACHE_HIT_RATE%"; echo " Integrity         : $AUDIT_VERDICT"; echo " Apply             : $APPLY_RECOMMENDATION"; echo "----------------------------------------------------"; echo " Timing (seconds)"; echo "   Discovery       : $DISCOVERY_SECONDS"; echo "   Save index      : $SAVE_INDEX_SECONDS"; echo "   Database/cache  : $DATABASE_CACHE_SECONDS"; echo "   Classification  : $CLASSIFICATION_SECONDS"; echo "   Full hash pass  : $FULL_VERIFY_PARALLEL_SECONDS"; echo "   Report processing: $REPORT_PROCESSING_SECONDS"; echo "   Publish         : $PUBLISH_SECONDS"; echo "   TOTAL           : $TOTAL_SECONDS"; echo "----------------------------------------------------"; echo " Reports: $AUDIT"; echo " Review : MiSTer_Library_Audit.txt"; echo " Missing: missing_library_titles.csv"; echo "----------------------------------------------------"; echo " READ ONLY: no ROMs or saves were changed."; echo "----------------------------------------------------"; echo; echo "Press Enter to close, or wait 60 seconds."; read -t 60 -r _ || true'''

if old not in s:
    raise SystemExit('expected exporter completion block not found')
s = s.replace(old, new, 1)
p.write_text(s)

for doc in ('README.md', 'PROJECT_CONTEXT.md'):
    q = Path(doc)
    if q.exists():
        text = q.read_text()
        note = '\n- Fast Audit performance telemetry reports stage timings for discovery, save indexing, database/cache work, classification, report processing, publication, and total runtime; Full Verification also reports its parallel hash-pass time.\n'
        if 'Fast Audit performance telemetry reports stage timings' not in text:
            q.write_text(text.rstrip() + '\n' + note)
