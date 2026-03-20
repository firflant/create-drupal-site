#!/usr/bin/env bash
set -e

# Paths: script dir = where this script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# When run via "curl ... | bash", there is no script file so SCRIPT_DIR is wrong and we have no
# config/templates. Clone the repo and re-exec so the rest of the script sees the real repo root.
REPO_URL="${CREATE_DRUPAL_SITE_REPO:-https://github.com/firflant/create-drupal-site.git}"
if [ ! -f "$SCRIPT_DIR/templates/deploy.sh" ]; then
  CLONE_DIR=$(mktemp -d)
  echo "Fetching create-drupal-site from GitHub..."
  git clone --depth 1 "$REPO_URL" "$CLONE_DIR"
  exec env CREATE_DRUPAL_SITE_CLONE="$CLONE_DIR" bash "$CLONE_DIR/create-drupal-site.sh" < /dev/tty
fi
# Clean up the temporary clone when we exit (we were re-exec'd from it).
if [ -n "${CREATE_DRUPAL_SITE_CLONE-}" ] && [ -d "${CREATE_DRUPAL_SITE_CLONE}" ]; then
  trap 'rm -rf "${CREATE_DRUPAL_SITE_CLONE}"' EXIT
fi


# Prompts: prompt_default → optional transform → require non-empty
# Prompt with default shown in brackets; empty input uses default. Sets variable named $3.
prompt_default() {
  local _label="$1" _default="$2" _var="$3" _input
  read -rp "${_label} [${_default}]: " _input
  printf -v "$_var" '%s' "${_input:-$_default}"
}

prompt_default "Site name" "My site" SITE_NAME
[[ -z "$SITE_NAME" ]] && { echo "Site name is required."; exit 1; }

