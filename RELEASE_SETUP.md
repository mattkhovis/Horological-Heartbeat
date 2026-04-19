# Release Setup (Standalone macOS App)

This project can be distributed as a standalone app. End users do **not** need Xcode.

The workflow at `.github/workflows/release.yml` builds the app without code signing and uploads a `.zip` to GitHub Releases. No Apple Developer account is required.

## 1. Create a Release

Push a semver-like tag:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The workflow will:

1. Build the archive in Release mode (unsigned)
2. Package the `.app` into a `.zip`
3. Upload the `.zip` to a GitHub Release

## 2. User Note: macOS Gatekeeper

Because the app is unsigned, macOS Gatekeeper will block it on first launch with a "cannot be opened because the developer cannot be verified" message. Users can bypass this in one of two ways:

- **Right-click the app → Open**, then click **Open** in the dialog.
- Go to **System Settings → Privacy & Security** and click **Open Anyway** after the first blocked attempt.

This is a one-time step per installation.

## Notes

- If the app name changes, update `APP_NAME` in the workflow.
- If the scheme or project path changes, update `SCHEME` and `PROJECT_PATH` in the workflow.
