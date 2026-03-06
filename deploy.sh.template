#!/bin/bash

###############################################################################
# Drupal 11 Production Deployment Script
#
# This script handles the full deployment pipeline for the Drupal 11 project
# with Tailwind CSS theme.
###############################################################################

set -e  # Exit on any error

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Trap to ensure maintenance mode is disabled on script exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo "=========================================="
        echo "ERROR: Deployment failed!"
        echo "Attempting to disable maintenance mode..."
        echo "=========================================="
        drush state:set system.maintenance_mode 0 2>/dev/null || true
    fi
    exit $exit_code
}
trap cleanup EXIT

echo "=========================================="
echo "Starting Drupal 11 Deployment Pipeline"
echo "=========================================="

echo ""
echo "[1/8] Pulling latest code from Git..."
echo "-------------------------------------------"
git pull

echo ""
echo "[2/8] Installing Composer dependencies..."
echo "-------------------------------------------"
composer install --no-dev --optimize-autoloader --no-interaction

# [Optional on standard hosting - START] Auto-applies noexec workaround if vendor/bin/drush can't run directly.
# Safe to remove if `vendor/bin/drush --version` works on your server without issues.
if ! "$SCRIPT_DIR/vendor/bin/drush" --version >/dev/null 2>&1; then
    source "$SCRIPT_DIR/drush-noexec-workaround.sh"
    if declare -f setup_drush_vendor_symlink >/dev/null 2>&1; then
        setup_drush_vendor_symlink
    fi
fi
# [Optional on standard hosting - END]

echo ""
echo "[3/8] Enabling maintenance mode..."
echo "-------------------------------------------"
drush state:set system.maintenance_mode 1

echo ""
echo "[4/8] Building Tailwind CSS theme assets..."
echo "-------------------------------------------"
echo "Installing dependencies with --production=false to include devDependencies..."
echo "Note: Tailwind CSS is in devDependencies as a build tool - needed to compile CSS, not at runtime"
cd web/themes/custom/tailwind
yarn install --frozen-lockfile --production=false
yarn build
cd "$SCRIPT_DIR"

echo ""
echo "[5/8] Importing configuration..."
echo "-------------------------------------------"
set +e  # Temporarily disable exit on error to handle field type change edge case
drush config:import -y
CONFIG_IMPORT_EXIT=$?
set -e  # Re-enable exit on error

if [ $CONFIG_IMPORT_EXIT -ne 0 ]; then
  echo ""
  echo "Config import failed (likely due to field type changes)."
  echo "Running database updates to handle field migrations..."
  echo "-------------------------------------------"
  drush updatedb -y

  echo ""
  echo "Re-running config import after field cleanup..."
  echo "-------------------------------------------"
  drush config:import -y
else
  echo ""
  echo "[6/8] Running database updates..."
  echo "-------------------------------------------"
  drush updatedb -y
fi

echo ""
echo "[7/8] Rebuilding cache..."
echo "-------------------------------------------"
drush cache:rebuild

echo ""
echo "[8/8] Disabling maintenance mode..."
echo "-------------------------------------------"
drush state:set system.maintenance_mode 0

echo ""
echo "Verifying deployment..."
echo "-------------------------------------------"
drush status

echo ""
echo "=========================================="
echo "Deployment completed successfully!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  - Verify the site is working correctly"
echo "  - Check for any errors in logs"
echo "  - Test critical functionality"
echo ""
