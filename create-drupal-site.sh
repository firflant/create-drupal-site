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

read -p "Site name [My site]: " SITE_NAME
SITE_NAME="${SITE_NAME:-My site}"
[[ -z "$SITE_NAME" ]] && { echo "Site name is required."; exit 1; }

# Default DDEV project name = site name in kebab-case
DEFAULT_PROJECT_NAME=$(echo "$SITE_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//')
read -p "DDEV project name [$DEFAULT_PROJECT_NAME]: " PROJECT_NAME
PROJECT_NAME="${PROJECT_NAME:-$DEFAULT_PROJECT_NAME}"

read -p "Theme [tailwind]: " THEME_NAME
THEME_NAME="${THEME_NAME:-tailwind}"
THEME_NAME=$(echo "$THEME_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]//g')
[[ -z "$THEME_NAME" ]] && { echo "Theme name is required."; exit 1; }


# 1. Create project
mkdir -p app && cd app
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
THEME_PATH=""
THEME_SHOULD_BUILD=false
if [ "$THEME_NAME" = "tailwind" ]; then
  TAILWIND_THEME_REPO="${TAILWIND_THEME_REPO:-https://github.com/firflant/tailwind-canvas.git}"
  mkdir -p web/themes/custom
  git clone --depth 1 "$TAILWIND_THEME_REPO" web/themes/custom/tailwind
  rm -rf web/themes/custom/tailwind/.git
  THEME_PATH="web/themes/custom/tailwind"
  THEME_SHOULD_BUILD=true
else
  DRUPAL_API=$(curl -s "https://www.drupal.org/api-d7/node.json?type=project_theme&field_project_machine_name=$THEME_NAME")
  if echo "$DRUPAL_API" | grep -q '"list":\[\]'; then
    echo "Theme '$THEME_NAME' not found on drupal.org."
    exit 1
  fi
  if echo "$DRUPAL_API" | grep -q '"id":"3060"'; then
    THEME_PATH="web/core/themes/${THEME_NAME}"
  else
    GITLAB_PROJECT=$(curl -s "https://git.drupalcode.org/api/v4/projects/project%2F${THEME_NAME}")
    BRANCH=$(echo "$GITLAB_PROJECT" | grep -o '"default_branch":"[^"]*"' | cut -d'"' -f4)
    if [ -z "$BRANCH" ]; then
      for b in 11.x 10.x 2.0.x 2.x 1.x; do
        if curl -s -o /dev/null -w "%{http_code}" "https://git.drupalcode.org/project/${THEME_NAME}/-/raw/${b}/${THEME_NAME}.info.yml" | grep -q 200; then
          BRANCH="$b"
          break
        fi
      done
    fi
    IS_STARTERKIT=false
    if [ -n "$BRANCH" ]; then
      if curl -s -o /dev/null -w "%{http_code}" "https://git.drupalcode.org/project/${THEME_NAME}/-/raw/${BRANCH}/${THEME_NAME}.starterkit.yml" | grep -q 200; then
        IS_STARTERKIT=true
      else
        INFO_YML=$(curl -s "https://git.drupalcode.org/project/${THEME_NAME}/-/raw/${BRANCH}/${THEME_NAME}.info.yml")
        if echo "$INFO_YML" | grep -qE 'starterkit:[[:space:]]*true'; then
          IS_STARTERKIT=true
        fi
      fi
    fi
    if [ "$IS_STARTERKIT" = true ]; then
      mkdir -p web/themes/custom
      git clone --depth 1 "https://git.drupalcode.org/project/${THEME_NAME}.git" "web/themes/custom/${THEME_NAME}"
      rm -rf "web/themes/custom/${THEME_NAME}/.git"
      THEME_PATH="web/themes/custom/${THEME_NAME}"
      THEME_SHOULD_BUILD=true
    else
      ddev composer require "drupal/${THEME_NAME}"
      THEME_PATH="web/themes/contrib/${THEME_NAME}"
    fi
  fi
fi
ddev drush theme:enable "$THEME_NAME" -y
ddev drush config:set system.theme default "$THEME_NAME" -y


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


# 9. Build styles (only for custom themes with package.json and build/production script)
THEME_WAS_BUILT=false
if [ "$THEME_SHOULD_BUILD" = true ] && [ -f "$THEME_PATH/package.json" ]; then
  BUILD_SCRIPT=""
  if grep -q '"build"' "$THEME_PATH/package.json"; then
    BUILD_SCRIPT="build"
  elif grep -q '"production"' "$THEME_PATH/package.json"; then
    BUILD_SCRIPT="production"
  fi
  if [ -n "$BUILD_SCRIPT" ]; then
    cd "$THEME_PATH"
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
      . "$NVM_DIR/nvm.sh"
      [ -f .nvmrc ] && nvm use || true
    fi
    npm install
    npm run "$BUILD_SCRIPT"
    cd - > /dev/null
    THEME_WAS_BUILT=true
  fi
fi


# 10. Rebuild cache
ddev drush cr


# 11. Initialize git repository
git init
git add .
git commit -m "Initial commit"


# 12. Done
echo "Done."
ddev launch $(ddev drush uli)
if [ "$THEME_WAS_BUILT" = true ]; then
  echo "Run 'npm run dev' in $THEME_PATH when developing to watch and rebuild styles."
fi
