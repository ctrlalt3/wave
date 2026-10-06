const {spawnSync}=require('node:child_process');
const fs=require('node:fs');const path=require('node:path');
const root=path.join(__dirname,'..');
if(process.platform==='darwin'){for(const folder of ['mac-arm64','mac']){const result=spawnSync('/usr/bin/codesign',['--verify','--deep','--strict',path.join(root,'dist',folder,'Wave.app')],{stdio:'inherit'});if(result.status!==0)throw Error(`Firma no válida: ${folder}`);}process.exit(0);}
const tool=process.env.WAVE_RCODESIGN||path.join(root,'tools/apple-codesign-0.29.0-x86_64-unknown-linux-musl/rcodesign');
if(!fs.existsSync(tool))throw Error('rcodesign no está instalado. Configura WAVE_RCODESIGN con su ruta.');
const entitlements=path.join(root,'build/entitlements.mac.plist');
for(const folder of ['mac-arm64','mac']){
 const bundle=path.join(root,'dist',folder,'Wave.app');
 const args=['sign','--timestamp-url','none','--code-signature-flags','runtime','--entitlements-xml-file',entitlements];
 const frameworks=path.join(bundle,'Contents/Frameworks');
 for(const entry of fs.readdirSync(frameworks))if(entry.endsWith('.app'))args.push('--code-signature-flags',`Contents/Frameworks/${entry}:runtime`,'--entitlements-xml-file',`Contents/Frameworks/${entry}:${entitlements}`);
 args.push(bundle);
 const result=spawnSync(tool,args,{stdio:'inherit'});
 if(result.error)throw result.error;if(result.status!==0)throw Error(`No se pudo firmar ${folder}.`);
 console.log(`${folder}: firma ad hoc aplicada al bundle y sus componentes.`);
}
