const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const {serverURL, inside, scanLibrary, resolveTrack} = require('../library.cjs');
test('normaliza subrutas y rechaza protocolos y credenciales', () => {
  assert.equal(serverURL('https://example.com/wave'), 'https://example.com/wave/');
  assert.equal(serverURL('http://localhost:5002'), 'http://localhost:5002/');
  for (const input of ['file:///etc/passwd', 'javascript:alert(1)', 'https://user:secret@example.com']) assert.throws(() => serverURL(input));
});
test('la biblioteca incluye audio anidado y excluye enlaces y archivos ajenos', async t => {
  const base = await fs.mkdtemp(path.join(os.tmpdir(), 'wave-test-'));
  t.after(() => fs.rm(base, {recursive: true, force: true}));
  const root = path.join(base, 'Music'); await fs.mkdir(path.join(root, 'Album'), {recursive: true});
  await fs.writeFile(path.join(root, 'Album', 'Song.MP3'), 'audio');
  await fs.writeFile(path.join(root, 'notes.txt'), 'private');
  await fs.writeFile(path.join(base, 'outside.mp3'), 'outside');
  await fs.symlink(path.join(base, 'outside.mp3'), path.join(root, 'link.mp3'));
  const library = await scanLibrary(root);
  assert.equal(library.tracks.length, 1); assert.equal(library.tracks[0].folder, 'Album');
  const track = library.tracks[0];
  assert.equal(await resolveTrack(library, track.id), path.join(root, 'Album', 'Song.MP3'));
  await assert.rejects(resolveTrack(library, '../notes.txt'));
  await fs.unlink(path.join(root, 'Album', 'Song.MP3'));
  await fs.symlink(path.join(base, 'outside.mp3'), path.join(root, 'Album', 'Song.MP3'));
  await assert.rejects(resolveTrack(library, track.id));
  assert.equal(inside(root, path.join(base, 'Music-other', 'song.mp3')), false);
});
test('una carpeta inaccesible falla y una carpeta vacía es válida', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'wave-empty-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  assert.equal((await scanLibrary(root)).tracks.length, 0);
  await assert.rejects(scanLibrary(path.join(root, 'missing')));
});