DEFAULT_PROJECT_NAME=$(echo "$SITE_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//')
prompt_default "Local project subdomain" "$DEFAULT_PROJECT_NAME" PROJECT_NAME
[[ -z "$PROJECT_NAME" ]] && { echo "Local project subdomain is required."; exit 1; }

prompt_default "Installation directory" "$PROJECT_NAME" INSTALL_DIR
INSTALL_DIR="${INSTALL_DIR#"${INSTALL_DIR%%[![:space:]]*}"}"
INSTALL_DIR="${INSTALL_DIR%"${INSTALL_DIR##*[![:space:]]}"}"
[[ -z "$INSTALL_DIR" ]] && { echo "Installation directory is required."; exit 1; }
[[ "$INSTALL_DIR" == *..* ]] && { echo "Installation directory must not contain '..'."; exit 1; }
case "$INSTALL_DIR" in
  /*) echo "Installation directory must be a relative path."; exit 1 ;;
esac

prompt_default "Theme" "tailwindcss" THEME_NAME
THEME_NAME=$(echo "$THEME_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]//g')
[[ -z "$THEME_NAME" ]] && { echo "Theme name is required."; exit 1; }


# 1. Create project
mkdir -p "$INSTALL_DIR" && cd "$INSTALL_DIR"
ddev config --project-type=drupal11 --docroot=web --project-name="$PROJECT_NAME"
ddev start
ddev composer create-project "drupal/recommended-project:^11" .
ddev composer require \
  drush/drush \
  drupal/canvas \
  drupal/coffee \
  drupal/config_ignore \
  drupal/filefield_paths:^1.0@RC \
  drupal/focal_point \
  drupal/gin \
  drupal/imageapi_optimize \
  drupal/page_analytics:^1.0@beta \
  drupal/sam \
  drupal/token


# 2. Install Drupal
ddev drush site:install minimal --account-name=admin --account-pass=admin --site-name="$SITE_NAME" -y


# 3. Apply recipes
mkdir -p recipes/create_drupal_site
cp -r "$SCRIPT_DIR/recipe/." recipes/create_drupal_site/
ddev drush recipe ../recipes/create_drupal_site
rm -rf recipes/create_drupal_site


# 4. Enable admin theme and navigation
ddev drush theme:enable gin -y
ddev drush config:set system.theme admin gin -y
# Navigation via drush (not recipe) to avoid broken navigation_menu:content block plugin.
ddev drush pm:enable -y navigation
# Canvas via drush (not recipe) to avoid broken canvas module installation.
ddev drush pm:enable -y canvas


# 5. Enable front-end theme
# shellcheck source=helpers/frontend_theme.sh
source "$SCRIPT_DIR/helpers/frontend_theme.sh"


# 6. Export config
sed -i.bak "s|# \\\$settings\['config_sync_directory'\] = '/directory/outside/webroot';|\\\$settings['config_sync_directory'] = '../config/sync';|" web/sites/default/settings.php
mkdir -p config/sync
ddev drush cex -y


# 7. Configure local development
# Uncomment the block at the end of settings.php that includes settings.local.php (if present).
sed -i.bak -e '/^# if (file_exists/s/^# //' -e '/^#   include /s/^# //' -e '/^# }$/s/^# //' web/sites/default/settings.php
cp web/sites/example.settings.local.php web/sites/default/settings.local.php
# Add development.services.local.yml to container_yamls (duplicate the container_yamls line with services.yml -> services.local.yml).
sed -i.bak '/container_yamls/{
  p
  s/services\.yml/services.local.yml/
}' web/sites/default/settings.local.php
# Uncomment cache backend null lines (render, page, dynamic_page_cache) for local development.
sed -i.bak -e '/^#.*cache\.backend\.null/s/^# //' web/sites/default/settings.local.php
cp "$SCRIPT_DIR/templates/development.services.local.yml" web/sites/development.services.local.yml


# 8. Copy dotfiles and scripts
cp "$SCRIPT_DIR/templates/gitignore.template" .gitignore
cp "$SCRIPT_DIR/templates/AGENT.md" AGENT.md
cp "$SCRIPT_DIR/templates/deploy.sh" deploy.sh
cp "$SCRIPT_DIR/templates/production-setup.sh" production-setup.sh
cp "$SCRIPT_DIR/templates/db-dump.sh" db-dump.sh
cp "$SCRIPT_DIR/templates/drush-noexec-workaround.sh" drush-noexec-workaround.sh
chmod +x deploy.sh production-setup.sh db-dump.sh drush-noexec-workaround.sh


# 9. Build theme assets
# shellcheck source=helpers/build_theme_assets.sh
source "$SCRIPT_DIR/helpers/build_theme_assets.sh"


# 10. Rebuild cache
ddev drush cr


# 11. Initialize git repository
git init
git add .
git commit -q -m "Initial commit"


# 12. Done (Create Drupal Site)
SITE_LOCATION="$(pwd -P)"
SITE_URL="https://${PROJECT_NAME}.ddev.site"
if command -v jq >/dev/null 2>&1; then
  _dd_json=$(ddev describe -j 2>/dev/null || true)
  _primary_url=$(echo "$_dd_json" | jq -r '.raw.primary_url // .primary_url // empty' 2>/dev/null || true)
  if [ -z "$_primary_url" ] || [ "$_primary_url" = "null" ]; then
    _primary_url=$(echo "$_dd_json" | jq -r '.raw.httpsURLs[0] // empty' 2>/dev/null || true)
  fi
  if [ -n "$_primary_url" ] && [ "$_primary_url" != "null" ]; then
    SITE_URL="$_primary_url"
  fi
fi
echo ""
echo "==="
echo "Created a Drupal site \"${SITE_NAME}\" at ${SITE_LOCATION}, with theme \"${THEME_NAME}\"."
echo "Site is available for local development at ${SITE_URL}"
if [ "$THEME_SHOULD_BUILD" = true ] && [ -f "$THEME_PATH/package.json" ]; then
  THEME_NPM_WATCH_SCRIPT=""
  if grep -qE '"dev"[[:space:]]*:' "$THEME_PATH/package.json"; then
    THEME_NPM_WATCH_SCRIPT="dev"
  elif grep -qE '"watch"[[:space:]]*:' "$THEME_PATH/package.json"; then
    THEME_NPM_WATCH_SCRIPT="watch"
  fi
  if [ -n "$THEME_NPM_WATCH_SCRIPT" ]; then
    echo "Run 'npm run $THEME_NPM_WATCH_SCRIPT' in $THEME_PATH when developing to watch and rebuild styles."
  fi
fi
echo "==="
ddev launch $(ddev drush uli)
