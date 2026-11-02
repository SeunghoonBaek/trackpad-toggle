# Trackpad Toggle

A macOS menu bar app that toggles **Ignore built-in trackpad when mouse or wireless trackpad is present** with one click.

Use the built-in trackpad when you need it, then turn the ignore setting back on without opening System Settings.

## Features

- **One-click toggle:** left-click the menu bar icon to change the setting.
- **Icon-only status:** a slashed trackpad means the ignore setting is on; a plain trackpad means it is off.
- **Settings sync:** changes made in System Settings appear in the app within a few seconds.
- **Optional launch at login:** enable it from the right-click menu.
- **English interface:** menus, tooltips, help, and app error messages are in English.

The setting applies when an external mouse or trackpad is connected. macOS decides when to ignore the built-in trackpad. The icon shows the setting's state, not whether input is currently being blocked.

## Requirements

- An Apple Silicon Mac. The build script currently produces an `arm64` app.
- Xcode Command Line Tools. Install them with `xcode-select --install` if needed.

The app targets macOS 13 or later and was tested on macOS 26.7.1. It uses a private macOS API, so compatibility with every macOS version is not guaranteed.

## Build and install

```sh
git clone https://github.com/SeunghoonBaek/trackpad-toggle.git
cd trackpad-toggle
make install
open "/Applications/Trackpad Toggle.app"
```

`make install` builds the app, copies it to `/Applications`, and verifies its code signature. It does not launch the app automatically.

To build without installing:

```sh
make build
```

The app is created as `Trackpad Toggle.app` in the project folder. To install it elsewhere:

```sh
make install INSTALL_DIR="$HOME/Applications"
open "$HOME/Applications/Trackpad Toggle.app"
```

Before reinstalling an update, choose **Quit Trackpad Toggle** from the menu bar, then run `make install` and open the app again.

## Usage

| Action or indicator | Meaning |
| --- | --- |
| Left-click | Toggle the ignore setting |
| Right-click or Control-click | Open the menu |
| Slashed trackpad icon | Ignore setting is on |
| Plain trackpad icon | Ignore setting is off |
| Launch at Login | Start the app when you log in |
| Open Pointer Control Settings… | Open the corresponding macOS settings page |
| How to Use… | Show the help window |
| Quit Trackpad Toggle | Quit the app and leave the current setting in place |

Closing the help window keeps the app running in the menu bar. Launch at login is off by default. If macOS requests approval, allow the app in Login Items.

## How it works

The app is written in Swift using AppKit. `NSStatusItem` provides the menu bar button, and `SMAppService` manages launch at login.

At runtime, the app loads `UniversalAccess.framework` and resolves the same functions used by Pointer Control settings:

- `UAIgnoreTrackpadWhenExternalMouseEnabled()` reads the setting.
- `UAIgnoreTrackpadWhenExternalMouseSetEnabled(Bool)` changes it.

After a toggle, the app reads the setting back to check the result. It also refreshes its status every two seconds to pick up changes made elsewhere.

## Compatibility and validation

These functions are private Apple APIs. A future macOS update may require changes to the app. If the functions cannot be found, the app shows an error and provides a link to Pointer Control settings.

On the tested Mac, toggling through the help window updated the System Settings switch and the driver's `USBMouseStopsTrackpad` value. Changes made in System Settings also appeared in the app. Direct menu bar clicks, physical input blocking, device disconnection, and launch after a fresh login were not independently tested.

The app did not require additional Accessibility or administrator permissions on the tested Mac. Builds are signed locally with an ad-hoc signature and are not notarized by Apple.

## Uninstall

Turn off **Launch at Login**, quit the app, and move `Trackpad Toggle.app` from its installation folder to the Trash. Uninstalling does not reset the macOS trackpad setting; choose the state you want before quitting.
