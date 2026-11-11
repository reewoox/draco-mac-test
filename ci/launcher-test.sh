#!/bin/bash
# Draco.app like a player: install from the zip, open it, sign in with the test account (secrets), let it download the
# game and Adobe's Flash Player, JOUER, then check the Zaap auto-login (ci/drive.mjs). Logs and screenshots in out/.
set -u
OUT="$PWD/out"; mkdir -p "$OUT"; export OUT
log() { echo "=== $*" | tee -a "$OUT/steps.txt"; }

log "Téléchargement de Draco-Launcher-Mac.zip"
curl -sSfL -o "$HOME/Draco-Launcher-Mac.zip" "$ZIP_URL"
ls -la "$HOME/Draco-Launcher-Mac.zip" | tee -a "$OUT/steps.txt"

log "Installation (décompression comme l'utilitaire d'archive, puis dans Applications)"
mkdir -p "$HOME/Applications"
ditto -x -k "$HOME/Draco-Launcher-Mac.zip" "$HOME/Applications"
APP="$HOME/Applications/Draco.app"
ls -la "$APP/Contents" "$APP/Contents/MacOS" "$APP/Contents/Frameworks/Electron Framework.framework" | tee -a "$OUT/steps.txt"
file "$APP/Contents/MacOS/Draco" | tee -a "$OUT/steps.txt"
plutil -p "$APP/Contents/Info.plist" > "$OUT/info-plist.txt" 2>&1
codesign -dv "$APP" 2>&1 | tee -a "$OUT/steps.txt" || true
# What Gatekeeper tells a player whose browser marked the download (quarantine): assessment only.
cp -R "$APP" "$HOME/q-Draco.app"
xattr -w com.apple.quarantine "0083;$(printf %x "$(date +%s)");Safari;" "$HOME/q-Draco.app"
spctl -a -vvv -t exec "$HOME/q-Draco.app" 2>&1 | tee -a "$OUT/steps.txt" || true
rm -rf "$HOME/q-Draco.app"

log "Lancement de Draco.app"
open -n -a "$APP" --stdout "$OUT/draco-stdout.txt" --stderr "$OUT/draco-stderr.txt" --args --remote-debugging-port=9333 \
  || { "$APP/Contents/MacOS/Draco" --remote-debugging-port=9333 > "$OUT/draco-stdout.txt" 2> "$OUT/draco-stderr.txt" & }
sleep 5
node ci/drive.mjs; RESULT=$?

log "Journaux"
R="$HOME/Library/Application Support/Draco"
ls -la "$R" "$R/flash" "$R/work" "$R/client/Abrak/Retro/resources/app/retroclient" 2>&1 | head -80 | tee -a "$OUT/steps.txt"
cp "$R"/work/*.log "$OUT/" 2>/dev/null || true
cp "$R/profile-local/local-client-processes.json" "$OUT/" 2>/dev/null || true
ps -axo pid=,comm= | grep -iE "draco|flash|electron" | tee "$OUT/ps.txt"
lsof -nP -iTCP -sTCP:ESTABLISHED 2>/dev/null | grep -iE "flash|draco|electron" | tee "$OUT/lsof.txt"
find "$HOME/Library/Preferences/Macromedia" -maxdepth 9 2>/dev/null | head -80 > "$OUT/macromedia.txt"
cat "$HOME/Library/Preferences/Macromedia/Flash Player/#Security/FlashPlayerTrust/draco.cfg" >> "$OUT/steps.txt" 2>/dev/null || true
ls -la "$HOME/Library/Logs/DiagnosticReports" 2>/dev/null | tail -20 > "$OUT/crash-reports.txt"
cp "$HOME"/Library/Logs/DiagnosticReports/*Draco* "$HOME"/Library/Logs/DiagnosticReports/*Flash* "$OUT/" 2>/dev/null || true
screencapture -x "$OUT/zz-fin.png" || true
exit $RESULT
