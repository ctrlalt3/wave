const navigationHistory=[];
let navigationIndex=-1,restoringNavigation=false,navigationGeneration=0,lastGestureNavigation=0;
function navigationSnapshot(){
  const library=lib();return{source,path:library?.path||'',all:Boolean(library?.all),view,layout:browserLayout,song:!$('song-view').hidden,query:$('search').value,sort:$('sort').value,scroll:window.scrollY};
}
function routeKey(route){return JSON.stringify([route.source,route.path,route.all,route.view,route.layout,route.song]);}
function beginNavigation(){
  if(restoringNavigation||navigationIndex<0)return;
  navigationHistory[navigationIndex]=navigationSnapshot();
}
function recordNavigation(){
  if(restoringNavigation)return;const next=navigationSnapshot(),previous=navigationHistory[navigationIndex];
  if(previous&&routeKey(previous)===routeKey(next)){navigationHistory[navigationIndex]=next;updateNavigationButtons();return;}
  navigationHistory.splice(navigationIndex+1);navigationHistory.push(next);
  if(navigationHistory.length>120)navigationHistory.shift();navigationIndex=navigationHistory.length-1;
  updateNavigationButtons();window.dispatchEvent(new CustomEvent('wave-navigation',{detail:{direction:1}}));
}
function updateNavigationButtons(){
  $('navigate-back').disabled=restoringNavigation||navigationIndex<=0;
  $('navigate-forward').disabled=restoringNavigation||navigationIndex>=navigationHistory.length-1;
  const labels={server:'Servidor Wave',local:'Música de este Mac',spotify:'Spotify',settings:'Ajustes'},route=navigationSnapshot();
  $('navigation-location').textContent=route.song?'Ahora suena':route.all?'Todas las canciones':route.path.split('/').pop()||labels[source];
}
async function moveNavigation(delta,input='pointer'){
  if(restoringNavigation||![-1,1].includes(delta))return;
  const destination=navigationIndex+delta;if(destination<0||destination>=navigationHistory.length)return;
  if(input==='gesture'&&performance.now()-lastGestureNavigation<650)return;
  if(input==='gesture')lastGestureNavigation=performance.now();
  beginNavigation();const previous=navigationIndex,route={...navigationHistory[destination]},generation=++navigationGeneration;
  restoringNavigation=true;navigationIndex=destination;updateNavigationButtons();
  try{
    if(source!==route.source){await window.wave.switchSource(route.source);await sourceTransition;if(source!==route.source)await showSource(route.source);}
    if(generation!==navigationGeneration)return;
    view=route.view;browserLayout=route.layout;localStorage.setItem('wave_view',view);localStorage.setItem('wave_browser_layout',browserLayout);
    $('sort').value=route.sort;$('search').value=route.query;
    if(lib()){
      const path=lib().folders.some(folder=>folder.path===route.path)?route.path:'';
      await navigate(path,route.all);
    }else await showSource(route.source);
    if(generation!==navigationGeneration)return;
    if(route.song&&playing){songOpen=true;for(const id of ['library','spotify','settings'])$(id).hidden=true;$('song-view').hidden=false;renderSong();}
    else{songOpen=false;$('song-view').hidden=true;$('library').hidden=!lib();$('spotify').hidden=source!=='spotify';$('settings').hidden=source!=='settings';}
    window.scrollTo({top:route.scroll,behavior:'instant'});navigationHistory[navigationIndex]=navigationSnapshot();
    window.dispatchEvent(new CustomEvent('wave-navigation',{detail:{direction:delta,input}}));
    if(input==='gesture')showGestureFeedback(delta);
  }catch(error){navigationIndex=previous;notice(error);}
  finally{if(generation===navigationGeneration){restoringNavigation=false;updateNavigationButtons();}}
}
function showGestureFeedback(delta){ /* Navigation is immediate, including gestures. */ }
$('navigate-back').addEventListener('click',()=>moveNavigation(-1));$('navigate-forward').addEventListener('click',()=>moveNavigation(1));
window.wave.onNavigate(request=>moveNavigation(typeof request==='number'?request:request.delta,typeof request==='number'?'keyboard':'gesture'));
document.addEventListener('keydown',event=>{
  if(isEditingText())return;
  const delta=event.altKey&&!event.ctrlKey&&!event.metaKey?(event.key==='ArrowLeft'?-1:event.key==='ArrowRight'?1:0):(event.metaKey||event.ctrlKey)?(event.key==='['?-1:event.key===']'?1:0):0;
  if(delta){event.preventDefault();moveNavigation(delta,'keyboard');}
});
document.addEventListener('auxclick',event=>{if(event.button===3||event.button===4){event.preventDefault();moveNavigation(event.button===3?-1:1);}});
function gestureBlocked(target){
  if(!(target instanceof Element)||!target.closest('main')||target.closest('input,select,textarea,[contenteditable="true"]'))return true;
  for(let node=target;node&&node!==document.body;node=node.parentElement){if(node.scrollWidth>node.clientWidth+2&&['auto','scroll'].includes(getComputedStyle(node).overflowX))return true;}
  return false;
}
let wheelDistance=0,wheelTimer,wheelLocked=false;
document.addEventListener('wheel',event=>{
  if(event.ctrlKey||gestureBlocked(event.target)||Math.abs(event.deltaX)<=Math.abs(event.deltaY)*1.35)return;
  clearTimeout(wheelTimer);wheelTimer=setTimeout(()=>{wheelDistance=0;wheelLocked=false;},180);
  if(wheelLocked)return;
  const delta=event.deltaX*(event.deltaMode===1?16:event.deltaMode===2?window.innerWidth:1);
  wheelDistance=Math.sign(wheelDistance)===Math.sign(delta)?wheelDistance+delta:delta;
  const direction=wheelDistance<0?-1:1;
  const canNavigate=direction<0?navigationIndex>0:navigationIndex<navigationHistory.length-1;
  if(!canNavigate)return;event.preventDefault();
  if(Math.abs(wheelDistance)>=90){wheelLocked=true;moveNavigation(direction,'gesture');}
},{passive:false});
let touchStart=null,suppressClickUntil=0;
document.addEventListener('pointerdown',event=>{if(event.pointerType==='touch'&&event.isPrimary&&!gestureBlocked(event.target))touchStart={id:event.pointerId,x:event.clientX,y:event.clientY};});
document.addEventListener('pointercancel',()=>{touchStart=null;});
document.addEventListener('pointerup',event=>{
  if(!touchStart||event.pointerId!==touchStart.id)return;
  const dx=event.clientX-touchStart.x,dy=event.clientY-touchStart.y;touchStart=null;
  if(Math.abs(dx)>=75&&Math.abs(dx)>Math.abs(dy)*1.5){suppressClickUntil=performance.now()+400;moveNavigation(dx>0?-1:1,'gesture');}
});
document.addEventListener('click',event=>{if(performance.now()<suppressClickUntil&&event.detail>0){event.preventDefault();event.stopImmediatePropagation();}},true);
