// Drives the Draco launcher (Draco.app started with --remote-debugging-port=9333) through Chrome DevTools, like a
// player: sign in with the test Draco account, wait for the game download, tick the account, JOUER, then follow the
// Zaap auto-login (events of the launcher's bridge). Screenshots (screencapture) at each stage, log in out/drive.txt.
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';

const OUT = process.env.OUT || 'out', EMAIL = process.env.DRACO_EMAIL, PASSWORD = process.env.DRACO_PASSWORD;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const log = (...parts) => { const line = `[${new Date().toISOString().slice(11, 19)}] ${parts.join(' ')}`; console.log(line); fs.appendFileSync(`${OUT}/drive.txt`, line + '\n'); };
const shot = name => { try { execFileSync('/usr/sbin/screencapture', ['-x', `${OUT}/${name}.png`]); log('capture', name); } catch (error) { log('capture impossible', name, error.message); } };
if (!EMAIL || !PASSWORD) { log('DRACO_EMAIL / DRACO_PASSWORD absents (secrets du dépôt)'); process.exit(2); }

async function pageTarget() {
  for (let i = 0; i < 240; i++) {
    try {
      const list = await (await fetch('http://127.0.0.1:9333/json')).json();
      const page = list.find(t => t.type === 'page' && t.url.startsWith('http://127.0.0.1:4318/'));
      if (page) return page;
      if (i % 15 === 0) log('cibles :', list.map(t => t.type + ' ' + t.url.slice(0, 60)).join(' | ') || 'aucune');
    } catch { if (i % 15 === 0) log('DevTools pas encore prêt'); }
    await sleep(1000);
  }
  throw Error('page du launcher introuvable (4 min)');
}
const page = await pageTarget(); log('page du launcher', page.url);
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
let nextId = 0; const pending = new Map();
ws.onmessage = event => { const m = JSON.parse(event.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } };
const send = (method, params = {}) => new Promise(resolve => { const id = ++nextId; pending.set(id, resolve); ws.send(JSON.stringify({id, method, params})); });
async function evaluate(expression) {
  const r = await send('Runtime.evaluate', {expression, awaitPromise: true, returnByValue: true});
  if (r.error) throw Error(r.error.message);
  if (r.result?.exceptionDetails) throw Error('JS : ' + (r.result.exceptionDetails.exception?.description || r.result.exceptionDetails.text));
  return r.result?.result?.value;
}
async function until(label, expression, timeout, every = 2000) {
  const end = Date.now() + timeout; let last = null;
  while (Date.now() < end) { try { const value = await evaluate(expression); if (value) return value; } catch (error) { last = error.message; } await sleep(every); }
  throw Error(`délai dépassé : ${label}${last ? ' (' + last + ')' : ''}`);
}
const toasts = () => evaluate("[...document.querySelectorAll('#toast > div')].map(d => (d.className ? '[erreur] ' : '') + d.textContent).join(' | ')").catch(() => '');
let ok = false;
try {
  await until('page prête', "document.readyState === 'complete' && typeof post === 'function'", 120000);
  await sleep(3000); shot('01-ouverture');
  log('état local :', await evaluate("fetch('/local/status').then(r => r.json()).then(s => JSON.stringify(s))"));

  await until('fenêtre « compte Draco »', "!!document.querySelector('#dlgMaster')?.open", 90000);
  await evaluate(`(() => { const f = document.querySelector('#formMaster'); f.querySelector('[name=email]').value = ${JSON.stringify(EMAIL)}; f.querySelector('[name=password]').value = ${JSON.stringify(PASSWORD)}; f.requestSubmit(); return true; })()`);
  log('connexion envoyée');
  await until('comptes de jeu', 'accounts.length > 0', 120000);
  log('comptes :', await evaluate("JSON.stringify(accounts.map(a => ({id: a.id, name: a.name, nickname: a.nickname})))"));
  await sleep(2000); shot('02-connecte');

  // The launcher downloads the game by itself (archive of the client, then the files that differ).
  const start = Date.now(); let shotDownload = false;
  for (;;) {
    const s = JSON.parse(await evaluate("JSON.stringify({client: client && {status: client.status, phase: client.phase, doneBytes: client.doneBytes, bytes: client.bytes, doneFiles: client.doneFiles, files: client.files, error: client.error}, installed: !!runtime?.games?.main?.installed, server: !!server?.ready, play: document.querySelector('#playSub')?.textContent})"));
    log('jeu :', JSON.stringify(s));
    if (s.client?.status === 'error') throw Error('mise à jour du jeu en erreur : ' + s.client.error);
    if (s.installed && s.server && s.client?.status === 'up-to-date') break;
    if (!shotDownload && Date.now() - start > 60000) { shot('03-telechargement'); shotDownload = true; }
    if (Date.now() - start > 30 * 60000) throw Error('jeu non installé après 30 min');
    await sleep(15000);
  }
  log(`jeu installé en ${Math.round((Date.now() - start) / 1000)} s`);

  await evaluate("selected = new Set([accounts[0].id]); saveSelection(); renderAccounts(); updatePlay(); true");
  await until('bouton JOUER actif', "!document.querySelector('#btnPlay').disabled", 60000);
  shot('04-avant-jouer');
  await evaluate("document.querySelector('#btnPlay').click(), true");
  log('JOUER cliqué');
  const begin = Date.now(), shots = [20, 45, 75, 110, 150];
  while (Date.now() - begin < 170000) {
    await sleep(5000);
    const state = await evaluate("L.getLocalRuntimeState().then(s => JSON.stringify({processes: (s.processes || []).map(p => ({pid: p.pid, account: p.id, executable: p.executable})), events: (s.nativeServices?.events || []).map(e => e.type + (e.reason ? ':' + e.reason : '') + (e.pid ? '@' + e.pid : ''))}))").catch(error => 'erreur ' + error.message);
    log('lancement :', state, '| messages :', await toasts());
    if (String(state).includes('ticket-issued')) ok = true;
    const elapsed = (Date.now() - begin) / 1000;
    while (shots.length && elapsed >= shots[0]) shot('05-jeu-' + shots.shift() + 's');
  }
  // Second launch in French: the launcher writes the client's language into Flash's shared objects (they exist
  // after the first launch), the game must open in French.
  if (ok) {
    try { execFileSync('/usr/bin/pkill', ['-f', 'Flash Player.app/Contents/MacOS/Flash Player']); } catch {}
    await until('fermeture du jeu vue par le launcher', 'L.getLocalRuntimeState().then(s => (s.processes || []).length === 0)', 60000);
    await evaluate("setLang('fr'), true"); await sleep(2000);
    await until('bouton JOUER actif (2)', "!document.querySelector('#btnPlay').disabled", 60000);
    await evaluate("document.querySelector('#btnPlay').click(), true");
    log('JOUER cliqué (français)');
    await sleep(60000); shot('06-jeu-fr-60s');
    log('lancement 2 :', await evaluate("L.getLocalRuntimeState().then(s => JSON.stringify((s.nativeServices?.events || []).map(e => e.type + (e.pid ? '@' + e.pid : ''))))").catch(error => 'erreur ' + error.message));
  }
} catch (error) {
  log('ÉCHEC :', error.message, '| messages :', await toasts());
  shot('99-echec');
}
log(ok ? 'RÉSULTAT : connexion automatique au jeu OK (jeton Zaap délivré au Flash Player)' : 'RÉSULTAT : connexion automatique non confirmée');
ws.close();
process.exit(ok ? 0 : 1);
