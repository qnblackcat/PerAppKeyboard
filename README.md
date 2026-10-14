# PerAppKeyboard

Choose the keyboard each app starts on, from the keyboards you have enabled in iOS. For jailbroken iOS 15+.

## Features

- Per app: a fixed keyboard (any iOS keyboard you have enabled), **Last used in this app**, or **Don't change** (the default, iOS decides)
- The keyboard goes back to the app's keyboard every time it appears. You can still switch with the globe key while typing
- Choose what resets it: hiding the keyboard, going Home or to another app, locking with the power button
- Master switch, also available as a Control Center toggle
- Leaves password, number, URL and e-mail fields and hardware keyboards alone

Only stock iOS keyboards (from Keyboard Settings) are supported, not third-party ones.

## Usage

Settings → PerAppKeyboard → **Default keyboard per app** → pick an app → pick its keyboard. Nothing changes in apps you don't set up. A newly set up app takes effect the next time you open it.

## Requirements

- iOS 15.0 or later, rootless or roothide
- [AltList](https://github.com/opa334/AltList) (`com.opa334.altlist`) for the app picker
- PreferenceLoader and [CCSupport](https://github.com/opa334/CCSupport) (the Control Center toggle)

Written and tested on iOS 17.1 and 16.3.1; iOS 15 _*should_ work.

## Building

Requires [Theos](https://theos.dev) (the [roothide fork](https://github.com/roothide/theos) for roothide packages).

```bash
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

Set `PAK_DEBUG` to `1` in `Tweak.x` to log what the tweak does to Console.app (filter by `PerAppKeyboard`).

## License

[GPLv3](LICENSE) © 2026 Qn (Đạt Nguyễn)
