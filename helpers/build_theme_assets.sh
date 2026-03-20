#!/usr/bin/env bash
# Run npm install + build/production in the front-end theme when applicable.
#
# Sourced from create-drupal-site.sh with cwd = project app/ directory.
# Input:  THEME_SHOULD_BUILD, THEME_PATH (from frontend_theme.sh)

if [ "${THEME_SHOULD_BUILD:-false}" = true ] && [ -f "${THEME_PATH:-}/package.json" ]; then
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
  fi
fi
