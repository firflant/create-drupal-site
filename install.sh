#!/usr/bin/env bash
set -e

# Paths: script dir = where this script lives; tailwind = sibling (override with env)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAILWIND_DIR="${TAILWIND_DIR:-$(dirname "$SCRIPT_DIR")/tailwind}"

read -p "Site name [My site]: " SITE_NAME
SITE_NAME="${SITE_NAME:-My site}"
[[ -z "$SITE_NAME" ]] && { echo "Site name is required."; exit 1; }

# Default DDEV project name = site name in kebab-case
DEFAULT_PROJECT_NAME=$(echo "$SITE_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//')
read -p "DDEV project name [$DEFAULT_PROJECT_NAME]: " PROJECT_NAME
PROJECT_NAME="${PROJECT_NAME:-$DEFAULT_PROJECT_NAME}"


# 1. Drupal initialization
mkdir -p app && cd app
ddev config --project-type=drupal11 --docroot=web --project-name="$PROJECT_NAME"
ddev start
ddev composer create-project "drupal/recommended-project:^11" .
ddev composer require drush/drush
ddev drush site:install minimal --account-name=admin --account-pass=admin --site-name="$SITE_NAME" -y


# 2. Required contrib modules
ddev composer require \
  drupal/canvas \
  drupal/config_ignore \
  drupal/filefield_paths:^1.0@RC \
  drupal/focal_point \
  drupal/imageapi_optimize \
  drupal/page_analytics:^1.0@beta \
  drupal/token


# 3. Theme (copy without .git so we get files only, not a repo)
mkdir -p web/themes/custom/tailwind && rsync -a --exclude='.git' "$TAILWIND_DIR/" web/themes/custom/tailwind/


# 4. Enable themes (Claro for admin; Tailwind for front)
ddev drush theme:enable claro -y
ddev drush theme:enable tailwind -y


# 5. Core recipes (paths relative to Drupal root = web/)
ddev drush recipe core/recipes/core_recommended_admin_theme
ddev drush recipe core/recipes/page_content_type
ddev drush recipe core/recipes/content_editor_role
ddev drush recipe core/recipes/basic_html_format_editor
ddev drush recipe core/recipes/image_media_type


# 6. Enable modules
ddev drush pm:enable -y views views_ui config field field_ui menu_ui filter text contextual file toolbar editor canvas config_ignore filefield_paths focal_point imageapi_optimize page_analytics token


# 7. Copy project config and import
sed -i.bak "s|# \\\$settings\['config_sync_directory'\] = '/directory/outside/webroot';|\\\$settings['config_sync_directory'] = '../config/sync';|" web/sites/default/settings.php
mkdir -p config/sync
cp "$SCRIPT_DIR"/config/*.yml config/sync/
ddev drush config:set system.site page.front /node -y
ddev drush config:set system.theme default tailwind -y
ddev drush cim -y --partial
# Export so config/sync matches this site (avoids "different site" on sync UI).
ddev drush cex -y


# 8. Adjust cache settings
# Uncomment the block at the end of settings.php that includes settings.local.php (if present).
sed -i.bak -e '/^# if (file_exists/s/^# //' -e '/^#   include /s/^# //' -e '/^# }$/s/^# //' web/sites/default/settings.php
cp web/sites/example.settings.local.php web/sites/default/settings.local.php
# Uncomment cache backend null lines (render, page, dynamic_page_cache) for local development.
sed -i.bak -e '/^#.*cache\.backend\.null/s/^# //' web/sites/default/settings.local.php
# Ensure development.services.yml exists (scaffolded to web/sites/ by Drupal), then insert Twig dev config from template after "parameters:".
if [ ! -f web/sites/development.services.yml ]; then
  cp web/core/assets/scaffold/files/development.services.yml web/sites/development.services.yml
fi
if ! grep -q 'twig.config:' web/sites/development.services.yml; then
  twig_insert=$(mktemp)
  tail -n +2 "$SCRIPT_DIR/development.services.local.yml.template" > "$twig_insert"
  sed -i.bak "/^parameters:/r $twig_insert" web/sites/development.services.yml
  rm -f "$twig_insert"
fi


# 9. Dotfiles
cp "$SCRIPT_DIR/gitignore.template" .gitignore
cp "$SCRIPT_DIR/cursorrules.template" .cursorrules


# 10. Style build
cd web/themes/custom/tailwind
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  . "$NVM_DIR/nvm.sh"
fi
nvm use
yarn install
yarn build:dev
cd - > /dev/null


# 11. Cache and launch
ddev drush cr
ddev launch
echo "Done. One-time login link:"
ddev drush uli
echo "Run 'yarn dev' in web/themes/custom/tailwind when developing to watch and rebuild styles."
