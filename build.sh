#!/usr/bin/env bash
# Builds every firmware in build.yaml locally, in ZMK's CI container, into firmware/.
# ./build.sh            build (fetches ZMK the first time only)
# ./build.sh --update   also pull the latest ZMK main first, like CI does on every run
set -euo pipefail

if [ ! -f /.dockerenv ]; then
  cd "$(dirname "$0")"
  # The named volume keeps ZMK, Zephyr and build dirs between runs, so rebuilds are incremental.
  exec docker run --rm -v "$PWD:/config" -v zmk-sofle-workspace:/workspace -w /workspace \
    zmkfirmware/zmk-build-arm:stable bash /config/build.sh "$@"
fi

mkdir -p /workspace/config /config/firmware
cp /config/config/west.yml /workspace/config/west.yml
[ -d /workspace/.west ] || west init -l /workspace/config
if [ ! -d /workspace/zmk ] || [ "${1:-}" = "--update" ]; then
  west update --fetch-opt=--filter=tree:0
fi
west zephyr-export >/dev/null

python3 - <<'EOF' >/tmp/matrix
import yaml
for b in yaml.safe_load(open("/config/build.yaml"))["include"]:
    shield = b.get("shield", "")
    name = b.get("artifact-name") or f"{shield}-{b['board'].replace('/', '_')}-zmk"
    print("|".join([b["board"], shield, b.get("snippet", ""), b.get("cmake-args", ""), name]))
EOF

while IFS='|' read -r board shield snippet cmake_args name; do
  echo "==> $name"
  # shellcheck disable=SC2086 # cmake_args holds several -D flags
  west build -p auto -s zmk/app -d "build/$name" -b "$board" ${snippet:+-S "$snippet"} -- \
    -DZMK_CONFIG=/config/config -DZMK_EXTRA_MODULES=/config ${shield:+-DSHIELD="$shield"} $cmake_args
  cp "build/$name/zephyr/zmk.uf2" "/config/firmware/$name.uf2"
done </tmp/matrix

ls -1 /config/firmware
