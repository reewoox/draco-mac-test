#!/bin/bash
# Flash "Local Storage: Allow local to store information on your computer?" prompt: which preset settings of the
# "local" domain (macromedia.com/support/flashplayer/sys) let the Draco client store its data without asking.
set -u
OUT="$PWD/out"; mkdir -p "$OUT"
D="$HOME/DracoTest"; mkdir -p "$D"
API="${DRACO_API:-https://ml.tail76e554.ts.net:8443}"
FP="$HOME/Library/Preferences/Macromedia/Flash Player"; SYS="$FP/macromedia.com/support/flashplayer/sys"
log() { echo "=== $*" | tee -a "$OUT/steps.txt"; }

curl -sSfL -o "$D/fp.dmg" https://fpdownload.macromedia.com/pub/flashplayer/updaters/32/flashplayer_32_sa.dmg
MNT=$(mktemp -d); hdiutil attach -nobrowse -readonly -noautoopen -noverify -mountpoint "$MNT" "$D/fp.dmg" > /dev/null
mkdir -p "$D/flash"; ditto "$MNT/Flash Player.app" "$D/flash/Flash Player.app"; hdiutil detach "$MNT" -force > /dev/null
BIN="$D/flash/Flash Player.app/Contents/MacOS/Flash Player"
for attempt in 1 2 3 4 5; do
  curl -sSfL -C - --retry 3 -o "$D/client.zip" "$API/client-archive.zip" && break
  log "téléchargement du client interrompu, reprise ($attempt)"
done
log "client.zip : $(stat -f %z "$D/client.zip") octets"
mkdir -p "$D/client"; tar -xf "$D/client.zip" -C "$D/client"
RC="$D/client/resources/app/retroclient"
python3 - "$RC/Dofus.exe" "$RC/Draco.swf" <<'EOF'
import struct, sys
data = open(sys.argv[1], 'rb').read(); magic, length = struct.unpack('<II', data[-8:])
open(sys.argv[2], 'wb').write(data[-8 - length:-8])
EOF
mkdir -p "$FP/#Security/FlashPlayerTrust"; echo "$RC" > "$FP/#Security/FlashPlayerTrust/draco.cfg"

run() { # $1 = name; settings already written
  rm -rf "$FP/#SharedObjects"
  "$BIN" "$RC/Draco.swf" > /dev/null 2>&1 &
  local pid=$!
  sleep 50
  screencapture -x "$OUT/$1.png" || true
  { echo "--- $1 : fichiers .sol"; find "$FP/#SharedObjects" -name '*.sol' -exec stat -f '%z %N' {} \; 2>/dev/null | sed "s|$FP/||"; } | tee -a "$OUT/steps.txt"
  kill "$pid" 2>/dev/null; sleep 3; pkill -f "Flash Player.app/Contents/MacOS/Flash Player"; sleep 2
  { echo "--- $1 : réglages après"; python3 ci/sol.py dump "$SYS/settings.sol" "$SYS/#local/settings.sol" 2>&1; } | tee -a "$OUT/steps.txt"
}

log "v0 : profil Flash neuf"
rm -rf "$SYS"; run v0
log "v1 : #local klimit = -2 (réglage du PC Windows de Draco)"
rm -rf "$SYS"; mkdir -p "$SYS/#local"
python3 ci/sol.py write "$SYS/#local/settings.sol" local/settings allow=false always=false klimit=-2 allowsecure=false alwayssecure=false
run v1
log "v2 : #local klimit = 1048576 Ko"
rm -rf "$SYS"; mkdir -p "$SYS/#local"
python3 ci/sol.py write "$SYS/#local/settings.sol" local/settings allow=false always=false klimit=1048576 allowsecure=false alwayssecure=false
run v2
log "v3 : réglage global defaultklimit = -2"
rm -rf "$SYS"; mkdir -p "$SYS"
python3 ci/sol.py write "$SYS/settings.sol" settings defaultklimit=-2 defaultalways=false
run v3
log "fin"
