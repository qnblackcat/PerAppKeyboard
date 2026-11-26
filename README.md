<img width="1179" height="2556" alt="IMG_CE2E577E3BF4-1" src="https://github.com/user-attachments/assets/6651bede-ed9a-4a22-8df3-2ca519e9e148" />

# PerAppKeyboard

Choose the **keyboard each app starts on**, from the keyboards you have added in iOS. For jailbroken iOS 15+.

- Pick the apps in Settings → PerAppKeyboard → Default keyboard per app. Apps you don't set up are left alone.
- Per app: a fixed keyboard, **Last used in this app**, or **Don't change** (iOS decides).
- Third-party keyboards work too. The tweak only launches them: Full Access and their own settings are up to you.
- You can still switch with the globe key while typing. The keyboard goes back to the app's one when you hide it, go Home / to another app, or lock with the power button (each can be turned off).
- Password, number, URL and e-mail fields and hardware keyboards are left alone.
- Master switch, also available as a Control Center toggle.

## Build

<details>
<summary>Build instructions</summary>

Build with Theos (roothide fork).

```sh
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

</details>

## License

PerAppKeyboard is licensed under the GNU General Public License, version 3 only. See [LICENSE](LICENSE).

© 2026 Qn (Đạt Nguyễn)
