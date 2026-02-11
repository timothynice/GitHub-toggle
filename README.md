# GH Status Toggle (macOS menu bar app)

Minimal status-bar app to switch GitHub CLI accounts quickly.

## What it does

- Left-click the status item to toggle to the next `gh` account.
- Right-click to see all accounts and switch directly.
- Color dot shows which account is active at a glance.
- Settings window lets you set a color per account.

## Requirements

- macOS 13+
- GitHub CLI installed (`gh`)
- Xcode Command Line Tools installed (`xcode-select --install`)

## Build

```bash
cd /path/to/GitHub-toggle
chmod +x build.sh
./build.sh
```

App is produced at:

`./build/GHStatusToggle.app`

## Install

1. Move app to `/Applications`:

```bash
cp -R ./build/GHStatusToggle.app /Applications/
```

2. Open `/Applications/GHStatusToggle.app`.
3. Grant permissions if macOS asks.
4. (Optional) Add it to login items:
   `System Settings -> General -> Login Items -> + -> GHStatusToggle.app`

## Use

- Ensure you already have multiple GitHub accounts authenticated in `gh`.
- Add accounts if needed:

```bash
gh auth login
```

- In the status bar:
  - Left click: switch to next account.
  - Right click: pick a specific account, open Settings, or quit.
  - `Settings...`: pick per-account colors.

## Config location

The app saves settings here:

`~/Library/Application Support/GHStatusToggle/config.json`
