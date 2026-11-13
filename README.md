# sofle-v2

ZMK firmware for my wireless Sofle v2: two nice!nano v2 controllers, 128x32 OLED screens, one rotary encoder per half.

- **Keymap:** edited live in [ZMK Studio](https://zmk.studio). `config/sofle.keymap` is a snapshot of it.
- **Screens:** [zmk-nice-oled](https://github.com/mctechnology17/zmk-nice-oled). The left half shows connection, battery, typing speed, the animated pet and the current layer. The right half shows its connection, its battery and the gem animation.
- **ZMK:** `main` (Zephyr 4.1).

## Flashing

GitHub Actions builds the firmware on every push.

1. Open the latest green run under **Actions** and download the `firmware` artifact. Unzip it.
2. Plug a half in by USB and double-tap its reset button. A drive called `NICENANO` appears.
3. Copy that half's file onto the drive: `sofle_left nice_oled-nice_nano@2.0.0__zmk-zmk.uf2` to the left half, `sofle_right nice_oled-…uf2` to the right. It reboots by itself. macOS may warn that the disk wasn't ejected properly; that's expected.
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

Screen options live in `config/sofle.conf`. The full list is in the [zmk-nice-oled README](https://github.com/mctechnology17/zmk-nice-oled). Current settings:

| Option | Value | Effect |
|---|---|---|
| `CONFIG_ZMK_DISPLAY_STATUS_SCREEN_CUSTOM` | `y` | Use zmk-nice-oled instead of the stock screen |
| `CONFIG_NICE_OLED_WIDGET_ANIMATION_PERIPHERAL_CAT` | `n` | No cat on the right half |
| `CONFIG_NICE_OLED_WIDGET_ANIMATION_PERIPHERAL_GEM` | `y` | Gem animation on the right half |

The module comes from [tokyo2006's port](https://github.com/mctechnology17/zmk-nice-oled/pull/37) to ZMK `main`, pinned to a commit in `config/west.yml`. Upstream's `main` still targets ZMK v0.3 (LVGL 8) and doesn't build here. Once that PR merges, switch the remote back to `mctechnology17` and `revision: main`.

## Layout

| File | Purpose |
|---|---|
| `build.yaml` | What Actions builds: left half (with ZMK Studio) and right half |
| `config/west.yml` | ZMK and module versions |
| `config/sofle.conf` | Screen, encoder, Bluetooth and Studio settings |
| `config/sofle.keymap` | Snapshot of the ZMK Studio keymap, plus encoder bindings |
| `tools/` | ZMK Studio → `sofle.keymap` sync script |

Based on [tupinikeebs/sofle-zmk_oled](https://github.com/tupinikeebs/sofle-zmk_oled).
