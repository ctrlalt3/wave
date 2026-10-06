const {serverURL} = require('./library.cjs');
function encodePath(value) { return value.split('/').map(encodeURIComponent).join('/'); }
function safePath(value) { return typeof value === 'string' && value.length > 0 && value.length < 2000 && !value.startsWith('/') && !value.includes('\\') && !value.split('/').some(part => part === '..' || part === '.'); }
class ServerLibrary {
  constructor(base, fetcher = fetch) { this.base = serverURL(base); this.fetch = fetcher; this.folders = []; this.tracks = new Map(); this.state = {hidden: [], orders: {}}; }
  url(relative) { return new URL(relative.replace(/^\/+/, ''), this.base).href; }
  async request(endpoint, options = {}) {
    const response = await this.fetch(this.url(endpoint), {...options, signal: options.signal || AbortSignal.timeout(endpoint.startsWith('api/cloud/') ? 300000 : 25000)});
    if (!response.headers.get('content-type')?.includes('application/json')) throw new Error('El servidor no ha devuelto datos de Wave. Revisa su dirección.');
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || `El servidor devolvió un error (${response.status}).`); return data;
  }
  async loadFolders() {
    const [folders, state] = await Promise.all([this.request('api/folders'), this.request('api/desktop/state')]);
    if (!Array.isArray(folders)) throw new Error('La biblioteca del servidor no es válida.');
    this.state = state;
    const byPath=new Map();
    for(const item of folders.filter(item=>safePath(item.name))) {
      const parts=item.name.split('/');
      for(let length=1;length<=parts.length;length++) {
        const key=parts.slice(0,length).join('/');
        if(!byPath.has(key))byPath.set(key,{path:key,parent:length===1?'':parts.slice(0,length-1).join('/'),name:parts[length-1],count:0,directCount:0});
        byPath.get(key).count+=Number(item.count)||0;
        if(length===parts.length)byPath.get(key).directCount=Number(item.count)||0;
      }
    }
    this.folders=[...byPath.values()];
    return {folders: [{path: '', parent: null, name: 'Servidor Wave', count: this.folders.filter(f=>f.parent==='').reduce((sum,f) => sum+f.count,0), directCount: 0}, ...this.folders], state, server: this.base};
  }
  async loadFolder(folder) {
    if (!this.folders.some(item => item.path === folder)) throw new Error('Carpeta del servidor no válida.');
    const data = await this.request(`api/folder/${encodePath(folder)}/tracks`);
    if (!Array.isArray(data)) throw new Error('La lista de canciones no es válida.');
    const tracks = data.filter(item => safePath(item.relPath) && item.relPath.startsWith(folder + '/') && typeof item.url === 'string' && item.url.startsWith('/music/')).map(item => {
      const id = Buffer.from(item.relPath).toString('base64url');
      const track = {id, relPath: item.relPath, filename: item.filename, name: item.name || item.filename, artist: item.artist || '', folder, folderPath: folder, duration: Number(item.duration) || 0, playCount: Number(item.play_count) || 0, format: (item.filename?.split('.').pop() || '').toUpperCase(), cover: this.url('api/artwork/'+encodePath(item.relPath)), source: 'server', url: `wave-audio://server/${id}`};
      this.tracks.set(id, {...track, remoteURL: this.url(item.url)}); return track;
    });
    return tracks;
  }
  async loadAll() {
    const all = []; let index = 0;
    await Promise.all(Array.from({length: Math.min(3,this.folders.length)}, async () => {
      while (index < this.folders.length) { const folder = this.folders[index++]; all.push(...await this.loadFolder(folder.path)); }
    })); return all;
  }
  async edit(operation) {
    const state = await this.request('api/desktop/state', {method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(operation)});
    this.state = state; return state;
  }
  async played(id) {
    const track = this.tracks.get(id); if (!track) return;
    return this.request('api/play', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({track:track.relPath})});
  }
}
class SpotifySearch {
  constructor(server, fetcher = fetch) { this.server = server; this.fetch = fetcher; this.token = null; }
  async search(query, offset = 0, market = 'ES') {
    if (typeof query !== 'string' || query.trim().length < 2 || query.length > 200) throw new Error('Escribe al menos dos caracteres para buscar.');
    if (!Number.isInteger(offset) || offset < 0 || offset > 1000 || !/^[A-Z]{2}$/.test(market)) throw new Error('Búsqueda no válida.');
    if (!this.token || this.token.expires < Date.now() + 30000) {
      const value = await this.server.request('api/spotify/search-token', {method:'POST'});
      this.token = {value: value.access_token, expires: Date.now() + Number(value.expires_in)*1000};
    }
    const url = new URL('https://api.spotify.com/v1/search');
    url.search = new URLSearchParams({q:query.trim(),type:'track',limit:'10',offset:String(offset),market}).toString();
    let response = await this.fetch(url.href,{headers:{Authorization:`Bearer ${this.token.value}`},signal:AbortSignal.timeout(20000)});
    if (response.status === 401) { this.token = null; throw new Error('La sesión de Spotify ha caducado. Vuelve a buscar.'); }
    if (response.status === 429) throw new Error(`Spotify ha limitado las búsquedas. Vuelve a intentarlo en ${response.headers.get('Retry-After') || '60'} segundos.`);
    if (response.status === 403) throw new Error('Spotify ha rechazado la búsqueda desde esta conexión. Revisa los permisos de la aplicación en Spotify o prueba otra conexión. Puedes abrir la búsqueda en Spotify.');
    if (!response.ok) throw new Error(`No se pudo buscar en Spotify (${response.status}).`);
    const data = await response.json(); const results = data.tracks;
    if (!results || !Array.isArray(results.items)) throw new Error('Spotify no ha devuelto una búsqueda válida.');
    return {query:query.trim(),offset,next:Boolean(results.next),total:results.total,items:results.items.filter(Boolean).map(item => ({id:item.id,name:item.name,artist:item.artists?.map(a=>a.name).join(', ') || '',album:item.album?.name || '',duration:Number(item.duration_ms)/1000,cover:item.album?.images?.find(image=>image.width<=300)?.url || item.album?.images?.[0]?.url || '',externalURL:item.external_urls?.spotify || `https://open.spotify.com/track/${item.id}`}))};
  }
}
module.exports = {ServerLibrary, SpotifySearch, safePath};
