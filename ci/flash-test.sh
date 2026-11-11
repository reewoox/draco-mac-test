#!/bin/bash
# Flash Player 32 (Adobe, macOS) + Draco client, without the launcher: does the client load, how does the player
# take the start SWF (command line or Launch Services), where are the shared objects, what does ps print.
set -u
OUT="$PWD/out"; mkdir -p "$OUT"
D="$HOME/DracoTest"; mkdir -p "$D"
API="${DRACO_API:-https://ml.tail76e554.ts.net:8443}"
log() { echo "=== $*" | tee -a "$OUT/steps.txt"; }

log "Flash Player 32 (Adobe)"
curl -sSfL -o "$D/fp.dmg" https://fpdownload.macromedia.com/pub/flashplayer/updaters/32/flashplayer_32_sa.dmg
shasum -a 256 "$D/fp.dmg" | tee -a "$OUT/steps.txt"
MNT=$(mktemp -d)
hdiutil attach -nobrowse -readonly -noautoopen -noverify -mountpoint "$MNT" "$D/fp.dmg"
ls -la "$MNT" | tee -a "$OUT/steps.txt"
mkdir -p "$D/flash"; ditto "$MNT/Flash Player.app" "$D/flash/Flash Player.app"
hdiutil detach "$MNT" -force
APP="$D/flash/Flash Player.app"; BIN="$APP/Contents/MacOS/Flash Player"
file "$BIN" | tee -a "$OUT/steps.txt"
codesign -dv --verbose=2 "$APP" 2>&1 | head -12 | tee -a "$OUT/steps.txt"
spctl -a -vv "$APP" 2>&1 | tee -a "$OUT/steps.txt" || true

log "Client Draco (archive publiée par le serveur)"
START=$(date +%s)
curl -sSfL --retry 3 -o "$D/client.zip" "$API/client-archive.zip"
echo "client.zip : $(stat -f %z "$D/client.zip") octets en $(( $(date +%s) - START )) s" | tee -a "$OUT/steps.txt"
mkdir -p "$D/client"; tar -xf "$D/client.zip" -C "$D/client"
RC="$D/client/resources/app/retroclient"
ls "$RC" | tee -a "$OUT/steps.txt"
python3 - "$RC/Dofus.exe" "$RC/Draco.swf" <<'EOF'
import struct, sys
data = open(sys.argv[1], 'rb').read()
magic, length = struct.unpack('<II', data[-8:])
assert magic == 0xFA123456, hex(magic)
open(sys.argv[2], 'wb').write(data[-8 - length:-8])
print('stub', length, 'octets')
EOF
TRUST="$HOME/Library/Preferences/Macromedia/Flash Player/#Security/FlashPlayerTrust"
mkdir -p "$TRUST"; echo "$RC" > "$TRUST/draco.cfg"

log "A : binaire lancé directement avec le SWF en argument"
"$BIN" "$RC/Draco.swf" > "$OUT/a-stdout.txt" 2>&1 &
PA=$!
sleep 35
screencapture -x "$OUT/a.png" || true
ps -axo pid=,comm= | grep -i "flash" | tee "$OUT/a-ps.txt"
find "$HOME/Library/Preferences/Macromedia" -maxdepth 9 2>/dev/null | tee "$OUT/a-macromedia.txt" | head -40
kill "$PA" 2>/dev/null; sleep 3; pkill -f "Flash Player.app/Contents/MacOS/Flash Player" || true; sleep 2

log "B : open -n -a (Launch Services)"
open -n -a "$APP" "$RC/Draco.swf"
sleep 45
screencapture -x "$OUT/b.png" || true
ps -axo pid=,comm= | grep -i "flash" | tee "$OUT/b-ps.txt"
PB=$(ps -axo pid=,comm= | awk -v b="$BIN" '{p=$1; $1=""; sub(/^ /,""); if ($0==b) print p}' | head -1)
echo "PID (comm = binaire exact) : ${PB:-aucun}" | tee -a "$OUT/steps.txt"
lsof -nP -a -iTCP -p "${PB:-1}" 2>/dev/null | tee "$OUT/b-lsof.txt"
find "$HOME/Library/Preferences/Macromedia" -maxdepth 9 2>/dev/null | tee "$OUT/b-macromedia.txt" | head -60
sleep 20
screencapture -x "$OUT/b2.png" || true
pkill -f "Flash Player.app/Contents/MacOS/Flash Player" || true
log "fin"
