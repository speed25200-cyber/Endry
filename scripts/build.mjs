import {mkdir,readFile,writeFile,readdir,cp} from 'node:fs/promises';
import {join,extname} from 'node:path';
const types={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8','.txt':'text/plain; charset=utf-8','.png':'image/png','.webp':'image/webp','.pdf':'application/pdf','.woff2':'font/woff2','.svg':'image/svg+xml'};
const assets={};
async function walk(dir,prefix=''){for(const entry of await readdir(dir,{withFileTypes:true})){const path=join(dir,entry.name),key=prefix+'/'+entry.name;if(entry.isDirectory())await walk(path,key);else assets[key]=[types[extname(path)]||'application/octet-stream',(await readFile(path)).toString('base64')];}}
await walk('public');
await mkdir('dist/server',{recursive:true});
await mkdir('dist/.openai',{recursive:true});
await writeFile('dist/server/assets.js','export default '+JSON.stringify(assets)+';\n');
await cp('worker/index.js','dist/server/index.js');
// The standalone GitHub distribution has no ChatGPT Site identity.
try{await cp('.openai/hosting.json','dist/.openai/hosting.json');}catch(e){if(e.code!=='ENOENT')throw e;await writeFile('dist/.openai/hosting.json',JSON.stringify({d1:'DB',r2:'BUCKET'}));}
await cp('drizzle','dist/.openai/drizzle',{recursive:true});
console.log('Worker + '+Object.keys(assets).length+' ressources publiques. Photos clients exclusivement en stockage privé.');
