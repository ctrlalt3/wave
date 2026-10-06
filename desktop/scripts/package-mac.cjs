const {spawnSync} = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');
const version = require('../package.json').version;
const release = process.env.WAVE_RELEASE_DIR || path.join(__dirname, '..', 'dist');
fs.mkdirSync(release, {recursive: true});
for (const [arch, folder] of [['arm64', 'mac-arm64'], ['x64', 'mac']]) {
  const base = path.join(__dirname, '..', 'dist', folder);
  const bundle = path.join(base, 'Wave.app');
  if (!fs.existsSync(bundle)) throw new Error(`Falta el bundle ${bundle}. Genera primero las apps de macOS.`);
  const output = path.resolve(release, `Wave-${version}-${arch}-mac.zip`);
  const temp = `${output}.tmp.zip`;
  fs.rmSync(temp, {force: true});
  const result = process.platform === 'darwin'
    ? spawnSync('ditto', ['-c', '-k', '--sequesterRsrc', '--keepParent', bundle, temp], {stdio: 'inherit'})
    : spawnSync('zip', ['-r', '-y', '-q', '-6', temp, 'Wave.app'], {cwd: base, stdio: 'inherit'});
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`El empaquetado ${arch} falló: ${result.status}`);
  fs.renameSync(temp, output);
  console.log(`${output} (${Math.round(fs.statSync(output).size / 1048576)} MiB)`);
}
