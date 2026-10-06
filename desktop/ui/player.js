let browserLayout='columns';
let songOpen=false, waveformKey='', waveformRequest=0, waveformPeaks=null;
function renderBrowser(){
  const advanced=view==='advanced';const columns=advanced&&browserLayout==='columns';$('table-wrap').hidden=columns||!visibleTracks().length;$('view-note').hidden=columns||!visibleTracks().length;$('library').classList.toggle('finder-view',advanced);
  $('browser-tools').hidden=!advanced;$('column-browser').hidden=!advanced||browserLayout!=='columns';
  for(const [id,mode] of [['list-layout','list'],['column-layout','columns']]){$(id).classList.toggle('active',browserLayout===mode);$(id).setAttribute('aria-pressed',String(browserLayout===mode));}
  $('folders').hidden=advanced&&browserLayout==='columns';
  $('column-browser').replaceChildren();if($('column-browser').hidden||!lib())return;
  const library=lib(),parts=library.path.split('/').filter(Boolean),paths=library.all?['*']:['',...parts.map((_,i)=>parts.slice(0,i+1).join('/'))];
  for(const path of paths){
    const column=element('div',undefined,'finder-column');column.append(element('h3',path.split('/').pop()||'Biblioteca'));
    for(const folder of library.folders.filter(item=>!library.all&&item.parent===path)){
      const button=action(undefined,()=>navigate(folder.path),'column-folder');button.append(icon('folder'),element('span',folder.name),icon('arrow-right'));button.classList.toggle('active',library.path===folder.path||library.path.startsWith(folder.path+'/'));column.append(button);
    }
    const hidden=new Set(library.state.hidden);
    for(const track of (library.all?visibleTracks():path===library.path?visibleTracks():library.tracks.filter(item=>item.folderPath===path))){
      const button=action(undefined,async()=>{const which=source;await navigate(library.all?'':path,library.all);if(source===which)playTrack(track);},'column-track');button.dataset.id=track.id;button.append(coverNode(track),element('span',track.name));button.title=[track.filename,track.artist,track.format].filter(Boolean).join(' · ');
      const checkbox=element('input');checkbox.type='checkbox';checkbox.checked=selected.has(track.id);checkbox.setAttribute('aria-label',`Seleccionar ${track.name}`);checkbox.addEventListener('click',event=>event.stopPropagation());checkbox.addEventListener('change',()=>{checkbox.checked?selected.add(track.id):selected.delete(track.id);updateSelection();});button.prepend(checkbox);button.classList.toggle('playing',playing?.source===source&&playing.id===track.id);button.draggable=path===library.path||library.all;
      button.addEventListener('dragstart',event=>{event.dataTransfer.setData('application/x-wave-order',JSON.stringify({id:track.id,source}));event.dataTransfer.effectAllowed='move';button.classList.add('dragging');});
      button.addEventListener('dragend',()=>document.querySelectorAll('.dragging,.drag-target').forEach(node=>node.classList.remove('dragging','drag-target')));
      button.addEventListener('dragover',event=>{if(button.draggable&&event.dataTransfer.types.includes('application/x-wave-order')){event.preventDefault();button.classList.add('drag-target');}});
      button.addEventListener('dragleave',()=>button.classList.remove('drag-target'));
      button.addEventListener('drop',event=>{event.preventDefault();button.classList.remove('drag-target');try{const value=JSON.parse(event.dataTransfer.getData('application/x-wave-order'));if(button.draggable&&value.source===source)reorder(value.id,0,track.id);}catch{notice('No se pudo reordenar esta canción.');}});button.classList.toggle('is-hidden',hidden.has(track.relPath));column.append(button);
    }
    if(column.childElementCount===1)column.append(element('p','Sin elementos','column-empty'));
    $('column-browser').append(column);
  }
  $('column-browser').scrollLeft=$('column-browser').scrollWidth;
}
for(const [id,mode] of [['list-layout','list'],['column-layout','columns']])$(id).addEventListener('click',()=>{beginNavigation();browserLayout=mode;localStorage.setItem('wave_browser_layout',mode);renderBrowser();recordNavigation();});
function timeLabel(value){return Number.isFinite(value)?`${Math.floor(value/60)}:${String(Math.floor(value%60)).padStart(2,'0')}`:'0:00';}
function updateProgress(){
  const duration=Number.isFinite(audio.duration)?audio.duration:0,current=audio.currentTime||0;
  for(const id of ['seek','song-seek']){$(id).disabled=!duration;$(id).value=duration?Math.round(current/duration*1000):0;}
  $('elapsed').textContent=$('song-elapsed').textContent=timeLabel(current);$('duration').textContent=$('song-duration').textContent=timeLabel(duration);
  if(songOpen)drawWaveform();
  if('mediaSession' in navigator&&duration>0)navigator.mediaSession.setPositionState({duration,playbackRate:audio.playbackRate,position:Math.min(current,duration)});
}
function seekTo(value){if(Number.isFinite(audio.duration)&&audio.duration>0)audio.currentTime=Math.max(0,Math.min(audio.duration,value));updateProgress();}
for(const id of ['seek','song-seek'])$(id).addEventListener('input',()=>seekTo(Number($(id).value)/1000*audio.duration));
$('volume').value=localStorage.getItem('wave_volume')||'1';audio.volume=Math.max(0,Math.min(1,Number($('volume').value)));
$('volume').addEventListener('input',()=>{audio.volume=Number($('volume').value);localStorage.setItem('wave_volume',String(audio.volume));});
$('shuffle').addEventListener('click',()=>{shuffle=!shuffle;$('shuffle').setAttribute('aria-pressed',String(shuffle));});
$('repeat').addEventListener('click',()=>{repeat=!repeat;$('repeat').setAttribute('aria-pressed',String(repeat));});
function setCompact(compact){$('player').classList.toggle('compact',compact);$('compact-player').setAttribute('aria-expanded',String(!compact));$('compact-player').setAttribute('aria-label',compact?'Expandir reproductor':'Compactar reproductor');$('compact-player').replaceChildren(icon(compact?'up':'down'));localStorage.setItem('wave_compact',String(compact));}
setCompact(localStorage.getItem('wave_compact')==='true');$('compact-player').addEventListener('click',()=>{const compact=!$('player').classList.contains('compact');setCompact(compact);window.waveMotion?.player(compact);});
function renderSong(){
  const track=playing?.track;$('song-title').textContent=track?.name||'Tu próxima canción';$('song-subtitle').textContent=track?[track.artist,track.folder,track.format,track.size?sizeText(track.size):''].filter(Boolean).join(' · '):'';
  $('song-play').replaceChildren(icon(audio.paused?'play':'pause'));$('song-play').setAttribute('aria-label',audio.paused?'Reproducir':'Pausar');
  for(const id of ['song-play','song-previous','song-next'])$(id).disabled=!playing;
  $('queue-list').replaceChildren();const index=playbackQueue.findIndex(item=>item.id===playing?.id),following=playbackQueue.slice(index+1);$('queue-count').textContent=countText(following.length);
  for(const item of following){const button=action(undefined,()=>playTrack(item,playbackSource,true),'queue-track');const details=element('span');details.append(element('strong',item.name),element('small',item.artist||item.folder));button.append(icon('music'),details,element('small',durationText(item.duration)));$('queue-list').append(button);}
  if(!following.length)$('queue-list').append(element('p','Has llegado al final de la cola.','view-note'));
  if(songOpen)loadWaveform();updateProgress();
}
$('open-song').addEventListener('click',()=>{if(!playing)return;beginNavigation();songOpen=true;for(const id of ['library','spotify','settings'])$(id).hidden=true;$('song-view').hidden=false;renderSong();recordNavigation();$('song-close').focus();});
$('song-close').addEventListener('click',()=>{beginNavigation();songOpen=false;showSource(source);$('open-song').focus();});
$('song-play').addEventListener('click',togglePlayback);$('song-previous').addEventListener('click',()=>step(-1));$('song-next').addEventListener('click',()=>step(1));
window.addEventListener('wave-player',()=>{if($('song-view').hidden)songOpen=false;renderSong();});
window.addEventListener('wave-track',()=>{waveformKey='';waveformPeaks=null;waveformRequest++;renderSong();});
for(const event of ['timeupdate','loadedmetadata','durationchange','seeked'])audio.addEventListener(event,updateProgress);
async function loadWaveform(){
  if(!playing)return;const key=`${playing.source}:${playing.id}`;if(waveformKey===key)return;waveformKey=key;
  const request=++waveformRequest,which=playing.source,id=playing.id;waveformPeaks=null;$('waveform-status').textContent='Analizando el audio…';drawWaveform();let context;
  try{
    const bytes=await window.wave.waveformAudio(which,id);if(request!==waveformRequest)return;
    context=new AudioContext();const buffer=await context.decodeAudioData(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength));if(request!==waveformRequest)return;
    const peaks=new Float32Array(240),stride=Math.max(1,Math.floor(buffer.length/peaks.length));
    for(let channel=0;channel<buffer.numberOfChannels;channel++){const data=buffer.getChannelData(channel);for(let i=0;i<peaks.length;i++){const end=Math.min(data.length,(i+1)*stride);for(let j=i*stride;j<end;j++)peaks[i]=Math.max(peaks[i],Math.abs(data[j]));}}
    waveformPeaks=peaks;$('waveform-status').textContent='Haz clic en la onda para avanzar';drawWaveform();
  }catch(error){if(request===waveformRequest)$('waveform-status').textContent=error.message||'Onda no disponible para este formato.';}
  finally{if(context)await context.close();}
}
function drawWaveform(){
  const canvas=$('waveform'),width=canvas.clientWidth||800,height=160,dpr=window.devicePixelRatio||1;canvas.width=Math.round(width*dpr);canvas.height=height*dpr;
  const ctx=canvas.getContext('2d');ctx.scale(dpr,dpr);ctx.clearRect(0,0,width,height);
  const progress=Number.isFinite(audio.duration)?audio.currentTime/audio.duration:0;
  if(!waveformPeaks){ctx.fillStyle='#d5d8d3';ctx.fillRect(0,height/2,width,1);return;}
  const max=Math.max(...waveformPeaks,0.001),step=width/waveformPeaks.length;
  waveformPeaks.forEach((peak,i)=>{const bar=Math.max(2,peak/max*132);ctx.fillStyle=i/waveformPeaks.length<=progress?'#456f51':'#d1d8ce';ctx.fillRect(i*step,(height-bar)/2,Math.max(1,step-2),bar);});
}
$('waveform').addEventListener('click',event=>{if(!waveformPeaks)return;const rect=$('waveform').getBoundingClientRect();seekTo((event.clientX-rect.left)/rect.width*audio.duration);});
new ResizeObserver(()=>{if(songOpen)drawWaveform();}).observe($('waveform'));
if('mediaSession' in navigator){navigator.mediaSession.setActionHandler('seekto',event=>seekTo(event.seekTime));navigator.mediaSession.setActionHandler('seekbackward',event=>seekTo(audio.currentTime-(event.seekOffset||10)));navigator.mediaSession.setActionHandler('seekforward',event=>seekTo(audio.currentTime+(event.seekOffset||10)));}
document.addEventListener('keydown',event=>{if(event.code==='Space'&&!isEditingText()&&!document.activeElement?.matches('button,input')){event.preventDefault();togglePlayback();}if(event.key==='Escape'&&songOpen)$('song-close').click();});
