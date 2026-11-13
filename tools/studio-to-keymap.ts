// Rewrites the bindings blocks of sofle.keymap from the Studio dump. Usage: bun studio-to-keymap.ts studio.json ../config/sofle.keymap
const [dumpPath, keymapPath] = process.argv.slice(2);
const j = await Bun.file(dumpPath).json();
let src = await Bun.file(keymapPath).text();

const KEY: Record<number, string> = {
  0x28: "RET", 0x29: "ESC", 0x2a: "BSPC", 0x2b: "TAB", 0x2c: "SPACE", 0x2d: "MINUS", 0x2e: "EQUAL", 0x2f: "LBKT", 0x30: "RBKT",
  0x31: "BSLH", 0x33: "SEMI", 0x34: "SQT", 0x35: "GRAVE", 0x36: "COMMA", 0x37: "DOT", 0x38: "FSLH", 0x39: "CAPS",
  0x46: "PSCRN", 0x47: "SLCK", 0x48: "PAUSE_BREAK", 0x49: "INS", 0x4a: "HOME", 0x4b: "PG_UP", 0x4c: "DEL", 0x4d: "END", 0x4e: "PG_DN",
  0x4f: "RIGHT", 0x50: "LEFT", 0x51: "DOWN", 0x52: "UP", 0x65: "K_CMENU", 0x7a: "K_UNDO", 0x7b: "K_CUT", 0x7c: "K_COPY", 0x7d: "K_PASTE",
  0xe0: "LCTRL", 0xe1: "LSHFT", 0xe2: "LALT", 0xe3: "LGUI", 0xe4: "RCTRL", 0xe5: "RSHFT", 0xe6: "RALT", 0xe7: "RGUI",
};
for (let i = 0; i < 26; i++) KEY[0x04 + i] = String.fromCharCode(65 + i);
for (let i = 1; i <= 9; i++) KEY[0x1d + i] = "N" + i;
KEY[0x27] = "N0";
for (let i = 1; i <= 12; i++) KEY[0x39 + i] = "F" + i;
const CONSUMER: Record<number, string> = { 0xe2: "C_MUTE", 0xe9: "C_VOL_UP", 0xea: "C_VOL_DN", 0xcd: "C_PP", 0xb5: "C_NEXT", 0xb6: "C_PREV" };
const MODS = ["LC", "LS", "LA", "LG", "RC", "RS", "RA", "RG"];
const MODNAME = ["LCTRL", "LSHFT", "LALT", "LGUI", "RCTRL", "RSHFT", "RALT", "RGUI"];

function key(p: number): string {
  const mods = (p >>> 24) & 0xff, page = (p >>> 16) & 0xff, id = p & 0xffff;
  const base = page === 7 ? KEY[id] : page === 0x0c ? CONSUMER[id] : undefined;
  if (!base) throw new Error(`no name for usage 0x${p.toString(16)}`);
  return MODS.reduce((s, m, i) => (mods & (1 << i) ? `${m}(${s})` : s), base);
}
const mod = (p: number) => MODNAME[Math.log2(p)] ?? (() => { throw new Error(`mod ${p}`); })();
const BT = ["BT_CLR", "BT_NXT", "BT_PRV", "BT_SEL", "BT_CLR_ALL", "BT_DISC"];

const names: Record<number, string> = j.behaviors;
const LAYER = ["BASE", "LOWER", "RAISE", "ADJUST"];
function binding(b: any, original: string): string {
  const n = names[b.behaviorId];
  switch (n) {
    case "Key Press": return `&kp ${key(b.param1)}`;
    case "Transparent": return "&trans";
    case "None": return "&none";
    case "Momentary Layer": return `&mo ${LAYER[b.param1] ?? b.param1}`;
    case "Toggle Layer": return `&tog ${LAYER[b.param1] ?? b.param1}`;
    case "To Layer": return `&to ${LAYER[b.param1] ?? b.param1}`;
    case "Sticky Layer": return `&sl ${b.param1}`;
    case "Layer-Tap": return `&lt ${b.param1} ${key(b.param2)}`;
    case "Mod-Tap": return `&mt ${mod(b.param1)} ${key(b.param2)}`;
    case "Sticky Key": return `&sk ${key(b.param1)}`;
    case "Key Toggle": return `&kt ${key(b.param1)}`;
    case "Grave/Escape": return "&gresc";
    case "Key Repeat": return "&key_repeat";
    case "Caps Word": return "&caps_word";
    case "Bootloader": return "&bootloader";
    case "Reset": return "&sys_reset";
    case "Studio Unlock": return "&studio_unlock";
    case "External Power": return `&ext_power ${["EP_OFF", "EP_ON", "EP_TOG"][b.param1]}`;
    case "Output Selection": return `&out ${["OUT_TOG", "OUT_USB", "OUT_BLE"][b.param1]}`;
    case "Bluetooth": return b.param1 === 3 ? `&bt BT_SEL ${b.param2}` : `&bt ${BT[b.param1]}`;
  }
  // Behaviors not compiled into this firmware (e.g. &rgb_ug with RGB off) come back as 0xffff: keep the file's binding.
  if (b.behaviorId === 0xffff && original) return original;
  throw new Error(`unhandled behavior ${b.behaviorId} (${n})`);
}

const ROWS = [12, 12, 12, 14, 10];
const blocks = [...src.matchAll(/bindings = <\n([\s\S]*?)\n\s*>;/g)].filter((m) => !m[0].startsWith("sensor"));
if (blocks.length !== j.keymap.layers.length) throw new Error(`file has ${blocks.length} layers, Studio has ${j.keymap.layers.length}`);
for (let li = blocks.length - 1; li >= 0; li--) {
  const m = blocks[li], layer = j.keymap.layers[li];
  const orig = m[1].trim().split(/\s+(?=&)/);
  if (layer.bindings.length !== 60 || orig.length !== 60) throw new Error(`layer ${li}: expected 60 keys`);
  const out = layer.bindings.map((b: any, i: number) => binding(b, orig[i]));
  const w = Math.max(...out.map((s: string) => s.length)) + 1;
  let i = 0, lines: string[] = [];
  for (const [r, n] of ROWS.entries()) {
    const row = out.slice(i, i + n).map((s: string) => s.padEnd(w)).join("").trimEnd();
    lines.push((r === 4 ? " ".repeat(w * 2) : "") + row);
    i += n;
  }
  src = src.slice(0, m.index!) + `bindings = <\n${lines.join("\n")}\n            >;` + src.slice(m.index! + m[0].length);
}
await Bun.write(keymapPath, src);
console.log("ok");
