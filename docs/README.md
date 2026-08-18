# Repster public website

This folder **is** the live site at <https://repster-app.github.io/Repster/>.
Edit these files and push `NewMain` — there is no separate publish step.

## GitHub Pages

Publish from:

- Branch: `NewMain`
- Folder: `/docs`

The contents of this folder are served at the site root, so `privacy.html` here
is `https://repster-app.github.io/Repster/privacy.html`.

**Do not change that URL.** The app links to it directly from Settings
(`SettingsViewModel.privacyPolicyURL` / `.termsOfUseURL`), including in versions
already on the App Store, and it is the Privacy Policy URL registered in App
Store Connect.

## Pages

- `index.html` - marketing home page
- `docs.html` - feature documentation
- `support.html` - support FAQ and contact
- `privacy.html` - privacy policy
- `terms.html` - terms of use

## History

Until 2026-08-17 this site lived at the root of the `main` branch, and a second,
divergent copy sat in `marketing/website/`. The 2026-08-08 privacy rewrite was
written into that copy — which is not published — so it never reached users and
silently dropped five sections. There is now one copy: this one. `main` is kept
as an archive of what was previously served.
