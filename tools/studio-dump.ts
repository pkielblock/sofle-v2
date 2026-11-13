// Read-only dump of the live ZMK Studio keymap over USB serial. Sends only get/list requests, never set/save.
import { create_rpc_connection, call_rpc } from "@zmkfirmware/zmk-studio-ts-client";
import { openSync, createReadStream, createWriteStream } from "node:fs";
import { execSync } from "node:child_process";
import { Readable, Writable } from "node:stream";

const dev = process.argv[2];
if (!dev) throw new Error("usage: bun studio-dump.ts /dev/cu.usbmodemXXXX");
execSync(`stty -f ${dev} raw -echo 115200`);
const fd = openSync(dev, "r+");
const abortController = new AbortController();
const transport = {
  label: dev,
  abortController,
  readable: Readable.toWeb(createReadStream("", { fd, autoClose: false })) as ReadableStream<Uint8Array>,
  writable: Writable.toWeb(createWriteStream("", { fd, autoClose: false })) as WritableStream<Uint8Array>,
};
const conn = create_rpc_connection(transport, { signal: abortController.signal });
const rpc = async (req: any) => {
  const r = await Promise.race([call_rpc(conn, req), Bun.sleep(5000).then(() => { throw new Error("timeout: is this the left half with Studio firmware?"); })]);
  return r;
};

const info = (await rpc({ core: { getDeviceInfo: true } })).core?.getDeviceInfo;
const keymap = (await rpc({ keymap: { getKeymap: true } })).keymap?.getKeymap;
const ids = (await rpc({ behaviors: { listAllBehaviors: true } })).behaviors?.listAllBehaviors?.behaviors ?? [];
const behaviors: Record<number, string> = {};
for (const id of ids) behaviors[id] = (await rpc({ behaviors: { getBehaviorDetails: { behaviorId: id } } })).behaviors!.getBehaviorDetails!.displayName;

console.log(JSON.stringify({ device: info?.name, behaviors, keymap }, null, 1));
abortController.abort();
process.exit(0);
