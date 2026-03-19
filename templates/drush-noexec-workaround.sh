#!/bin/bash

###############################################################################
# MyDevil Shared Hosting - Drush noexec Workaround
#
# This file is sourced by deploy.sh ONLY when vendor/bin/drush cannot be
# executed directly (i.e. when the server's filesystem is mounted with 'noexec').
#
# WHY THIS EXISTS:
# MyDevil mounts the user home directory (/usr/home/) with the 'noexec' kernel
# flag. This means the OS will REFUSE to directly execute any script or binary
# placed in the project folder, even if it has chmod +x permissions.
# This affects vendor/bin/drush and any Composer-generated bin wrappers.
#
# TWO-LAYER PROBLEM:
#
# Layer 1 - Main drush() calls from deploy.sh:
#   We cannot run vendor/bin/drush directly (noexec blocks it). Instead, we
#   invoke the underlying drush.php file explicitly with `php`. This works
#   because `php` itself lives outside the noexec-mounted directory.
#
# Layer 2 - Drush SUBPROCESS calls (e.g. during `drush updatedb`):
#   Drush spawns background child processes to handle large operations in
#   batches (to avoid memory exhaustion). These subprocesses bypass our bash
#   drush() function and blindly try to exec() vendor/bin/drush directly.
#   Fix: export the DRUSH env var pointing to a script in /tmp/ - which is
#   NOT mounted with noexec and CAN execute scripts. Drush reads this env var
#   and uses it for all subprocess invocations instead of vendor/bin/drush.
#
# Layer 3 - Composer wipes vendor/bin/drush on every install:
#   After each `composer install`, the vendor/ folder is rebuilt from scratch,
#   destroying any /tmp symlink we created previously. So we must re-establish
#   the symlink after every Composer run (see setup_drush_symlink below).
#
# DRUSH_LAUNCHER_FALLBACK=0 prevents Drush from silently falling back to the
# global system Drush on MyDevil, which is an incompatible older version.
###############################################################################

# Require SCRIPT_DIR to be set by the caller (deploy.sh)
if [ -z "$SCRIPT_DIR" ]; then
    echo "Error: SCRIPT_DIR is not set. This file must be sourced from deploy.sh." >&2
    exit 1
fi

# Create a wrapper script in the project root that invokes drush.php via PHP.
# This is what the DRUSH env var will point to for subprocess invocations.
# It lives in the project root but calls PHP explicitly (PHP reads it as a
# text file, not a binary, so the noexec restriction doesn't apply).
wrapper_path="$SCRIPT_DIR/drush-wrapper.sh"
cat > "$wrapper_path" << 'WRAPPER_EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
php "$SCRIPT_DIR/vendor/drush/drush/drush.php" --root="$SCRIPT_DIR/web" "$@"
WRAPPER_EOF
chmod +x "$wrapper_path" 2>/dev/null || true

# Export DRUSH so all Drush subprocess invocations use our PHP-based wrapper
# instead of trying to directly execute the noexec-blocked vendor/bin/drush.
export DRUSH="$wrapper_path"
export DRUSH_LAUNCHER_FALLBACK=0

# Override the drush command for all calls in the parent script.
# Invokes drush.php directly via `php` to bypass the noexec restriction.
# Subprocesses are handled separately via the DRUSH env var + symlink below.
drush() {
    export DRUSH="${DRUSH:-$SCRIPT_DIR/drush-wrapper.sh}"
    export DRUSH_LAUNCHER_FALLBACK=0
    php "$SCRIPT_DIR/vendor/drush/drush/drush.php" --root="$SCRIPT_DIR/web" "$@"
}

# Call this function after every `composer install` to re-establish the /tmp
# symlink for vendor/bin/drush. Composer recreates vendor/ from scratch each
# run, destroying any previous symlink we placed there.
#
# WHY /tmp/ SPECIFICALLY:
# /tmp/ is not mounted with noexec, so the OS allows direct script execution
# from there. Drush subprocesses can successfully exec() a script from /tmp/
# even though they cannot exec() one from the project folder.
setup_drush_vendor_symlink() {
    local drush_path="$SCRIPT_DIR/vendor/bin/drush"

    mkdir -p "$(dirname "$drush_path")" 2>/dev/null || true

    local tmp_wrapper="/tmp/drush-wrapper-$(whoami)-$$.sh"
    cat > "$tmp_wrapper" << TMPWRAPPER_EOF
#!/bin/bash
SCRIPT_DIR="$SCRIPT_DIR"
php "\$SCRIPT_DIR/vendor/drush/drush/drush.php" --root="\$SCRIPT_DIR/web" "\$@"
TMPWRAPPER_EOF

    chmod +x "$tmp_wrapper" 2>/dev/null || true

    if [ -x "$tmp_wrapper" ] && "$tmp_wrapper" --version >/dev/null 2>&1; then
        rm -f "$drush_path"
        ln -s "$tmp_wrapper" "$drush_path" 2>/dev/null || cp "$tmp_wrapper" "$drush_path"
        echo "✓ vendor/bin/drush symlinked to /tmp wrapper (noexec workaround active)"
    else
        echo "Warning: Could not create /tmp Drush wrapper. Subprocess commands may fail." >&2
    fi
}
