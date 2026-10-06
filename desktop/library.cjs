const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const AUDIO = new Set(['.mp3', '.m4a', '.aac', '.wav', '.flac', '.ogg', '.opus', '.aiff', '.aif', '.webm']);
const STATE_FILE = '.wave-library.json';
function serverURL(value) {
  const url = new URL(value);
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) throw new Error('Introduce una dirección HTTP o HTTPS sin credenciales.');
  url.hash = ''; url.search = ''; if (!url.pathname.endsWith('/')) url.pathname += '/'; return url.href;
}
function inside(root, target) {
  const relative = path.relative(root, target);
  return relative !== '' && !relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative);
}
function emptyState() { return {hidden: [], orders: {}}; }
async function readState(root) {
  try {
    const file = path.join(root, STATE_FILE); const info = await fs.lstat(file);
    if (info.isSymbolicLink() || info.size > 5 * 1024 * 1024) throw new Error('El archivo de organización de Wave no es válido.');
    const value = JSON.parse(await fs.readFile(file, 'utf8'));
    return {hidden: Array.isArray(value.hidden) ? value.hidden.filter(x => typeof x === 'string') : [], orders: value.orders && typeof value.orders === 'object' && !Array.isArray(value.orders) ? value.orders : {}};
  } catch (error) { if (error.code === 'ENOENT') return emptyState(); throw new Error('No se pudo leer la organización de esta biblioteca.'); }
}
async function writeState(root, state) {
  const temp = path.join(root, `.wave-state-${crypto.randomUUID()}.tmp`);
  try { await fs.writeFile(temp, JSON.stringify(state, null, 2), {flag: 'wx', mode: 0o600}); await fs.rename(temp, path.join(root, STATE_FILE)); }
  finally { await fs.rm(temp, {force: true}); }
}
async function scanLibrary(folder) {
  const root = await fs.realpath(folder); const tracks = []; const files = new Map(); const folders = []; let skipped = 0;
  async function walk(dir, parent = null) {
    let entries;
    try { entries = await fs.readdir(dir, {withFileTypes: true}); } catch (error) { if (dir === root) throw error; skipped++; return 0; }
    const relative = path.relative(root, dir).split(path.sep).join('/');
    const record = {path: relative, parent, name: path.basename(dir), count: 0, directCount: 0}; folders.push(record);
    for (const entry of entries) {
      if (entry.name.startsWith('.') || entry.isSymbolicLink()) continue;
      const file = path.join(dir, entry.name);
      if (entry.isDirectory()) { record.count += await walk(file, relative); continue; }
      if (!entry.isFile() || !AUDIO.has(path.extname(file).toLowerCase())) continue;
      let info; try { info = await fs.stat(file); } catch { skipped++; continue; }
      const relPath = path.relative(root, file).split(path.sep).join('/');
      const id = crypto.createHash('sha256').update(root + '\0' + relPath).digest('hex'); files.set(id, file);
      tracks.push({id, relPath, filename: entry.name, name: path.basename(file, path.extname(file)), folder: relative || path.basename(root), folderPath: relative, format: path.extname(file).slice(1).toUpperCase(), size: info.size, modified: info.mtimeMs, source: 'local', url: `wave-audio://library/${id}`});
      record.count++; record.directCount++;
    }
    return record.count;
  }
  await walk(root);
  tracks.sort((a,b) => a.folder.localeCompare(b.folder) || a.name.localeCompare(b.name));
  folders.sort((a,b) => a.path.localeCompare(b.path));
  return {root, tracks, folders, files, skipped, state: await readState(root)};
}
async function resolveTrack(library, id) {
  const file = library.files.get(id); if (!file) throw new Error('Archivo no autorizado.');
  const real = await fs.realpath(file);
  if (!inside(library.root, real) || !AUDIO.has(path.extname(real).toLowerCase())) throw new Error('Archivo fuera de la biblioteca.');
  if (!(await fs.stat(real)).isFile()) throw new Error('No es una canción.'); return real;
}
async function resolveDirectory(library, relative) {
  if (typeof relative !== 'string' || !library.folders.some(folder => folder.path === relative)) throw new Error('Carpeta no autorizada.');
  const real = await fs.realpath(path.join(library.root, relative));
  if ((real !== library.root && !inside(library.root, real)) || !(await fs.stat(real)).isDirectory()) throw new Error('Carpeta fuera de la biblioteca.'); return real;
}
async function editState(library, operation) {
  const state = await readState(library.root); const valid = new Set(library.tracks.map(track => track.relPath));
  if (operation.action === 'hidden') {
    if (!Array.isArray(operation.paths) || !operation.paths.length || operation.paths.some(p => !valid.has(p)) || typeof operation.hidden !== 'boolean') throw new Error('Selección no válida.');
    const hidden = new Set(state.hidden); for (const file of operation.paths) operation.hidden ? hidden.add(file) : hidden.delete(file); state.hidden = [...hidden];
  } else if (operation.action === 'order') {
    if (typeof operation.scope !== 'string' || !Array.isArray(operation.paths) || operation.paths.some(p => !valid.has(p)) || new Set(operation.paths).size !== operation.paths.length) throw new Error('Orden no válido.');
    if (operation.scope !== '*' && !library.folders.some(folder => folder.path === operation.scope)) throw new Error('Carpeta no válida.');
    state.orders = {...state.orders, [operation.scope]: operation.paths};
  } else throw new Error('Operación no válida.');
  await writeState(library.root, state); library.state = state; return state;
}
async function copyInto(entries, destination) {
  const dest = await fs.realpath(destination); if (!(await fs.stat(dest)).isDirectory()) throw new Error('El destino no es una carpeta.');
  const results = [];
  for (const entry of entries) {
    let temp;
    try {
      const source = await fs.realpath(entry.file);
      if (!inside(entry.root, source) || !AUDIO.has(path.extname(source).toLowerCase())) throw new Error('La canción ya no está en su biblioteca.');
      const name = path.basename(entry.file); const target = path.join(dest, name);
      let existed = false;
      try { const info = await fs.lstat(target); existed = true; if (info.isDirectory()) throw new Error('El destino contiene una carpeta con ese nombre.'); if (await fs.realpath(target) === source) { results.push({id: entry.id, name, status: 'same'}); continue; } } catch (error) { if (error.code !== 'ENOENT') throw error; }
      temp = path.join(dest, `.wave-copy-${crypto.randomUUID()}.tmp`);
      await fs.copyFile(source, temp, require('node:fs').constants.COPYFILE_EXCL);
      await fs.rename(temp, target); temp = null;
      results.push({id: entry.id, name, status: existed ? 'overwritten' : 'copied'});
    } catch (error) { results.push({id: entry.id, name: entry.name, status: 'error', error: error.message}); }
    finally { if (temp) await fs.rm(temp, {force: true}); }
  }
  return {destination: dest, results};
}
module.exports = {serverURL, inside, scanLibrary, resolveTrack, resolveDirectory, editState, copyInto, readState};
