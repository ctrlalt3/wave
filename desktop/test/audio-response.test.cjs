const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const {audioResponse} = require('../audio-response.cjs');
test('audio devuelve rangos parciales para saltar de posición sin reiniciar la canción', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'wave-range-'));
  t.after(() => fs.rm(root, {recursive:true,force:true}));
  const file = path.join(root, 'track.wav'); await fs.writeFile(file, '0123456789');
  const request = range => new Request('https://local/track', {headers: range ? {Range: range} : {}});
  const full = await audioResponse(file, request()); assert.equal(full.status,200); assert.equal(await full.text(),'0123456789');
  const partial = await audioResponse(file, request('bytes=3-5')); assert.equal(partial.status,206); assert.equal(partial.headers.get('Content-Range'),'bytes 3-5/10'); assert.equal(await partial.text(),'345');
  const suffix = await audioResponse(file, request('bytes=-2')); assert.equal(await suffix.text(),'89');
  const tail = await audioResponse(file, request('bytes=8-')); assert.equal(await tail.text(),'89');
  for (const range of ['bytes=100-', 'bytes=5-2', 'bytes=0-1,3-4', 'bytes=-0', 'bytes=-']) assert.equal((await audioResponse(file, request(range))).status,416);
  const head = await audioResponse(file, new Request('https://local/track',{method:'HEAD'})); assert.equal(head.headers.get('Content-Length'),'10'); assert.equal(await head.text(),'');
});
