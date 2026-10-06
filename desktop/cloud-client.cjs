const fs = require('node:fs/promises');
const {openAsBlob} = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {Readable} = require('node:stream');
const {pipeline} = require('node:stream/promises');
const {resolveTrack, inside} = require('./library.cjs');
const {safePath} = require('./server-client.cjs');
async function hash(file) {
 const h=crypto.createHash('sha256');const handle=await fs.open(file);
 try {for await(const chunk of handle.createReadStream())h.update(chunk);return h.digest('hex');}finally{await handle.close();}
}
class CloudClient {
 constructor(server,root){this.server=server;this.root=root;this.journal=path.join(root,'.wave-download-undo.json');}
 async post(endpoint,body){return this.server.request(endpoint,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body||{})});}
 async upload(library){
  if(!library.tracks.length)throw new Error('La carpeta no contiene música.');
  const manifest=await this.server.request('api/cloud/manifest');
  const remote=new Map(manifest.tracks.map(t=>[t.path,t.hash]));
  const session=await this.post('api/cloud/upload');let count=0;
  for(const track of library.tracks){
   const cloudPath=track.cloudPath||`${path.basename(library.root)}/${track.relPath}`;
   const file=await resolveTrack(library,track.id);if(remote.get(cloudPath)===await hash(file))continue;count++;
   const body=await openAsBlob(file);
   await this.server.request(`api/cloud/upload/${session.id}?path=${encodeURIComponent(cloudPath)}`,{method:'PUT',body});
  }
  return count?this.post(`api/cloud/upload/${session.id}/commit`):{changed:0,expires:Date.now()/1000+1800,id:''};
 }
 async download(){
  await fs.mkdir(this.root,{recursive:true});
  const manifest=await this.server.request('api/cloud/manifest');
  const indexFile=path.join(this.root,'.wave-cloud-index.json');
  let previous=[];try{previous=JSON.parse(await fs.readFile(indexFile,'utf8'));}catch(e){if(e.code!=='ENOENT')throw e;}
  const backup=path.join(this.root,'.wave-backup-'+crypto.randomUUID());await fs.mkdir(backup);
  const changes=[];
  try{
   for(const track of manifest.tracks){
    if(!safePath(track.path)||track.path.split('/').some(p=>!p||p.startsWith('.'))||!/^[a-f0-9]{64}$/.test(track.hash))throw new Error('Manifiesto no válido.');
    const target=path.join(this.root,track.path);if(!inside(this.root,target))throw new Error('Ruta no válida.');
    await fs.mkdir(path.dirname(target),{recursive:true});
    const realParent=await fs.realpath(path.dirname(target));if(!inside(this.root,realParent))throw new Error('Carpeta no válida.');
    let old=null;try{if((await fs.lstat(target)).isSymbolicLink())throw new Error('Enlace no válido.');old=await hash(target);}catch(e){if(e.code!=='ENOENT')throw e;}
    if(old===track.hash)continue;
    const saved=path.join(backup,String(changes.length));if(old)await fs.copyFile(target,saved);
    const temp=path.join(backup,'new-'+changes.length);
    const response=await this.server.fetch(this.server.url('api/cloud/blob/'+track.hash),{signal:AbortSignal.timeout(300000)});
    if(!response.ok)throw new Error('No se pudo descargar '+track.path);
    await pipeline(Readable.fromWeb(response.body),require('node:fs').createWriteStream(temp,{flags:'wx'}));
    if(await hash(temp)!==track.hash)throw new Error('La descarga no supera la verificación.');
    changes.push({path:track.path,before:old,after:track.hash,saved,temp});
   }
   const wanted=new Set(manifest.tracks.map(t=>t.path));
   for(const old of previous.filter(t=>!wanted.has(t.path))){
    if(!safePath(old.path)||!inside(this.root,path.join(this.root,old.path)))throw new Error('Índice no válido.');
    const target=path.join(this.root,old.path);let before;try{before=await hash(target);}catch(e){if(e.code==='ENOENT')continue;throw e;}
    if(before!==old.hash)throw new Error('La canción eliminada de la nube tiene cambios locales. Consérvala antes de actualizar.');
    const saved=path.join(backup,String(changes.length));await fs.copyFile(target,saved);changes.push({path:old.path,before,after:null,saved});
   }
   if(!changes.length){await fs.writeFile(indexFile,JSON.stringify(manifest.tracks));await fs.rm(backup,{recursive:true,force:true});return {changed:0};}
   const journal={expires:Date.now()+1800000,changes,status:'prepared',previous};
   await fs.writeFile(this.journal,JSON.stringify(journal));
   for(const item of changes){if(item.after===null)await fs.rm(path.join(this.root,item.path));else await fs.rename(item.temp,path.join(this.root,item.path));}
   await fs.writeFile(indexFile,JSON.stringify(manifest.tracks));
   journal.status='committed';await fs.writeFile(this.journal,JSON.stringify(journal));
   return {changed:changes.length,expires:journal.expires};
  }catch(error){
   for(const item of changes){const target=path.join(this.root,item.path);if(item.before)await fs.copyFile(item.saved,target);else await fs.rm(target,{force:true});}
   throw error;
  }
 }
 async recover(){try{const value=JSON.parse(await fs.readFile(this.journal,'utf8'));if(value.status==='prepared'){for(const item of value.changes){const target=path.join(this.root,item.path);if(item.before)await fs.copyFile(item.saved,target);else await fs.rm(target,{force:true});}await fs.writeFile(path.join(this.root,'.wave-cloud-index.json'),JSON.stringify(value.previous||[]));await fs.rm(this.journal);}}catch(e){if(e.code!=='ENOENT')throw e;}}
 async undo(){
  const value=JSON.parse(await fs.readFile(this.journal,'utf8'));
  if(value.status!=='committed'||Date.now()>value.expires)throw new Error('El plazo de 30 minutos ha terminado.');
  for(const item of value.changes){let actual=null;try{actual=await hash(path.join(this.root,item.path));}catch(e){if(e.code!=='ENOENT')throw e;}if(actual!==item.after)throw new Error('Hay cambios posteriores; no se pueden sobrescribir.');}
  for(const item of value.changes){const target=path.join(this.root,item.path);if(item.before)await fs.copyFile(item.saved,target);else await fs.rm(target);}
  await fs.writeFile(path.join(this.root,'.wave-cloud-index.json'),JSON.stringify(value.previous||[]));
  await fs.rm(this.journal);return {ok:true};
 }
}
module.exports={CloudClient,hash};
