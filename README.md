# Firflant Starter

Minimal Drupal + Page content type, Content editor role, Canvas, Tailwind. Requires **minimal** profile. Bash installer; theme and this project from local drive.

## Prerequisites

DDEV, this project folder locally, Tailwind theme folder locally.

## Installation

From the directory where you want the Drupal app (e.g. parent of this project), run:

```bash
/path/to/firflant_starter/install.sh
```

The script will prompt for **site name** (default "My site") and **DDEV project name** (default kebab-case of site name), then:

- Create `app`, install Drupal minimal, require contrib modules, copy the Tailwind theme
- Enable Claro, apply core recipes (admin theme, page content type, content editor role, basic HTML editor, image media type)
- Enable Canvas and other modules plus Tailwind theme, copy this project’s config into `config/sync`, set front page to `/node`, import config
- Build theme styles, clear cache, launch, and print a one-time login link

- **Tailwind theme:** By default the script expects the Tailwind theme as a sibling of this project (e.g. `../tailwind`). Override with `TAILWIND_DIR=/path/to/tailwind` if needed.
- For ongoing development, run `yarn dev` in `app/web/themes/custom/tailwind` to watch and rebuild styles.
