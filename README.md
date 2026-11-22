# BetterScroll

Smooth scrolling, wheel modes, and custom gestures for Logitech MX Master mice on macOS. BetterScroll lives in the menu bar and leaves your trackpad settings alone.

[Download BetterScroll for Apple silicon](https://github.com/gokberkkaraca/BetterScroll/releases/latest)

## Get started

1. Open the DMG and drag BetterScroll to **Applications**.
2. Pair your mouse over Bluetooth and open BetterScroll from Applications.
3. In **System Settings → Privacy & Security**, allow **Input Monitoring** for mouse reports and **Accessibility** for smooth scrolling and shortcuts. Then quit and reopen BetterScroll.
4. Click the mouse icon in the menu bar to change your settings.

BetterScroll is ad-hoc signed. macOS may require you to approve it in **System Settings → Privacy & Security** on first launch. See [Apple’s guide to opening downloaded apps](https://support.apple.com/en-us/102445).

## Controls

- **Scrolling** lets you turn on smooth vertical scrolling, reverse the wheel direction independently, and choose Ratchet, Free-spin, or SmartShift. The physical wheel mode button cycles through all three modes.
- **Buttons** lets you assign shortcuts or choose **Mouse default** to use the button’s original action.
- **Gestures** lets you assign an action to tap or to each of the four directions while holding the gesture button.
- **Open at Login** starts the app when you sign in. If you’ve hidden the menu-bar icon, it stays hidden on login. Open BetterScroll from Applications to bring it back.

## Compatibility

- macOS 12 or later on Apple silicon. **Open at Login** requires macOS 13 or later.
- Bluetooth models include MX Master 2S, 3, 3S, 4, and 4 for Business. The MX Master 3 has been tested on macOS. The other models are experimental.
- BetterScroll controls one mouse at a time. Use it with other mouse configuration apps closed.

## Updates

Choose **Check for Updates…** in the menu-bar panel. Confirm **Install Update** and BetterScroll will download the signed update, install it, and reopen. macOS may ask for Accessibility and Input Monitoring again after an update.

## Build from source

With Xcode command-line tools installed, run `make check build SIGN_IDENTITY=-` for a local build at `build/BetterScroll.app`. See [maintainer notes](docs/RELEASING.md) for signing, packaging, and release automation.
