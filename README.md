# Studi0Toggle

Menu bar app for quickly switching between GitHub CLI (`gh`) accounts on macOS.

## Features

- Left-click the menu bar icon to switch to the next GitHub account.
- Right-click to choose a specific account.
- Per-account icon and color in the menu bar and menu.
- Username display modes: none, short, or full.
- Launch-on-startup toggle in Settings.
- Local config persisted between launches.
- Uses whatever GitHub CLI accounts are configured on the current machine.

## Requirements

- macOS 13 or newer
- Xcode Command Line Tools
- GitHub CLI (`gh`)

Install prerequisites:

```bash
xcode-select --install
brew install gh
```

## Quick Start

```bash
git clone https://github.com/timothynice/GitHub-toggle.git
cd GitHub-toggle
chmod +x *.sh
./doctor.sh
./run.sh
```

## Build, Run, Install

Build the app bundle:

```bash
./build.sh
```

Output:

`./build/Studi0Toggle.app`

Build and launch immediately:

```bash
./run.sh
```

Install for current user (recommended, no admin permission required):

```bash
./install.sh --launch
```

Install system-wide to `/Applications`:

```bash
./install.sh --system --launch
```

Installing to `/Applications` is the recommended path if you want to enable `Launch on startup` from Settings.

Or use `make` shortcuts:

```bash
make doctor
make build
make run
make install
```

## First-Time GitHub Setup

The app does not bundle usernames, tokens, or account-specific logic for other developers. It reads the currently configured local `gh` accounts on each machine.

Add/log into each account you want to switch between:

```bash
gh auth login -h github.com
```

Verify auth status:

```bash
gh auth status --hostname github.com
```

## Usage

- Left-click status item: switch to next account.
- Right-click status item: select account, refresh, open settings, or quit.
- Settings:
  - Per-account icon and color.
  - Default icon and color fallback.
  - Username display mode (`No username`, `Short username`, `Full username`).
  - `Launch on startup` toggle.

## Configuration

Config file location:

`~/Library/Application Support/Studi0Toggle/config.json`

To reset app settings, quit the app and remove that file.

## Troubleshooting

- `No accounts found`
  - Run `gh auth login -h github.com` and re-open the app.
- `xcrun` or `swiftc` not found
  - Install Xcode Command Line Tools: `xcode-select --install`
- Build fails after environment changes
  - Run `./doctor.sh`, then `./build.sh`

## App Icon

The app icon source artwork is stored in:

`./Assets/Studi0Toggle-icon-source.png`

To regenerate the macOS `.icns` from the source artwork:

```bash
./generate-icon.sh
```
