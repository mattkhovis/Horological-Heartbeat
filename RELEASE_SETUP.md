# Release Setup (Standalone macOS App)

This project can be distributed as a standalone app. End users do **not** need Xcode.

The workflow at `.github/workflows/release.yml` builds and signs the app, notarizes it with Apple, creates a DMG, and uploads release assets to GitHub Releases.

## 1. Apple Requirements

1. Enroll in Apple Developer Program.
2. Create a **Developer ID Application** certificate in Apple Developer account.
3. Export that certificate from Keychain Access as `.p12` with a password.
4. Create an app-specific password for your Apple ID.

## 2. Add GitHub Secrets

Add these repository secrets:

- `APPLE_TEAM_ID`: Your Apple Developer Team ID.
- `APPLE_ID`: Apple ID email used for notarization.
- `APPLE_APP_SPECIFIC_PASSWORD`: App-specific password for notarization.
- `APPLE_DEVELOPER_ID_APPLICATION`: Full signing identity string.
  - Example: `Developer ID Application: Your Name (TEAMID)`
- `APPLE_DEVELOPER_ID_P12_BASE64`: Base64 content of the exported `.p12`.
- `APPLE_DEVELOPER_ID_P12_PASSWORD`: Password used when exporting the `.p12`.

To generate the base64 string locally:

```sh
base64 -i developer_id_application.p12 | pbcopy
```

Then paste clipboard contents into `APPLE_DEVELOPER_ID_P12_BASE64`.

## 3. Create a Release

Push a semver-like tag:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The workflow will:

1. Build archive in Release mode
2. Sign app with your Developer ID certificate
3. Notarize app and DMG
4. Staple notarization tickets
5. Upload `.dmg` and `.zip` to a GitHub Release

## 4. Verify Downloaded Artifact

After downloading the DMG, verify notarization:

```sh
spctl -a -vv -t install /path/to/Horological\ Heartbeat.dmg
```

## Notes

- If the app name changes, update `APP_NAME` in the workflow.
- If the scheme or project path changes, update `SCHEME` and `PROJECT_PATH` in the workflow.
