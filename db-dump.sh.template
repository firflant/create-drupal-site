#!/bin/bash

###############################################################################
# Database Dump Script
#
# Creates a clean, compressed database dump with a timestamped filename.
# Cache and session tables are exported as structure-only (no data) to keep
# the dump file size minimal and the import free of stale cache entries.
#
# Output file: db_YYYY-MM-DD_HH-MM-SS.sql.gz  (saved in project root)
###############################################################################

set -e  # Exit on any error

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# [Optional on standard hosting - START] Auto-applies noexec workaround if vendor/bin/drush can't run directly.
# Safe to remove if `vendor/bin/drush --version` works on your server without issues.
if ! "$SCRIPT_DIR/vendor/bin/drush" --version >/dev/null 2>&1; then
    source "$SCRIPT_DIR/drush-noexec-workaround.sh"
fi
# [Optional on standard hosting - END]

DUMP_FILE="$SCRIPT_DIR/db_$(date '+%Y-%m-%d_%H-%M-%S').sql"

echo "Clearing caches before dump..."
drush cache:rebuild

echo "Dumping database to ${DUMP_FILE}.gz ..."
drush sql:dump \
    --gzip \
    --structure-tables-list="cache,cache_*,history,sessions,watchdog" \
    --result-file="$DUMP_FILE"

echo ""
echo "Done! File saved to: ${DUMP_FILE}.gz"
