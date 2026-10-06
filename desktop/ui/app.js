const $ = id => document.getElementById(id);
const audio = $('audio');
const newLibrary = () => ({root:'',folders:[],tracks:[],state:{hidden:[],orders:{}},path:'',all:false,loaded:false,loadedFolders:new Set(),expanded:new Set([''])});
const libraries = {local:newLibrary(),server:newLibrary()};
let source='server', rememberedFolder='', view='advanced', selected=new Set(), tray=[], playing=null, working=0, serverGeneration=0;
let sharedLikes={},favoritesOnly=false;
let spotifyState={query:'',offset:0,total:0,next:false},spotifyRequest=0;
function element(tag,text,className) { const node=document.createElement(tag);if(text!==undefined)node.textContent=text;if(className)node.className=className;return node; }
function icon(name) { const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.setAttribute('aria-hidden','true');const use=document.createElementNS(svg.namespaceURI,'use');use.setAttribute('href',`#i-${name}`);svg.append(use);return svg; }
function action(label,handler,className='') { const button=element('button',label,className);button.type='button';button.addEventListener('click',handler);return button; }
function iconAction(name,label,handler) { const button=action(undefined,handler,'icon-button');button.append(icon(name));button.title=label;button.setAttribute('aria-label',label);return button; }
function notice(value='',type='error',target='notice') { $(target).textContent=value?.message || String(value);$(target).className=`notice ${type}`; }
function countText(n) { return `${n} ${n===1?'canción':'canciones'}`; }
function sizeText(size) { if(!Number.isFinite(size))return '—';return size<1048576?`${Math.round(size/1024)} KB`:`${(size/1048576).toFixed(1)} MB`; }
function durationText(value) { if(!value || !Number.isFinite(value))return '—';return `${Math.floor(value/60)}:${String(Math.floor(value%60)).padStart(2,'0')}`; }
function lib() { return libraries[source]; }
function scope(library) { return library.all?'*':library.path; }
function scopedTracks(library) { return library.all?library.tracks:library.tracks.filter(track=>track.folderPath===library.path); }
function orderedTracks(library) {
  const rows=[...scopedTracks(library)];const mode=$('sort').value;
  const order=Object.hasOwn(library.state.orders || {},scope(library))?library.state.orders[scope(library)]:[];
  const rank=new Map((Array.isArray(order)?order:[]).map((p,i)=>[p,i]));
  return rows.sort((a,b)=>{
    if(mode==='manual') { const diff=(rank.get(a.relPath)??Infinity)-(rank.get(b.relPath)??Infinity);if(!Number.isNaN(diff)&&diff!==0)return diff; }
    if(mode==='size')return (b.size||0)-(a.size||0)||a.name.localeCompare(b.name);
    if(mode==='modified')return (b.modified||0)-(a.modified||0)||a.name.localeCompare(b.name);
    if(mode==='duration')return (b.duration||0)-(a.duration||0)||a.name.localeCompare(b.name);
    if(mode==='filename')return a.filename.localeCompare(b.filename);
    if(mode==='folder')return a.folder.localeCompare(b.folder)||a.name.localeCompare(b.name);
    return a.name.localeCompare(b.name)*(mode==='name-desc'?-1:1);
  });
}
function visibleTracks() {
  if(!lib())return [];const query=$('search').value.trim().toLocaleLowerCase();const hidden=new Set(lib().state.hidden);
  return orderedTracks(lib()).filter(track=>(!favoritesOnly||sharedLikes[track.cloudPath||track.relPath])&&(view==='advanced'||!hidden.has(track.relPath))&&`${track.name} ${track.filename} ${track.artist||''} ${track.folder}`.toLocaleLowerCase().includes(query));
}
function folderCount(folder,library) { if(view==='advanced')return folder.count;return Math.max(0,folder.count-library.state.hidden.filter(p=>!folder.path||p.startsWith(folder.path+'/')).length); }
function updateSelection() {
  const rows=visibleTracks();$('selection-count').textContent=selected.size?`${selected.size} seleccionadas`:'';
  $('copy-selected').disabled=!selected.size||working>0;$('hide-selected').disabled=!selected.size||working>0;$('clear-selection').disabled=!selected.size;
  const allHidden=selected.size>0&&[...selected].every(id=>lib()?.state.hidden.includes(lib().tracks.find(t=>t.id===id)?.relPath));
  $('hide-selected').lastChild.textContent=allHidden?'Mostrar selección':'Ocultar selección';
  $('select-all').checked=rows.length>0&&rows.every(track=>selected.has(track.id));$('select-all').indeterminate=rows.some(track=>selected.has(track.id))&&!$('select-all').checked;
}
function renderTree() {
  const area=$('folder-tree');area.replaceChildren();if(!lib())return;const library=lib();
  const all=action('Todas las canciones',()=>navigate('',true),'tree-node');all.prepend(icon('music'));all.classList.toggle('active',library.all);area.append(all);
  function build(folder,container) {
    const row=element('div',undefined,'tree-row');const children=library.folders.filter(item=>item.parent===folder.path);
    if(children.length) { const toggle=iconAction(library.expanded.has(folder.path)?'down':'next',`Expandir ${folder.name}`,()=>{library.expanded.has(folder.path)?library.expanded.delete(folder.path):library.expanded.add(folder.path);renderTree();});toggle.className='tree-toggle';toggle.setAttribute('aria-expanded',String(library.expanded.has(folder.path)));row.append(toggle); }
    const button=action(undefined,()=>navigate(folder.path),'tree-node');button.append(icon('folder'),element('span',folder.name),element('small',String(folderCount(folder,library)),'tree-count'));button.title=folder.name;button.classList.toggle('active',!library.all&&library.path===folder.path);row.append(button);container.append(row);
    if(children.length&&library.expanded.has(folder.path)) { const branch=element('div',undefined,'tree-children');for(const child of children)build(child,branch);container.append(branch); }
  }
  const root=library.folders.find(folder=>folder.path==='');if(root)build(root,area);
}
function renderBreadcrumbs() {
  $('breadcrumbs').replaceChildren();if(!lib())return;const library=lib();const rootName=source==='local'?(library.root.split(/[\\/]/).pop()||'Música del Mac'):'Servidor Wave';
  const root=action(rootName,()=>navigate(''),'breadcrumb');root.classList.toggle('active',!library.path&&!library.all);$('breadcrumbs').append(root);
  const parts=library.all?['Todas las canciones']:library.path.split('/').filter(Boolean);
  parts.forEach((part,index)=>{const path=parts.slice(0,index+1).join('/');$('breadcrumbs').append(element('span','/'));const button=action(part,()=>navigate(library.all?'':path,library.all),'breadcrumb');if(index===parts.length-1)button.classList.add('active');$('breadcrumbs').append(button);});
  $('all-tracks').classList.toggle('active',library.all);
}
function renderFolders() {
  $('folders').replaceChildren();if(!lib()||lib().all)return;
  const query=$('search').value.trim().toLocaleLowerCase();
  for(const folder of lib().folders.filter(item=>item.parent===lib().path&&item.name.toLocaleLowerCase().includes(query))) {
    const button=action(undefined,()=>navigate(folder.path),'folder-card');const details=element('div',undefined,'folder-details');details.append(element('strong',folder.name),element('small',countText(folderCount(folder,lib()))));button.append(icon('folder'),details);$('folders').append(button);
  }
}
function renderTracks() {
  const positions=window.waveMotion?.captureRows();
  const rows=visibleTracks();const hidden=new Set(lib()?.state.hidden || []);const fragment=document.createDocumentFragment();
  $('tracks-table').className=view;$('detail-heading').textContent=source==='local'?'Tamaño':'Duración';$('date-heading').textContent=source==='local'?'Modificado':'Reproducciones';
  for(const track of rows) {
    const tr=element('tr',undefined,'track');tr.dataset.id=track.id;tr.draggable=true;tr.classList.toggle('selected',selected.has(track.id));tr.classList.toggle('playing',playing?.source===source&&playing.id===track.id);tr.classList.toggle('is-hidden',hidden.has(track.relPath));
    const selectCell=element('td',undefined,'check-col');const checkbox=element('input');checkbox.type='checkbox';checkbox.checked=selected.has(track.id);checkbox.setAttribute('aria-label',`Seleccionar ${track.name}`);checkbox.addEventListener('change',()=>{checkbox.checked?selected.add(track.id):selected.delete(track.id);tr.classList.toggle('selected',checkbox.checked);updateSelection();});selectCell.append(checkbox);
    const titleCell=element('td');const title=action(undefined,()=>playTrack(track),'song-title');const details=element('span');details.append(element('strong',track.name),element('small',track.artist || track.folder));title.append(coverNode(track),icon(playing?.source===source&&playing.id===track.id&&!audio.paused?'pause':'play'),details);titleCell.append(title);if(hidden.has(track.relPath))titleCell.append(element('span','Oculta','hidden-badge'));
    const fileCell=element('td',undefined,'advanced-only file-detail');fileCell.append(element('span',track.filename),element('small',track.folderPath||'Carpeta principal'));
    const detailCell=element('td',source==='local'?sizeText(track.size):durationText(track.duration),'advanced-only');
    const dateCell=element('td',source==='local'?(track.modified?new Date(track.modified).toLocaleDateString('es-ES'):'—'):String(track.playCount||0),'advanced-only');
    const formatCell=element('td',track.format,'advanced-only');
    const actionsCell=element('td',undefined,'actions-col');const actions=element('div',undefined,'row-actions');
    const heart=action(sharedLikes[track.cloudPath||track.relPath]?'♥':'♡',()=>setFavorite(track,source));heart.setAttribute('aria-label','Me gusta: '+track.name);actions.append(heart);
    if($('sort').value==='manual'||view==='advanced') { actions.append(iconAction('up',`Subir ${track.name}`,()=>reorder(track.id,-1)),iconAction('down',`Bajar ${track.name}`,()=>reorder(track.id,1))); }
    actions.append(iconAction(hidden.has(track.relPath)?'eye':'hidden',hidden.has(track.relPath)?`Mostrar ${track.name}`:`Ocultar ${track.name}`,()=>changeHidden([track.id],!hidden.has(track.relPath))));
    if(source==='local'&&view==='advanced')actions.append(iconAction('external',`Mostrar ${track.filename} en Finder`,()=>window.wave.reveal(track.id).catch(error=>notice(error))));for(const button of actions.children)button.disabled=working>0;actionsCell.append(actions);
    tr.append(selectCell,titleCell,fileCell,detailCell,dateCell,formatCell,actionsCell);
    tr.addEventListener('dragstart',event=>{event.dataTransfer.setData('application/x-wave-order',JSON.stringify({id:track.id,source}));event.dataTransfer.effectAllowed='move';tr.classList.add('dragging');});
    tr.addEventListener('dragend',()=>{document.querySelectorAll('.dragging,.drag-target').forEach(node=>node.classList.remove('dragging','drag-target'));});
    tr.addEventListener('dragover',event=>{if(event.dataTransfer.types.includes('application/x-wave-order')){event.preventDefault();tr.classList.add('drag-target');}});
    tr.addEventListener('dragleave',()=>tr.classList.remove('drag-target'));
    tr.addEventListener('drop',event=>{event.preventDefault();tr.classList.remove('drag-target');try{const value=JSON.parse(event.dataTransfer.getData('application/x-wave-order'));if(value.source===source)reorder(value.id,0,track.id);}catch{notice('No se pudo reordenar esta canción.');}});
    fragment.append(tr);
  }
  $('list').replaceChildren(fragment);$('table-wrap').hidden=!rows.length;$('view-note').hidden=!rows.length;
  const hiddenCount=scopedTracks(lib()||newLibrary()).filter(track=>hidden.has(track.relPath)).length;
  $('count').textContent=countText(rows.length)+(hiddenCount?` · ${hiddenCount} ${hiddenCount===1?'oculta':'ocultas'}`:'');
  const noFolder=source==='local'&&!libraries.local.loaded;const isEmpty=!rows.length&&!$('folders').childElementCount;
  $('empty').hidden=!isEmpty;$('empty-choose').hidden=!noFolder;
  $('empty-title').textContent=noFolder?'Tu colección, en su sitio.':hiddenCount&&view==='normal'?'Las canciones están ocultas.':$('search').value?'Sin coincidencias.':'Esta carpeta está vacía.';
  $('empty-text').textContent=noFolder?'Abre tu carpeta Música o cualquier otra carpeta del Mac.':hiddenCount&&view==='normal'?'Cambia a la vista avanzada para verlas y volver a mostrarlas.':$('search').value?'Prueba otro nombre o busca en todas las canciones.':'Abre una subcarpeta o pega canciones desde la bandeja.';
  updateSelection();syncPlayer();renderBrowser();window.waveMotion?.moveRows(positions);
}
function renderLibrary() {
  if(!lib())return;const local=source==='local';$('library-title').textContent=local?'Música de este Mac':'Servidor Wave';$('library-label').textContent=local?'Biblioteca local':'Biblioteca del servidor';$('folder-label').textContent=local?(lib().root||rememberedFolder||'Elige una carpeta y organiza tu música.'):'Tu biblioteca del servidor, desde la API de Wave.';
  $('choose').hidden=!local;$('copy-selected').hidden=!local;$('sort').disabled=working>0;$('refresh').disabled=working>0||(!lib().loaded&&local);
  $('normal-view').classList.toggle('active',view==='normal');$('advanced-view').classList.toggle('active',view==='advanced');$('normal-view').setAttribute('aria-pressed',String(view==='normal'));$('advanced-view').setAttribute('aria-pressed',String(view==='advanced'));
  for(const option of $('sort').options)option.disabled=!local&&['size','modified'].includes(option.value);
  if(!local&&['size','modified'].includes($('sort').value))$('sort').value='manual';
  const category=$('discover-category'),current=category.value;category.replaceChildren();
  for(const folder of lib().folders.filter(f=>f.path)){const option=element('option',folder.path);option.value=folder.path;category.append(option);}if([...category.options].some(o=>o.value===current))category.value=current;
  $('cloud-upload').hidden=!local;$('cloud-upload').disabled=working>0||!lib().loaded;
  renderBreadcrumbs();renderTree();renderFolders();renderTracks();renderTray();renderBrowser();
}
function adoptLocal(result) {
  if(!result)return;const library=libraries.local;library.root=result.folder;library.tracks=result.tracks;library.folders=result.folders;library.state=result.state;library.loaded=Boolean(result.folder);rememberedFolder=result.folder;
  if(!library.folders.some(folder=>folder.path===library.path)){library.path='';library.all=false;}
  if(playing?.source==='local'&&!library.tracks.some(track=>track.id===playing.id)){audio.pause();audio.removeAttribute('src');audio.load();playing=null;resetNow();}selected.clear();
}
function resetNow() { $('now-title').textContent='Nada reproduciéndose';$('now-folder').textContent='Selecciona una canción para empezar'; }
async function localAction(fn) {
  if(working)return;working++;$('choose').disabled=true;notice('Leyendo la carpeta de música…','loading');if(source==='local')renderLibrary();
  try { const result=await fn();adoptLocal(result);notice(result?.skipped?`${result.skipped} archivos o carpetas no se pudieron leer.`:'',result?.skipped?'error':'success'); }
  catch(error){notice(error);}finally{working--;$('choose').disabled=false;if(source==='local')renderLibrary();}
}
async function loadServer() {
  const generation=++serverGeneration;notice('Leyendo la biblioteca del servidor…','loading');$('connection').textContent='Conectando al servidor…';
  try { const data=await window.wave.serverFolders();sharedLikes=await window.wave.likes();if(generation!==serverGeneration)return;const library=libraries.server;library.folders=data.folders;library.state=data.state;library.root=data.server;library.tracks=[];library.loadedFolders.clear();library.loaded=true;if(!library.folders.some(folder=>folder.path===library.path))library.path='';$('connection').textContent='API del servidor conectada';if(source==='server')await navigate(library.path,library.all); }
  catch(error){if(generation!==serverGeneration)return;$('connection').textContent='Servidor no disponible';if(source==='server')notice(error);}
}
async function navigate(path,all=false) {
  if(!lib())return;beginNavigation();songOpen=false;$('song-view').hidden=true;$('library').hidden=false;const library=lib();library.path=path;library.all=all;selected.clear();notice('');
  const parts=path.split('/');library.expanded.add('');for(let i=1;i<=parts.length;i++)library.expanded.add(parts.slice(0,i).join('/'));renderLibrary();recordNavigation();
  if(source==='server'&&library.loaded&&(all||path)&&!library.loadedFolders.has(all?'*':path)) {
    const requested=all?'*':path;const generation=serverGeneration;notice('Cargando canciones…','loading');
    try { const tracks=await window.wave.serverTracks(requested);if(generation!==serverGeneration)return;if(all){library.tracks=tracks;for(const folder of library.folders)library.loadedFolders.add(folder.path);}else library.tracks=[...library.tracks.filter(track=>track.folderPath!==path),...tracks];library.loadedFolders.add(requested);if(source==='server'&&scope(library)===requested){notice('');renderLibrary();} }
    catch(error){if(source==='server')notice(error);}
  }
}
async function changeHidden(ids,hidden) {
  if(!lib()||working)return;const which=source;const library=lib();const paths=ids.map(id=>library.tracks.find(track=>track.id===id)?.relPath).filter(Boolean);if(!paths.length)return;
  working++;notice('Guardando cambios…','loading');renderLibrary();
  try{library.state=await window.wave.editState(which,{action:'hidden',paths,hidden});selected.clear();notice(hidden?'Canciones ocultas. Puedes recuperarlas desde la vista avanzada.':'Canciones visibles de nuevo.','success');}
  catch(error){notice(error);}finally{working--;if(source===which)renderLibrary();}
}
async function reorder(id,delta,targetId) {
  if(!lib()||working)return;const which=source;const library=lib();const ordered=orderedTracks(library);const from=ordered.findIndex(track=>track.id===id);if(from<0)return;
  const visible=visibleTracks();const visibleFrom=visible.findIndex(track=>track.id===id);const neighbor=targetId||visible[visibleFrom+delta]?.id;
  let to=neighbor?ordered.findIndex(track=>track.id===neighbor):-1;if(to<0||to>=ordered.length||to===from)return;
  const [moving]=ordered.splice(from,1);ordered.splice(to,0,moving);working++;notice('Guardando el orden…','loading');renderLibrary();
  try { library.state=await window.wave.editState(which,{action:'order',scope:scope(library),paths:ordered.map(track=>track.relPath)});$('sort').value='manual';notice('Orden guardado en la biblioteca.','success'); }
  catch(error){notice(error);}finally{working--;if(source===which)renderLibrary();}
}
let playbackQueue=[], playbackSource='server', shuffle=false, repeat=false;
async function playTrack(track, which=source, keepQueue=false) {
  if(!track)return;
  if(playing?.source===which&&playing.id===track.id&&audio.src){togglePlayback();return;}
  if(!keepQueue){playbackQueue=visibleTracks();playbackSource=which;}
  playing={source:which,id:track.id,track};audio.src=track.url;$('now-title').textContent=track.name;$('now-folder').textContent=track.artist?`${track.artist} · ${track.folder}`:track.folder;
  if('mediaSession' in navigator)navigator.mediaSession.metadata=new MediaMetadata({title:track.name,artist:track.artist||'Wave',album:track.folder});
  updateArtwork();if(lib()){renderTracks();renderBrowser();}syncPlayer();window.dispatchEvent(new Event('wave-track'));
  try{await audio.play();if(which==='server')window.wave.played(track.id).then(result=>{if(result?.count)track.playCount=result.count;}).catch(()=>{});}catch{notice('No se pudo reproducir esta canción. Comprueba su formato, su ubicación o la conexión al servidor.');}
}
function togglePlayback(){if(playing){if(audio.paused)audio.play().catch(error=>notice(error));else audio.pause();}else{const track=visibleTracks()[0];if(track)playTrack(track);}}
function step(delta, ended=false) {
  const rows=playbackQueue.length?playbackQueue:visibleTracks();if(!rows.length)return;
  const index=rows.findIndex(track=>track.id===playing?.id);
  if(ended&&repeat&&rows.length===1){audio.currentTime=0;audio.play().catch(error=>notice(error));return;}
  if(ended&&!repeat&&!shuffle&&index===rows.length-1){syncPlayer();return;}
  let next=(index+delta+rows.length)%rows.length;
  if(shuffle&&rows.length>1){next=(index+1+Math.floor(Math.random()*(rows.length-1)))%rows.length;}
  if(rows[next].id===playing?.id){audio.currentTime=0;audio.play().catch(error=>notice(error));return;}
  playTrack(rows[next],playbackQueue.length?playbackSource:source,true);
}
function syncPlayer() {
  const enabled=Boolean(playing||visibleTracks().length);for(const id of ['previous','play','next'])$(id).disabled=!enabled;
  $('open-song').disabled=!playing;$('play').replaceChildren(icon(audio.paused?'play':'pause'));$('play').setAttribute('aria-label',audio.paused?'Reproducir':'Pausar');
  if('mediaSession' in navigator)navigator.mediaSession.playbackState=playing?(audio.paused?'paused':'playing'):'none';
  window.dispatchEvent(new Event('wave-player'));
}
function renderTray() {
  $('tray-badge').textContent=String(tray.length);$('tray-list').replaceChildren();
  for(const entry of tray){const row=element('div',undefined,'tray-item');const details=element('div');details.append(element('strong',entry.name),element('small',entry.filename));row.append(icon('music'),details,iconAction('close',`Quitar ${entry.name} de la bandeja`,()=>window.wave.removeTray(entry.id).catch(error=>notice(error,'error','tray-notice'))));$('tray-list').append(row);}
  if(!tray.length)$('tray-list').append(element('p','Selecciona canciones de tu Mac y pulsa «Copiar a bandeja».'));
  $('paste-here').disabled=!tray.length||source!=='local'||!libraries.local.loaded||libraries.local.all||working>0;
  $('paste-elsewhere').disabled=!tray.length||working>0;$('clear-tray').disabled=!tray.length||working>0;
}
function toggleTray(show) { if(window.waveMotion)window.waveMotion.tray(show);else{$('tray').hidden=!show;document.body.classList.toggle('tray-open',show);}renderTray(); }
async function copySelection() {
  if(source!=='local'||!selected.size)return;
  try{tray=await window.wave.copy([...selected]);toggleTray(true);notice(`${countText(tray.length)} en la bandeja. Puedes pegarlas en la carpeta que quieras.`,'success','tray-notice');}
  catch(error){notice(error);}
}
async function pasteSongs(choose=false) {
  if(working)return;working++;if(lib())renderLibrary();else renderTray();notice('Copiando canciones…','loading','tray-notice');
  try {
    const result=await window.wave.paste({choose,folder:libraries.local.path});if(!result){notice('','','tray-notice');return;}
    if(result.library)adoptLocal(result.library);const overwritten=result.results.filter(item=>item.status==='overwritten').length;const copied=result.results.filter(item=>item.status==='copied').length;const same=result.results.filter(item=>item.status==='same').length;const errors=result.results.filter(item=>item.status==='error');
    const summary=[`${copied} copiadas`,`${overwritten} sobrescritas`,same?`${same} ya estaban en el destino`:null,errors.length?`${errors.length} errores: ${errors.map(item=>`${item.name}: ${item.error}`).join('; ')}`:null].filter(Boolean).join(' · ');
    notice(summary,errors.length?'error':'success','tray-notice');if(source==='local')notice(summary,errors.length?'error':'success');
  }catch(error){notice(error,'error','tray-notice');}finally{working--;if(lib())renderLibrary();else renderTray();}
}
async function showSource(next) {
  beginNavigation();const changed=source!==next;if(changed){selected.clear();$('search').value='';notice('');}source=next;
  $('song-view').hidden=true;$('storage-area').hidden=next!=='local';if(next==='local')refreshVolumes();$('library').hidden=!lib();$('spotify').hidden=next!=='spotify';$('settings').hidden=next!=='settings';$('tree-area').hidden=!lib();
  for(const name of ['server','local','spotify','settings'])$(`${name}-nav`).classList.toggle('active',next===name);
  if(lib())renderLibrary();else syncPlayer();renderTray();recordNavigation();
  if(next==='local'&&!libraries.local.loaded&&rememberedFolder)await localAction(window.wave.refresh);
  if(next==='server'&&!libraries.server.loaded)await loadServer();
  if(next==='spotify')window.wave.spotifyStatus().then(status=>{if(!status.configured)notice('Spotify no está configurado en el servidor.','error','spotify-notice');}).catch(error=>notice(error,'error','spotify-notice'));
}
async function refreshCurrent() {
  if(source==='local')await localAction(window.wave.refresh);
  if(source==='server'){await loadServer();}
}
function setView(next){beginNavigation();view=next;localStorage.setItem('wave_view',next);selected.clear();if(lib())renderLibrary();recordNavigation();}
async function searchSpotify(query,offset=0) {
  const request=++spotifyRequest;query=query.trim();if(query.length<2){notice('Escribe al menos dos caracteres.','error','spotify-notice');return;}
  $('spotify-search').disabled=true;$('spotify-prev').disabled=$('spotify-next').disabled=true;$('spotify-external').disabled=false;notice('Buscando en Spotify…','loading','spotify-notice');
  try {
    const result=await window.wave.spotifySearch(query,offset,$('spotify-market').value);if(request!==spotifyRequest)return;spotifyState=result;$('spotify-results').replaceChildren();
    for(const track of result.items){const row=element('div',undefined,'spotify-result');const image=element('img');image.alt='';if(/^https:\/\/i\.scdn\.co\//.test(track.cover))image.src=track.cover;const details=element('div',undefined,'result-details');details.append(element('strong',track.name),element('p',`${track.artist} · ${track.album}`));const open=action('Abrir en Spotify',()=>window.wave.openSpotify(track.externalURL).catch(error=>notice(error,'error','spotify-notice')));open.prepend(icon('external'));row.append(image,details,element('span',durationText(track.duration),'duration'),open);$('spotify-results').append(row);}
    $('spotify-count').textContent=`${result.total.toLocaleString('es-ES')} ${result.total===1?'resultado':'resultados'}`;$('spotify-page').textContent=`Página ${Math.floor(result.offset/10)+1}`;$('spotify-pagination').hidden=!result.items.length;$('spotify-prev').disabled=result.offset===0;$('spotify-next').disabled=!result.next||result.offset>=1000;notice(result.items.length?'':'No hay resultados para esta búsqueda.','success','spotify-notice');
  }catch(error){if(request===spotifyRequest)notice(error,'error','spotify-notice');}finally{if(request===spotifyRequest)$('spotify-search').disabled=false;}
}
for(const name of ['server','local','spotify','settings'])$(`${name}-nav`).addEventListener('click',()=>window.wave.switchSource(name).catch(error=>notice(error)));
$('choose').addEventListener('click',()=>localAction(window.wave.chooseFolder));$('empty-choose').addEventListener('click',()=>localAction(window.wave.chooseFolder));$('refresh').addEventListener('click',refreshCurrent);
$('all-tracks').addEventListener('click',()=>navigate('',!lib().all));$('search').addEventListener('input',()=>{selected.clear();renderLibrary();});$('sort').addEventListener('change',renderLibrary);
$('normal-view').addEventListener('click',()=>setView('normal'));$('advanced-view').addEventListener('click',()=>setView('advanced'));
$('select-all').addEventListener('change',()=>{for(const track of visibleTracks())$('select-all').checked?selected.add(track.id):selected.delete(track.id);renderTracks();});
$('clear-selection').addEventListener('click',()=>{selected.clear();renderTracks();});$('copy-selected').addEventListener('click',copySelection);
$('hide-selected').addEventListener('click',()=>{const hidden=[...selected].every(id=>lib().state.hidden.includes(lib().tracks.find(track=>track.id===id)?.relPath));changeHidden([...selected],!hidden);});
$('tray-toggle').addEventListener('click',()=>toggleTray(!document.body.classList.contains('tray-open')));$('tray-close').addEventListener('click',()=>toggleTray(false));$('paste-here').addEventListener('click',()=>pasteSongs());$('paste-elsewhere').addEventListener('click',()=>pasteSongs(true));$('clear-tray').addEventListener('click',()=>window.wave.removeTray(null).then(()=>notice('','','tray-notice')));
$('previous').addEventListener('click',()=>step(-1));$('next').addEventListener('click',()=>step(1));$('play').addEventListener('click',togglePlayback);
audio.addEventListener('play',()=>{syncPlayer();if(lib())renderTracks();});audio.addEventListener('pause',()=>{syncPlayer();if(lib())renderTracks();});audio.addEventListener('ended',()=>step(1,true));audio.addEventListener('error',()=>{if(playing)notice('No se pudo abrir esta canción. Actualiza la biblioteca o comprueba la conexión.');});
$('server-form').addEventListener('submit',async event=>{event.preventDefault();notice('','','settings-notice');audio.pause();audio.removeAttribute('src');audio.load();playing=null;resetNow();libraries.server.loaded=false;serverGeneration++;try{$('server-url').value=await window.wave.saveServer($('server-url').value);}catch(error){notice(error,'error','settings-notice');}});
$('spotify-form').addEventListener('submit',event=>{event.preventDefault();searchSpotify($('spotify-query').value);});$('spotify-query').addEventListener('input',()=>{$('spotify-external').disabled=$('spotify-query').value.trim().length<2;});
$('spotify-prev').addEventListener('click',()=>searchSpotify(spotifyState.query,Math.max(0,spotifyState.offset-10)));$('spotify-next').addEventListener('click',()=>searchSpotify(spotifyState.query,spotifyState.offset+10));$('spotify-external').addEventListener('click',()=>window.wave.openSpotify(`https://open.spotify.com/search/${encodeURIComponent($('spotify-query').value.trim()||spotifyState.query)}`).catch(error=>notice(error,'error','spotify-notice')));
let sourceTransition=Promise.resolve();window.wave.onSource(next=>{sourceTransition=showSource(next);});window.wave.onTray(value=>{tray=value;renderTray();});window.wave.onRefresh(refreshCurrent);
function isEditingText() { return document.activeElement?.matches('textarea,select,[contenteditable="true"],input:not([type="checkbox"]):not([type="radio"])'); }
function copyCommand(){if(isEditingText())window.wave.clipboardCommand('copy');else copySelection();}
function pasteCommand(){if(isEditingText())window.wave.clipboardCommand('paste');else if(source==='local'&&tray.length&&!lib().all)pasteSongs();}
function selectCommand(){if(isEditingText())window.wave.clipboardCommand('selectAll');else if(lib()){for(const track of visibleTracks())selected.add(track.id);renderTracks();}}
window.wave.onCopy(copyCommand);window.wave.onPaste(pasteCommand);window.wave.onSelectAll(selectCommand);

if('mediaSession' in navigator){navigator.mediaSession.setActionHandler('play',()=>{if(playing)audio.play().catch(error=>notice(error));});navigator.mediaSession.setActionHandler('pause',()=>audio.pause());navigator.mediaSession.setActionHandler('previoustrack',()=>step(-1));navigator.mediaSession.setActionHandler('nexttrack',()=>step(1));}
document.addEventListener('DOMContentLoaded',()=>{window.wave.state().then(state=>{rememberedFolder=state.folder;tray=state.tray;$('server-url').value=state.server;if(state.local.folder)adoptLocal(state.local);renderTray();sourceTransition=showSource(state.source);}).catch(error=>notice(error));},{once:true});

const artworkCache=new Map();
async function trackArtwork(track,which=source){
 const key=which+':'+track.id;if(!artworkCache.has(key))artworkCache.set(key,window.wave.artwork(which,track.id).catch(()=>''));return artworkCache.get(key);
}
function coverNode(track,which=source){
 const box=element('span',undefined,'track-cover');box.append(icon('music'));
 const load=()=>trackArtwork(track,which).then(url=>{if(!url||! /^(data:image\/(jpeg|png|webp);base64,|https:\/\/)/.test(url))return;const image=element('img');image.alt='';image.src=url;image.addEventListener('load',()=>box.replaceChildren(image));});const observer=new IntersectionObserver(entries=>{if(entries.some(entry=>entry.isIntersecting)){observer.disconnect();load();}});observer.observe(box);return box;
}
function updateArtwork(){const track=playing?.track;if(!track)return;const which=playing.source;const old=$('open-song').querySelector('svg,.track-cover');if(old)old.replaceWith(coverNode(track,which));document.querySelector('.song-art').replaceChildren(coverNode(track,which));}
async function refreshVolumes(){try{const volumes=await window.wave.volumes();$('storage-list').replaceChildren();for(const volume of volumes){const button=action(volume.name,()=>localAction(()=>window.wave.openVolume(volume.path)),'nav');button.prepend(icon('folder'));button.title=volume.path;$('storage-list').append(button);}if(!volumes.length)$('storage-list').append(element('p','No hay discos externos conectados.','view-note'));}catch(error){notice(error);}}
$('storage-refresh').addEventListener('click',refreshVolumes);
for(const command of ['minimize','maximize','close'])$('window-'+command).addEventListener('click',()=>window.wave.windowControl(command).catch(error=>notice(error)));
window.addEventListener('focus',()=>{if(source==='local')refreshVolumes();});

async function syncLikes(){try{sharedLikes=await window.wave.likes();if(lib())renderTracks();updatePlayerHeart();}catch(error){notice(error);}}
async function setFavorite(track,which,desired){try{const key=which==='local'?track.cloudPath:track.relPath;const result=await window.wave.like(key,desired??!sharedLikes[key]);if(result.liked)sharedLikes[key]=true;else delete sharedLikes[key];if(lib())renderTracks();updatePlayerHeart();}catch(error){notice(error);throw error;}}
function cloudToast(message){$('cloud-toast-text').textContent=message;$('cloud-toast').hidden=false;clearTimeout(cloudToast.timer);cloudToast.timer=setTimeout(()=>$('cloud-toast').hidden=true,15000);}
$('cloud-toast-close').onclick=()=>$('cloud-toast').hidden=true;
$('favorites-filter').onclick=()=>{favoritesOnly=!favoritesOnly;$('favorites-filter').setAttribute('aria-pressed',String(favoritesOnly));renderLibrary();};
$('cloud-upload').onclick=async()=>{if(working)return;working++;try{const result=await window.wave.cloudUpload();cloudToast(`${result.changed} canciones actualizadas en la nube. Puedes deshacer durante 30 minutos.`);}catch(error){notice(error);}finally{working--;}};
$('cloud-download').onclick=async()=>{if(working)return;working++;notice('Descargando y verificando música…','loading');try{const result=await window.wave.cloudDownload();adoptLocal(result.library);await showSource('local');await syncLikes();cloudToast(`${result.changed} canciones actualizadas en este Mac. Deshacer disponible durante 30 minutos.`);}catch(error){notice(error);}finally{working--;renderLibrary();}};
$('cloud-undo-local').onclick=async()=>{try{adoptLocal(await window.wave.cloudUndoLocal());cloudToast('Descarga deshecha.');}catch(error){notice(error);}};
$('cloud-history').onclick=async()=>{try{const values=await window.wave.cloudHistory();$('cloud-operations').replaceChildren();for(const value of values){const row=element('div');row.append(element('span',`${value.changed} cambios · hasta ${new Date(value.expires*1000).toLocaleTimeString()}`),action('Deshacer',async()=>{try{await window.wave.cloudUndo(value.id);await loadServer();$('cloud-history').click();cloudToast('Actualización del servidor deshecha. Actualiza tus dispositivos.');}catch(error){notice(error);}}));$('cloud-operations').append(row);}if(!values.length)$('cloud-operations').textContent='No hay actualizaciones recuperables.';}catch(error){notice(error);}};
let discoverTracks=[],discoverIndex=0,discoverSource='server';
function currentDiscover(){return discoverTracks[discoverIndex];}
async function renderDiscover(){const track=currentDiscover();$('discover-title').textContent=track?`${track.name} · ${track.folder}`:'Has recorrido esta playlist.';for(const id of ['discover-play','discover-skip','discover-like','discover-move'])$(id).disabled=!track;if(track){await playTrack(track,discoverSource);const cover=await trackArtwork(track,discoverSource);if(currentDiscover()?.id===track.id){$('discover-art').hidden=!cover;if(cover)$('discover-art').src=cover;}}}
$('discover-start').onclick=async()=>{try{await syncLikes();discoverSource=source;const folder=$('discover-category').value;if(!folder)throw new Error('Elige una carpeta con música.');
 if(source==='server'){const all=await window.wave.serverTracks('*');libraries.server.tracks=all;}
 const hidden=new Set(lib().state.hidden);discoverTracks=lib().tracks.filter(t=>(t.folderPath===folder||t.folderPath.startsWith(folder+'/'))&&!hidden.has(t.relPath)&&!sharedLikes[t.cloudPath||t.relPath]);for(let i=discoverTracks.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[discoverTracks[i],discoverTracks[j]]=[discoverTracks[j],discoverTracks[i]];}discoverIndex=0;$('discover-dialog').showModal();await renderDiscover();}catch(error){notice(error);}};
$('discover-play').onclick=togglePlayback;
$('discover-skip').onclick=()=>{discoverIndex++;renderDiscover().catch(error=>notice(error));};
$('discover-like').onclick=async()=>{const track=currentDiscover();if(!track)return;try{await setFavorite(track,discoverSource,true);discoverIndex++;await renderDiscover();}catch(error){cloudToast(error.message);}};
$('discover-close').onclick=()=>$('discover-dialog').close();
$('discover-move').onclick=async()=>{try{const values=await window.wave.serverFolders();$('relocate-folder').replaceChildren();for(const folder of values.folders.filter(f=>f.path)){const option=element('option',folder.name);option.value=folder.path;$('relocate-folder').append(option);} $('relocate-dialog').showModal();}catch(error){cloudToast(error.message);}};
$('relocate-close').onclick=()=>$('relocate-dialog').close();
$('relocate-confirm').onclick=async()=>{const track=currentDiscover();if(!track)return;$('relocate-confirm').disabled=true;try{const result=await window.wave.relocate(track.cloudPath||track.relPath,$('relocate-folder').value);$('relocate-dialog').close();cloudToast(`Canción enviada a ${$('relocate-folder').value}. Actualiza la copia local para descargar su nueva ubicación.`);discoverIndex++;await renderDiscover();libraries.server.loaded=false;}catch(error){cloudToast(error.message);}finally{$('relocate-confirm').disabled=false;}};
window.addEventListener('focus',syncLikes);
setInterval(()=>{if(!document.hidden)syncLikes();},15000);

function updatePlayerHeart(){const track=playing?.track;$('player-like').disabled=!track;$('player-like').textContent=track&&sharedLikes[track.cloudPath||track.relPath]?'♥':'♡';$('player-like').setAttribute('aria-pressed',String(Boolean(track&&sharedLikes[track.cloudPath||track.relPath])));}
$('player-like').onclick=()=>{if(playing)setFavorite(playing.track,playing.source).catch(()=>{});};window.addEventListener('wave-track',updatePlayerHeart);
$('discover-back-ten').onclick=()=>audio.currentTime=Math.max(0,audio.currentTime-10);
$('discover-forward-ten').onclick=()=>{if(Number.isFinite(audio.duration))audio.currentTime=Math.min(audio.duration,audio.currentTime+10);};
$('discover-seek').oninput=()=>{if(Number.isFinite(audio.duration))audio.currentTime=Number($('discover-seek').value)/1000*audio.duration;};
audio.addEventListener('timeupdate',()=>{if(Number.isFinite(audio.duration))$('discover-seek').value=audio.currentTime/audio.duration*1000;});
$('discover-dialog').addEventListener('keydown',event=>{if(event.target.matches('input,select'))return;if(event.key==='ArrowLeft'){$('discover-skip').click();event.preventDefault();}if(event.key==='ArrowRight'){$('discover-like').click();event.preventDefault();}});
const systemDark=matchMedia('(prefers-color-scheme: dark)');
function applyTheme(){const mode=$('appearance').value;document.documentElement.dataset.theme=mode==='system'?(systemDark.matches?'dark':'light'):mode;document.documentElement.dataset.accent=$('accent').value;localStorage.setItem('wave_appearance',mode);localStorage.setItem('wave_accent',$('accent').value);}
$('appearance').value=localStorage.getItem('wave_appearance')||'system';$('accent').value=localStorage.getItem('wave_accent')||'system';$('appearance').onchange=$('accent').onchange=applyTheme;systemDark.addEventListener('change',applyTheme);applyTheme();
