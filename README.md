# CloudBar

A small native macOS menu bar app for checking Laravel Cloud usage.

CloudBar calls `GET https://cloud.laravel.com/api/usage` with a Laravel Cloud API bearer token, then shows current spend, bandwidth, resource cost, application totals, add-ons, and alert information in the menu bar.

## Run

```bash
swift run CloudBar
```

Paste a Laravel Cloud API token on first launch. The token is stored in the macOS Keychain under `com.cloudbar.laravel-cloud`.

## Build

```bash
xcodebuild -scheme CloudBar -configuration Debug -destination "platform=macOS"
```

## Package as an App

```bash
./scripts/package-app.sh
open Build/CloudBar.app
```

The packaged app is configured as an agent app with `LSUIElement`, so it appears in the menu bar without adding a Dock icon.
