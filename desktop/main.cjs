const {app, BrowserWindow, Menu, dialog, ipcMain, protocol, session, shell, net, clipboard} = require('electron');
const fs = require('node:fs/promises');
const path = require('node:path');
const {pathToFileURL} = require('node:url');
const {serverURL, scanLibrary, resolveTrack, resolveDirectory, editState, copyInto} = require('./library.cjs');
const {audioResponse} = require('./audio-response.cjs');
const {CloudClient} = require('./cloud-client.cjs');
const {ServerLibrary, SpotifySearch} = require('./server-client.cjs');
protocol.registerSchemesAsPrivileged([{scheme:'wave-audio',privileges:{standard:true,secure:true,stream:true,supportFetchAPI:true}}]);
const DEFAULT_SERVER = 'https://tulopetas.duckdns.org/wave/';
const UI_URL = pathToFileURL(path.join(__dirname,'ui/index.html')).href;
let win, source = 'server', config = {}, scanning = false, copying = false, editing = Promise.resolve();
let library = {root:'',tracks:[],folders:[],files:new Map(),state:{hidden:[],orders:{}}};
let server, spotify; const tray = new Map();
const configPath = () => path.join(app.getPath('userData'),'settings.json');
async function saveConfig() { await fs.writeFile(configPath(),JSON.stringify(config,null,2),{mode:0o600}); }
function send(channel,value) { if (win && !win.isDestroyed()) win.webContents.send(channel,value); }
function cloudClient(){return new CloudClient(server,path.join(app.getPath('userData'),'cloud-library-'+require('node:crypto').createHash('sha256').update(config.server).digest('hex').slice(0,12)));}
function localState() { library.tracks.forEach(t=>{t.cloudPath=library.root===cloudClient().root?t.relPath:path.basename(library.root)+'/'+t.relPath;}); return {folder:library.root,tracks:library.tracks,folders:library.folders,state:library.state,skipped:library.skipped}; }
function trayState() { return [...tray.values()].map(({id,name,filename})=>({id,name,filename})); }
function setSource(next) {
  if (!['server','local','spotify','settings'].includes(next)) throw new Error('Vista no válida.');
  source = next; send('wave:source-changed',next);
}
async function scan(folder) {
  if (scanning) throw new Error('Ya se está leyendo una carpeta.'); scanning = true;
  try { const next = await scanLibrary(folder); config.folder = next.root; await saveConfig(); library = next; return localState(); }
  finally { scanning = false; }
}
function trusted(event) {
  if (!win || event.sender !== win.webContents || event.senderFrame !== win.webContents.mainFrame || event.senderFrame.url !== UI_URL) throw new Error('Acceso no autorizado.');
}
function handle(name,fn) { ipcMain.handle(name,async(event,...args)=>{trusted(event);return fn(...args);}); }
function serialize(fn) { const result = editing.then(fn); editing = result.catch(()=>{}); return result; }
function xml(value) { return value.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&apos;'); }
async function addToTray(ids) {
  if (!Array.isArray(ids) || !ids.length || ids.length > 10000) throw new Error('Selecciona canciones de tu Mac.');
  const items = [];
  for (const id of new Set(ids)) {
    const track = library.tracks.find(item=>item.id===id); if (!track) throw new Error('Canción no válida.');
    const file = await resolveTrack(library,id); items.push({...track,file,root:library.root});
  }
  for (const item of items) tray.set(item.id,item);
  // Finder-compatible file list; the in-app tray also supports repeated pastes.
  if (process.platform === 'darwin') {
    const plist = `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><array>${items.map(item=>`<string>${xml(item.file)}</string>`).join('')}</array></plist>`;
    clipboard.clear(); clipboard.writeBuffer('NSFilenamesPboardType',Buffer.from(plist));
  } else clipboard.writeText(items.map(item=>item.file).join('\n'));
  send('wave:tray',trayState()); return trayState();
}
async function paste(options = {}) {
  if (copying) throw new Error('Ya se están copiando canciones.');
  if (!tray.size) throw new Error('La bandeja está vacía.');
  let destination;
  if (options.choose) {
    const result = await dialog.showOpenDialog(win,{title:'Pegar canciones en una carpeta',defaultPath:library.root || app.getPath('music'),properties:['openDirectory']});
    if (result.canceled) return null; destination = result.filePaths[0];
  } else destination = await resolveDirectory(library,options.folder || '');
  copying = true;
  try { const result = await copyInto([...tray.values()],destination); const updated = library.root ? await scan(library.root) : null; return {...result,library:updated}; }
  finally { copying = false; }
}
async function createWindow() {
  win = new BrowserWindow({width:1380,height:900,minWidth:940,minHeight:650,title:'Wave',frame:false,backgroundColor:'#f7f6f3',webPreferences:{preload:path.join(__dirname,'preload.cjs'),contextIsolation:true,nodeIntegration:false,sandbox:true,backgroundThrottling:false}});
  if (process.platform === 'darwin') win.setWindowButtonVisibility(false);
  win.webContents.setWindowOpenHandler(()=>({action:'deny'}));win.webContents.on('will-navigate',event=>event.preventDefault());
  win.on('swipe',(_event,direction)=>{if(direction==='left'||direction==='right')send('wave:navigate-request',{delta:direction==='right'?-1:1});});
  win.on('app-command',(_event,command)=>{if(command==='browser-backward'||command==='browser-forward')send('wave:navigate-request',{delta:command==='browser-backward'?-1:1});});
  win.on('closed',()=>{win=null;});await win.loadFile(path.join(__dirname,'ui/index.html'));
}
app.whenReady().then(async()=>{
  try { config = JSON.parse(await fs.readFile(configPath(),'utf8')); } catch { config = {}; }
  try { config.server = serverURL(config.server || DEFAULT_SERVER); } catch { config.server = DEFAULT_SERVER; }
  server = new ServerLibrary(config.server, (...args)=>net.fetch(...args)); spotify = new SpotifySearch(server,(...args)=>net.fetch(...args));
  session.defaultSession.setPermissionRequestHandler((_wc,_permission,callback)=>callback(false));session.defaultSession.setPermissionCheckHandler(()=>false);
  protocol.handle('wave-audio',async request=>{
    try {
      if (!['GET','HEAD'].includes(request.method)) return new Response(null,{status:403});
      const url = new URL(request.url); const id = url.pathname.slice(1);
      if (url.hostname === 'library') return await audioResponse(await resolveTrack(library,id),request);
      if (url.hostname === 'server') {
        const track = server.tracks.get(id); if (!track) return new Response(null,{status:404});
        const headers = {}; const range=request.headers.get('range');if(range)headers.Range=range;
        return await net.fetch(track.remoteURL,{method:request.method,headers,signal:request.signal});
      }
      return new Response(null,{status:403});
    } catch { return new Response('Archivo no disponible',{status:404}); }
  });
  handle('wave:waveform-audio',async(which,id)=>{
    const limit=32*1024*1024;
    if(which==='local'){
      const file=await resolveTrack(library,id);const info=await fs.stat(file);
      if(info.size>limit)throw new Error('La onda está disponible para archivos de hasta 32 MB.');
      return new Uint8Array(await fs.readFile(file));
    }
    if(which!=='server')throw new Error('Biblioteca no válida.');
    const track=server.tracks.get(id);if(!track)throw new Error('Canción no disponible.');
    const response=await net.fetch(track.remoteURL,{signal:AbortSignal.timeout(30000)});
    if(!response.ok)throw new Error('No se pudo cargar el audio para la onda.');
    const reader=response.body.getReader();const parts=[];let size=0;
    try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>limit)throw new Error('La onda está disponible para archivos de hasta 32 MB.');parts.push(value);}}
    finally{await reader.cancel();}
    const bytes=new Uint8Array(size);let offset=0;for(const part of parts){bytes.set(part,offset);offset+=part.length;}return bytes;
  });
  handle('wave:window-control',command=>{
    if(command==='close')win.close();else if(command==='minimize')win.minimize();else if(command==='maximize'){if(win.isFullScreen())win.setFullScreen(false);else if(win.isMaximized())win.unmaximize();else win.maximize();}else throw new Error('Control no válido.');
  });
  handle('wave:volumes',async()=>{
    const roots=process.platform==='darwin'?['/Volumes']:process.platform==='linux'?['/media/'+require('node:os').userInfo().username,'/mnt','/run/media/'+require('node:os').userInfo().username]:[];
    const volumes=[];
    for(const root of roots){try{for(const entry of await fs.readdir(root,{withFileTypes:true})){const folder=path.join(root,entry.name);try{if((await fs.stat(folder)).isDirectory())volumes.push({name:entry.name,path:folder});}catch{}}}catch{}}
    return volumes;
  });
  handle('wave:open-volume',async folder=>{
    const roots=process.platform==='darwin'?['/Volumes']:['/media','/mnt','/run/media'];
    if(typeof folder!=='string'||!roots.some(root=>path.dirname(folder)===root||path.dirname(path.dirname(folder))===root))throw new Error('Almacenamiento no válido.');
    return scan(folder);
  });
  handle('wave:artwork',async(which,id)=>{
    if(which==='server'){const track=server.tracks.get(id);return track?.cover||track?.artwork||'';}
    if(which!=='local')throw new Error('Biblioteca no válida.');
    const file=await resolveTrack(library,id);
    try{const {parseFile}=await import('music-metadata');const metadata=await parseFile(file,{skipCovers:false,skipPostHeaders:true});const picture=metadata.common.picture?.[0];if(picture&&picture.data.length<=5*1024*1024&&['image/jpeg','image/png','image/webp'].includes(picture.format))return `data:${picture.format};base64,${Buffer.from(picture.data).toString('base64')}`;}catch{}
    for(const name of ['cover.jpg','folder.jpg','cover.png','folder.png']){try{const cover=path.join(path.dirname(file),name),real=await fs.realpath(cover);if(!real.startsWith(library.root+path.sep))continue;const info=await fs.stat(real);if(info.size>5*1024*1024)continue;return `data:image/${name.endsWith('.png')?'png':'jpeg'};base64,${(await fs.readFile(real)).toString('base64')}`;}catch{}}
    return '';
  });
  handle('wave:state',()=>({server:config.server,folder:config.folder||'',source,local:localState(),tray:trayState()}));
  handle('wave:source',setSource);
  handle('wave:folder',async()=>{const result=await dialog.showOpenDialog(win,{title:'Selecciona tu carpeta de música',defaultPath:config.folder||app.getPath('music'),properties:['openDirectory']});return result.canceled?null:scan(result.filePaths[0]);});
  handle('wave:refresh',()=>config.folder?scan(config.folder):localState());
  handle('wave:server',async value=>{const next=serverURL(value);config.server=next;await saveConfig();server=new ServerLibrary(next,(...args)=>net.fetch(...args));spotify=new SpotifySearch(server,(...args)=>net.fetch(...args));setSource('server');return next;});
  handle('wave:cloud-upload',()=>serialize(()=>cloudClient().upload(library)));
  handle('wave:cloud-download',()=>serialize(async()=>{const client=cloudClient();await client.recover();const result=await client.download();return {...result,library:await scan(client.root)};}));
  handle('wave:cloud-undo-local',()=>serialize(async()=>{const client=cloudClient();await client.undo();return scan(client.root);}));
  handle('wave:cloud-history',()=>server.request('api/cloud/history'));
  handle('wave:cloud-undo',id=>serialize(()=>cloudClient().post('api/cloud/undo/'+id)));
  handle('wave:likes',()=>server.request('api/likes'));
  handle('wave:like',(track,liked)=>serialize(()=>{if(typeof track!=='string'||typeof liked!=='boolean')throw new Error('Favorito no válido.');return cloudClient().post('api/like',{track,liked});}));
  handle('wave:relocate',(track,folder)=>serialize(()=>cloudClient().post('api/cloud/relocate',{track,folder})));
  handle('wave:server-folders',()=>server.loadFolders());
  handle('wave:server-tracks',folder=>folder==='*'?server.loadAll():server.loadFolder(folder));
  handle('wave:edit-state',(which,operation)=>serialize(()=>which==='local'?editState(library,operation):which==='server'?server.edit(operation):Promise.reject(new Error('Biblioteca no válida.'))));
  handle('wave:played',id=>server.played(id));
  handle('wave:copy',addToTray);
  handle('wave:clipboard-command',command=>{if(!['copy','paste','selectAll'].includes(command))throw new Error('Acción no válida.');win.webContents[command]();});
  handle('wave:tray-remove',id=>{if(id===null)tray.clear();else tray.delete(id);send('wave:tray',trayState());return trayState();});
  handle('wave:paste',options=>serialize(()=>paste(options)));
  handle('wave:reveal',async id=>shell.showItemInFolder(await resolveTrack(library,id)));
  handle('wave:spotify-status',()=>server.request('api/spotify/status'));
  handle('wave:spotify-search',(query,offset,market)=>spotify.search(query,offset,market));
  handle('wave:open-spotify',url=>{
    if(typeof url!=='string'||!/^https:\/\/open\.spotify\.com\/(?:track\/[A-Za-z0-9]+(?:\?.*)?|search\/[^\r\n]*)$/.test(url))throw new Error('Enlace de Spotify no válido.');return shell.openExternal(url);
  });
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    {label:'Wave',submenu:[{role:'about'},{label:'Ajustes…',accelerator:'CmdOrCtrl+,',click:()=>setSource('settings')},{type:'separator'},{role:'hide'},{role:'hideOthers'},{role:'unhide'},{type:'separator'},{role:'quit'}]},
    {label:'Biblioteca',submenu:[{label:'Servidor Wave',accelerator:'CmdOrCtrl+1',click:()=>setSource('server')},{label:'Música de este Mac',accelerator:'CmdOrCtrl+2',click:()=>setSource('local')},{label:'Spotify',accelerator:'CmdOrCtrl+3',click:()=>setSource('spotify')}]},
    {label:'Edición',submenu:[{role:'undo'},{role:'redo'},{type:'separator'},{role:'cut'},{label:'Copiar',accelerator:'CmdOrCtrl+C',click:()=>send('wave:copy-request')},{label:'Pegar',accelerator:'CmdOrCtrl+V',click:()=>send('wave:paste-request')},{label:'Seleccionar todo',accelerator:'CmdOrCtrl+A',click:()=>send('wave:select-request')}]},{label:'Visualización',submenu:[{label:'Atrás',accelerator:'CmdOrCtrl+[',click:()=>send('wave:navigate-request',-1)},{label:'Adelante',accelerator:'CmdOrCtrl+]',click:()=>send('wave:navigate-request',1)},{type:'separator'},{label:'Actualizar biblioteca',accelerator:'CmdOrCtrl+R',click:()=>send('wave:refresh-request',null)},{role:'togglefullscreen'}]},{role:'windowMenu'}
  ]));await createWindow();app.on('activate',()=>{if(!BrowserWindow.getAllWindows().length)createWindow();});
}).catch(error=>{dialog.showErrorBox('Wave',error.message);app.quit();});
app.on('window-all-closed',()=>{if(process.platform!=='darwin')app.quit();});
