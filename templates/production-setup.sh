#!/bin/bash

###############################################################################
# Drupal 11 Production First-Time Setup Script
#
# This script performs the initial setup of a Drupal 11 production instance
# after cloning the repository. It configures settings.php, installs
# dependencies, and runs the Drupal installer.
#
# Usage: bash setup.sh
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SETTINGS_DIR="web/sites/default"
SETTINGS_FILE="$SETTINGS_DIR/settings.php"
DEFAULT_SETTINGS_FILE="$SETTINGS_DIR/default.settings.php"

echo "=========================================="
echo "Drupal 11 Production First-Time Setup"
echo "=========================================="

# ─────────────────────────────────────────────
# Step 1: Create settings.php
# ─────────────────────────────────────────────
echo ""
echo "[1/8] Creating settings.php..."
echo "-------------------------------------------"

if [ -f "$SETTINGS_FILE" ]; then
    echo "ERROR: $SETTINGS_FILE already exists."
    echo "This script is intended for first-time setup only."
    echo "If you want to re-run it, remove settings.php first:"
    echo "  rm $SETTINGS_FILE"
    exit 1
fi

if [ ! -f "$DEFAULT_SETTINGS_FILE" ]; then
    echo "ERROR: $DEFAULT_SETTINGS_FILE not found."
    echo "Make sure you are running this script from the project root."
    exit 1
fi

cp "$DEFAULT_SETTINGS_FILE" "$SETTINGS_FILE"
echo "Created $SETTINGS_FILE"

# ─────────────────────────────────────────────
# Step 2: Configure database credentials
# ─────────────────────────────────────────────
echo ""
echo "[2/8] Configuring database credentials..."
echo "-------------------------------------------"

read -p "Database name: " DB_NAME
read -p "Database username: " DB_USER
read -sp "Database password: " DB_PASS
echo ""
read -p "Database host [localhost]: " DB_HOST
DB_HOST="${DB_HOST:-localhost}"
read -p "Database port [3306]: " DB_PORT
DB_PORT="${DB_PORT:-3306}"
read -p "Database driver [mysql]: " DB_DRIVER
DB_DRIVER="${DB_DRIVER:-mysql}"

# Escape single quotes for safe embedding in PHP strings
DB_NAME_ESC="${DB_NAME//\'/\\\'}"
DB_USER_ESC="${DB_USER//\'/\\\'}"
DB_PASS_ESC="${DB_PASS//\'/\\\'}"
DB_HOST_ESC="${DB_HOST//\'/\\\'}"

DB_BLOCK=$(cat <<PHPEOF
\$databases['default']['default'] = [
  'database' => '${DB_NAME_ESC}',
  'username' => '${DB_USER_ESC}',
  'password' => '${DB_PASS_ESC}',
  'host' => '${DB_HOST_ESC}',
  'port' => '${DB_PORT}',
  'driver' => '${DB_DRIVER}',
  'prefix' => '',
  'collation' => 'utf8mb4_general_ci',
];
PHPEOF
)

# Replace the empty $databases = []; with the full config block
php -r "
\$file = file_get_contents('$SETTINGS_FILE');
\$replacement = <<<'REPLACEMENT'
${DB_BLOCK}
REPLACEMENT;
\$file = str_replace('\$databases = [];', \$replacement, \$file);
file_put_contents('$SETTINGS_FILE', \$file);
"

echo "Database credentials configured."

# ─────────────────────────────────────────────
# Step 3: Set hash_salt
# ─────────────────────────────────────────────
echo ""
echo "[3/8] Generating hash_salt..."
echo "-------------------------------------------"

HASH_SALT=$(php -r "echo bin2hex(random_bytes(32));")

php -r "
\$file = file_get_contents('$SETTINGS_FILE');
\$file = str_replace(\"\\\$settings['hash_salt'] = '';\", \"\\\$settings['hash_salt'] = '${HASH_SALT}';\", \$file);
file_put_contents('$SETTINGS_FILE', \$file);
"

echo "hash_salt set."

# ─────────────────────────────────────────────
# Step 4: Set config_sync_directory
# ─────────────────────────────────────────────
echo ""
echo "[4/9] Setting config_sync_directory..."
echo "-------------------------------------------"

sed -i.bak "s|^# \$settings\['config_sync_directory'\] = '/directory/outside/webroot';|\$settings['config_sync_directory'] = '../config/sync';|" "$SETTINGS_FILE"
rm -f "${SETTINGS_FILE}.bak"

echo "config_sync_directory set to '../config/sync'."

# ─────────────────────────────────────────────
# Step 5: Set trusted_host_patterns
# ─────────────────────────────────────────────
echo ""
echo "[5/9] Setting trusted_host_patterns..."
echo "-------------------------------------------"

read -p "Production domain (e.g. example.com): " PROD_HOST

# Escape dots for use as a regex pattern
PROD_HOST_ESCAPED="${PROD_HOST//./\\.}"

cat >> "$SETTINGS_FILE" <<PHPEOF

\$settings['trusted_host_patterns'] = [
  '^${PROD_HOST_ESCAPED}\$',
];
PHPEOF

echo "trusted_host_patterns set to '^${PROD_HOST_ESCAPED}\$'."

# ─────────────────────────────────────────────
# Step 6: Install Composer dependencies
# ─────────────────────────────────────────────
echo ""
echo "[6/9] Installing Composer dependencies..."
echo "-------------------------------------------"

composer install --no-dev --optimize-autoloader --no-interaction

# ─────────────────────────────────────────────
# Step 7: Install Drupal
# ─────────────────────────────────────────────
echo ""
echo "[7/9] Installing Drupal (existing config)..."
echo "-------------------------------------------"

drush site:install --existing-config -y

# ─────────────────────────────────────────────
# Step 8: Verify installation
# ─────────────────────────────────────────────
echo ""
echo "[8/9] Verifying installation..."
echo "-------------------------------------------"

drush status

# ─────────────────────────────────────────────
# Step 9: Generate one-time login link
# ─────────────────────────────────────────────
echo ""
echo "[9/9] Generating one-time login link..."
echo "-------------------------------------------"

drush uli

echo ""
echo "=========================================="
echo "Setup completed successfully!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  - Use the login link above to access the admin panel"
echo "  - Verify the site is working correctly"
echo ""
