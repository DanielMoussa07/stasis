# Sparkle Setup and Release Flow

This repository is now wired to automate Sparkle update packaging in CI.

## One-time setup

1. Generate Sparkle keys locally:

```bash
./scripts/sparkle_generate_keys.sh
```

2. Save outputs:
- Private key file: `releases/keys/sparkle_private_key` (keep secret)
- Public key: printed by Sparkle (copy this)

3. Set app target keys in Xcode (`stasis` target only):
- `INFOPLIST_KEY_SUFeedURL` = your real appcast URL
- `INFOPLIST_KEY_SUPublicEDKey` = Sparkle public key

Current project is set to:
- `https://github.com/DinanathDash/Stasis/releases/latest/download/appcast.xml`

## GitHub Actions secrets required

Set these repository secrets:

- `SPARKLE_PRIVATE_KEY`: full private key content (multi-line)

`SPARKLE_DOWNLOAD_BASE_URL` is computed automatically by CI from the release tag:
- `https://github.com/<owner>/<repo>/releases/download/<tag>`

## What CI now does on push to `main`

1. Bumps app version/build.
2. Archives and exports app.
3. Creates DMG.
4. Creates Sparkle ZIP (`Stasis-<version>.zip`).
5. Signs ZIP with `sign_update`.
6. Generates `releases/appcast/appcast.xml` using `generate_appcast`.
7. Publishes DMG + ZIP + appcast + release notes HTML to GitHub Release.

## Local release command (manual fallback)

```bash
cp .env.example .env
# edit .env values for the current release tag
./scripts/sparkle_release.sh 0.0.7 7
```

This performs your required steps 3-6 (build, zip, sign, appcast output).

## Release notes

Place per-version note files here:
- `releases/notes/0.0.7.html`

If missing, CI/script auto-creates a minimal placeholder.
