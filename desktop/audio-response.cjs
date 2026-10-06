const fs = require('node:fs');
const {stat} = require('node:fs/promises');
const {Readable} = require('node:stream');
const path = require('node:path');
const TYPES = {'.mp3':'audio/mpeg','.m4a':'audio/mp4','.aac':'audio/aac','.wav':'audio/wav','.flac':'audio/flac','.ogg':'audio/ogg','.opus':'audio/ogg','.aiff':'audio/aiff','.aif':'audio/aiff','.webm':'audio/webm'};
async function audioResponse(file, request) {
  const info = await stat(file);
  if (!info.isFile()) return new Response(null, {status: 404});
  const size = info.size;
  const headers = {'Content-Type': TYPES[path.extname(file).toLowerCase()] || 'application/octet-stream', 'Accept-Ranges': 'bytes', 'Cache-Control': 'no-store'};
  let start = 0, end = size - 1, status = 200;
  const range = request.headers.get('range');
  if (range) {
    const match = /^bytes=(\d*)-(\d*)$/.exec(range);
    if (match && (match[1] || match[2])) {
      if (!match[1]) start = Math.max(0, size - Number(match[2]));
      else { start = Number(match[1]); if (match[2]) end = Math.min(end, Number(match[2])); }
    }
    if (!match || (!match[1] && !match[2]) || !Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start > end || start >= size || (!match[1] && Number(match[2]) === 0)) {
      return new Response(null, {status: 416, headers: {...headers, 'Content-Range': `bytes */${size}`}});
    }
    status = 206; headers['Content-Range'] = `bytes ${start}-${end}/${size}`;
  }
  headers['Content-Length'] = String(Math.max(0, end - start + 1));
  if (request.method === 'HEAD' || size === 0) return new Response(null, {status, headers});
  const stream = fs.createReadStream(file, {start, end});
  const abort = () => stream.destroy();
  request.signal.addEventListener('abort', abort, {once: true});
  stream.once('close', () => request.signal.removeEventListener('abort', abort));
  return new Response(Readable.toWeb(stream), {status, headers});
}
module.exports = {audioResponse};
