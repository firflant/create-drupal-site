#!/usr/bin/env bash
# Enable front-end theme (Drupal.org + git.drupalcode.org / composer).
#
# Sourced from create-drupal-site.sh with cwd = project app/ directory.
# Input:  THEME_NAME (required)
# Output: THEME_PATH, THEME_SHOULD_BUILD

[[ -z "${THEME_NAME:-}" ]] && {
  echo "enable_front_end_theme.sh: THEME_NAME must be set" >&2
  return 1 2>/dev/null || exit 1
}

THEME_PATH=""
THEME_SHOULD_BUILD=false

DRUPAL_API=$(curl -s "https://www.drupal.org/api-d7/node.json?type=project_theme&field_project_machine_name=$THEME_NAME")
if echo "$DRUPAL_API" | grep -q '"list":\[\]'; then
  echo "Theme '$THEME_NAME' not found on drupal.org."
  return 1 2>/dev/null || exit 1
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
ddev drush theme:enable "$THEME_NAME" -y
ddev drush config:set system.theme default "$THEME_NAME" -y
