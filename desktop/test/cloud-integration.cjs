const {app,net}=require('electron');const fs=require('node:fs/promises');const path=require('node:path');const os=require('node:os');const assert=require('node:assert/strict');const {CloudClient}=require('../cloud-client.cjs');const {ServerLibrary}=require('../server-client.cjs');const {scanLibrary}=require('../library.cjs');
app.whenReady().then(async()=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'wave-electron-cloud-'));
 try {
  const music=path.join(root,'Music');await fs.mkdir(music);await fs.writeFile(path.join(music,'song.wav'),'first revision');
  const server=new ServerLibrary('http://127.0.0.1:5099/',(...args)=>net.fetch(...args));
  const mac=new CloudClient(server,path.join(root,'copy'));const uploaded=await mac.upload(await scanLibrary(music));assert.equal(uploaded.changed,1);
  const other=new CloudClient(new ServerLibrary('http://127.0.0.1:5099/',(...args)=>net.fetch(...args)),path.join(root,'other'));
  assert.equal((await other.download()).changed,1);assert.equal(await fs.readFile(path.join(root,'other/Music/song.wav'),'utf8'),'first revision');
  await fs.writeFile(path.join(music,'song.wav'),'second revision');const updated=await mac.upload(await scanLibrary(music));assert.equal(updated.changed,1);
  assert.equal((await other.download()).changed,1);assert.equal(await fs.readFile(path.join(root,'other/Music/song.wav'),'utf8'),'second revision');
  await other.undo();assert.equal(await fs.readFile(path.join(root,'other/Music/song.wav'),'utf8'),'first revision');
  await mac.post('api/cloud/undo/'+updated.id);assert.equal((await other.download()).changed,0);
  console.log('PASS: Electron net.fetch → Flask: subida, descarga, actualización, SHA-256 y deshacer local/servidor entre clientes.');
 }finally{await fs.rm(root,{recursive:true,force:true});}
 app.quit();
}).catch(error=>{console.error(error);app.exit(1);});
