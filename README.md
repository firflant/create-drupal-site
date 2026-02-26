# Create Drupal Site

A one-liner installation command for creating a new Drupal project locally.

It sets up a Drupal site from scratch with the most commonly required modules, initial Canvas configuration, Canvas-engaged Tailwind theme, and a full development environment. It also provides a compatible CI/CD script for deploying your local changes to production hosting.

## Prerequisites

- [DDEV](https://ddev.com/get-started/) - the most popular dev server for local Drupal development must be installed on your system.
- [Yarn](https://yarnpkg.com/getting-started/install) - a JS package manager and Node.js script runner for building the Tailwind assets.

## Usage

From the directory where you want the Drupal app (e.g. parent of this project), run:

```bash
/path/to/create_drupal_site/install.sh
```

The script will prompt for **site name** (default "My site") and **DDEV project name** (default kebab-case of site name), then:

- Create `app`, install Drupal minimal, require contrib modules, copy the Tailwind theme
- Enable Claro, apply core recipes (admin theme, page content type, content editor role, basic HTML editor, image media type)
- Enable Canvas and other modules plus Tailwind theme, copy this project’s config into `config/sync`, set front page to `/node`, import config
- Build theme styles, clear cache, launch, and print a one-time login link

- **Tailwind theme:** By default the script expects the Tailwind theme as a sibling of this project (e.g. `../tailwind`). Override with `TAILWIND_DIR=/path/to/tailwind` if needed.
- For ongoing development, run `yarn dev` in `/web/themes/custom/tailwind` to watch and rebuild styles.


## Release

Make sure that your hosting environment allows Composer, Drush, and Node.js (for building the Tailwind styles).

1. Export the current configuration using `ddev drush cex -y` command
2. Commit all changes to git and push them.
3. On the configured hosting environment, go to the project directory and run `bash deploy.sh`.

### Deploying the site on shared hosting platforms that do not support Node.js

Remove the `dist/` line from the .gitignore file in `web/themes/custom/tailwind`, then make sure you run `yarn build`and commit the generated stylesheet file before you push your local changes to git.
