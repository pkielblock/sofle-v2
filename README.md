# sofle-v2

ZMK firmware for my wireless Sofle v2: two nice!nano v2 controllers, 128x32 OLED screens, one rotary encoder per half.

- **Keymap:** edited live in [ZMK Studio](https://zmk.studio). `config/sofle.keymap` is a snapshot of it.
- **Screens:** ZMK's stock status screen. The [zmk-nice-oled](https://github.com/mctechnology17/zmk-nice-oled) version (pet, typing speed, gem animation) is on the `nice-oled` branch: it builds, but it froze the keyboard on first flash, so it isn't on `main` yet.
- **ZMK:** `main` (Zephyr 4.1).

## Flashing

GitHub Actions builds the firmware on every push.

1. Open the latest green run under **Actions** and download the `firmware` artifact. Unzip it.
2. Plug a half in by USB and double-tap its reset button. A drive called `NICENANO` appears.
3. Copy that half's file onto the drive: `sofle_left-nice_nano@2.0.0__zmk-zmk.uf2` to the left half, `sofle_right-…uf2` to the right. It reboots by itself. macOS may warn that the disk wasn't ejected properly; that's expected.
4. Do the same for the other half.

- **Screen or firmware changes:** flash both halves. Each half draws its own screen.
- **Keymap changes:** you don't need to flash. Use ZMK Studio.

Flashing keeps your ZMK Studio keymap, the pairing between the halves and your Bluetooth pairings. All of that lives in the settings storage, not in the firmware. Don't flash a `settings_reset` firmware unless you want to wipe all of it. If you do, the keyboard falls back to `config/sofle.keymap`, and you'll need to re-pair the halves and your devices.

## Keymap (ZMK Studio)

1. Plug the **left** half in by USB.
2. Open <https://zmk.studio> in Chrome and connect. The keyboard is unlocked (`CONFIG_ZMK_STUDIO_LOCKING=n`).
3. Change keys or layers, then click **Save**.

Studio saves to the left half's flash only. To keep this repo in sync, run this with the left half still plugged in:

```sh
cd tools
bun install
bun run sync-keymap   # reads the live keymap over USB and rewrites config/sofle.keymap
```

Then commit `config/sofle.keymap`. The script only reads from the keyboard; it never changes it. It fails loudly if it sees a key or behavior it can't translate.

Studio can't edit the encoders (`sensor-bindings`: volume on the left, page up/down on the right), combos or macros. Change those in `config/sofle.keymap` and flash the left half.

## Screens

`main` uses ZMK's stock status screen (`CONFIG_ZMK_DISPLAY=y` in `config/sofle.conf`).

The `nice-oled` branch swaps in [zmk-nice-oled](https://github.com/mctechnology17/zmk-nice-oled) with the gem animation on the right half. It uses [tokyo2006's port](https://github.com/mctechnology17/zmk-nice-oled/pull/37) to ZMK `main`, pinned to a commit, because upstream still targets ZMK v0.3 (LVGL 8). It builds, but the first flash froze both halves: no keys, no battery, and ZMK Studio stopped responding. Don't merge it until that's fixed.

## Layout

| File | Purpose |
|---|---|
| `build.yaml` | What Actions builds: left half (with ZMK Studio) and right half |
| `config/west.yml` | ZMK and module versions |
| `config/sofle.conf` | Screen, encoder, Bluetooth and Studio settings |
| `config/sofle.keymap` | Snapshot of the ZMK Studio keymap, plus encoder bindings |
| `tools/` | ZMK Studio → `sofle.keymap` sync script |

Based on [tupinikeebs/sofle-zmk_oled](https://github.com/tupinikeebs/sofle-zmk_oled).
