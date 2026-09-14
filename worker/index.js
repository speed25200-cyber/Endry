import assets from './assets.js';

// Only the Sites dispatcher may supply these verified identity headers.
// A deployment outside Sites MUST replace admin() with a verified identity provider.
const COOKIE='__Host-endry_chantier';
const ADMIN_COOKIE='__Host-endry_admin';
const DAY=86400000;
const STATUS=['Préparation','En cours','En attente','Terminé'];
const encoder=new TextEncoder();
const uuid=()=>crypto.randomUUID();
const hex=bytes=>Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');
export const hash=async value=>hex(new Uint8Array(await crypto.subtle.digest('SHA-256',encoder.encode(value))));
const token=()=>hex(crypto.getRandomValues(new Uint8Array(32)));
export function newCode(){const alphabet='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';return Array.from(crypto.getRandomValues(new Uint8Array(20)),b=>alphabet[b%32]).join('').match(/.{1,5}/g).join('-');}
export const normalize=value=>String(value||'').toUpperCase().replace(/[\s-]/g,'');
function cookieValue(req,name){return req.headers.get('cookie')?.split(';').map(x=>x.trim()).find(x=>x.startsWith(name+'='))?.slice(name.length+1);}
async function admin(req,env){
 if(env.ADMIN_AUTH_MODE==='sites')return Boolean(env.ADMIN_EMAIL)&&Boolean(req.headers.get('oai-authenticated-user-id'))&&req.headers.get('oai-authenticated-user-email')?.toLowerCase()===env.ADMIN_EMAIL.toLowerCase();
 if(env.ADMIN_AUTH_MODE!=='password'||!env.ADMIN_PASSWORD_HASH)return false;
 const value=cookieValue(req,ADMIN_COOKIE);if(!value||!/^[0-9a-f]{64}$/.test(value))return false;
 return Boolean(await sql(env,'SELECT hash FROM admin_sessions WHERE hash=? AND expires>? AND credential_version=?',await hash(value),Date.now(),await hash(env.ADMIN_PASSWORD_HASH)).first());
}
export async function verifyPassword(password,stored){
 if(typeof password!=='string'||password.length>256||typeof stored!=='string')return false;
 const [scheme,iterations,salt,expected]=stored.split('$');if(scheme!=='pbkdf2-sha256'||iterations!=='100000'||!/^[0-9a-f]{32}$/.test(salt)||!/^[0-9a-f]{64}$/.test(expected))return false;
 const key=await crypto.subtle.importKey('raw',encoder.encode(password),'PBKDF2',false,['deriveBits']);
 const digest=hex(new Uint8Array(await crypto.subtle.deriveBits({name:'PBKDF2',hash:'SHA-256',salt:Uint8Array.from(salt.match(/../g),h=>parseInt(h,16)),iterations:100000},key,256)));
 let difference=0;for(let i=0;i<expected.length;i++)difference|=expected.charCodeAt(i)^digest.charCodeAt(i);return difference===0;
}
function error(status,message){throw Object.assign(new Error(message),{status});}
function json(data,status=200,extra={}){return new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json; charset=utf-8',...extra}});}
function db(env){if(!env.DB||!env.BUCKET)error(503,'Le suivi est temporairement indisponible. Réessayez dans quelques instants.');return env.DB;}
function sql(env,query,...args){return db(env).prepare(query).bind(...args);}
async function requireAdmin(req,env){if(!await admin(req,env))error(403,'Accès réservé à l’administration Endry SA.');}
function text(value,max,required=true){if(typeof value!=='string'||value.length>max||(required&&!value.trim()))error(400,'Vérifiez les champs du formulaire.');return value.trim();}
async function bytes(req,limit){const announced=Number(req.headers.get('content-length'));if(announced>limit)error(413,'Fichier ou demande trop volumineux.');const reader=req.body?.getReader();if(!reader)return new Uint8Array();const chunks=[];let size=0;while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>limit){await reader.cancel();error(413,'Fichier ou demande trop volumineux.');}chunks.push(value);}const result=new Uint8Array(size);let offset=0;for(const chunk of chunks){result.set(chunk,offset);offset+=chunk.length;}return result;}
async function body(req){if(!req.headers.get('content-type')?.startsWith('application/json'))error(415,'Format de demande invalide.');try{const data=JSON.parse(new TextDecoder().decode(await bytes(req,12000)));if(!data||typeof data!=='object'||Array.isArray(data))error(400,'Demande invalide.');return data;}catch(e){if(e.status)throw e;error(400,'Demande invalide.');}}
function csrf(req){if(!['GET','HEAD','OPTIONS'].includes(req.method)){if(req.headers.get('origin')!==new URL(req.url).origin||req.headers.get('sec-fetch-site')==='cross-site')error(403,'Rechargez la page avant de réessayer.');}}
async function limit(env,key,max,window){const now=Date.now();const bucket=Math.floor(now/window);const row=await sql(env,'INSERT INTO limits (key,count,expires) VALUES (?,1,?) ON CONFLICT(key) DO UPDATE SET count=count+1 RETURNING count',key+':'+bucket,now+window).first();if(row.count>max)error(429,'Trop de tentatives. Réessayez un peu plus tard.');}
async function session(req,env){const cookies=req.headers.get('cookie')||'';const value=cookies.split(';').map(x=>x.trim()).find(x=>x.startsWith(COOKIE+'='))?.slice(COOKIE.length+1);if(!value||!/^[0-9a-f]{64}$/.test(value))error(401,'Saisissez votre code personnel pour accéder au chantier.');const p=await sql(env,'SELECT p.* FROM sessions s JOIN projects p ON p.id=s.project_id WHERE s.hash=? AND s.expires>? AND s.version=p.access_version AND p.active=1',await hash(value),Date.now()).first();if(!p)error(401,'Votre accès a expiré ou a été désactivé. Contactez Endry SA si nécessaire.');return p;}
function safeProject(p){return {id:p.id,title:p.title,client:p.client,location:p.location,progress:p.progress,status:p.status,active:Boolean(p.active),created_at:p.created_at,updated_at:p.updated_at};}
async function project(env,id){const p=await sql(env,'SELECT * FROM projects WHERE id=?',id).first();if(!p)error(404,'Chantier introuvable.');return p;}
async function detail(env,p){const [updates,photos]=await Promise.all([sql(env,'SELECT id,body,created_at FROM updates WHERE project_id=? ORDER BY created_at DESC LIMIT 500',p.id).all(),sql(env,'SELECT id,caption,created_at FROM photos WHERE project_id=? ORDER BY created_at DESC LIMIT 500',p.id).all()]);return {project:safeProject(p),updates:updates.results,photos:photos.results};}
const cookie=(value,age)=>`${COOKIE}=${value}; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=${age}`;
async function cleanup(env){await db(env).batch([sql(env,'DELETE FROM sessions WHERE expires<?',Date.now()),sql(env,'DELETE FROM admin_sessions WHERE expires<?',Date.now()),sql(env,'DELETE FROM limits WHERE expires<?',Date.now())]);}

async function route(req,env,ctx){const url=new URL(req.url),path=url.pathname,method=req.method;csrf(req);
 if(path==='/api/auth-mode'&&method==='GET')return json({mode:env.ADMIN_AUTH_MODE==='sites'?'sites':'password'});
 if(path==='/api/admin-login'&&method==='POST'){
  if(env.ADMIN_AUTH_MODE!=='password'||!env.ADMIN_PASSWORD_HASH)error(503,'La connexion administrateur n’est pas configurée.');
  await limit(env,'admin-login:'+await hash(req.headers.get('cf-connecting-ip')||'unknown'),5,900000);
  const data=await body(req);if(!await verifyPassword(data.password,env.ADMIN_PASSWORD_HASH))error(401,'Identifiants invalides.');
  const value=token();await sql(env,'INSERT INTO admin_sessions (hash,expires,credential_version) VALUES (?,?,?)',await hash(value),Date.now()+8*3600000,await hash(env.ADMIN_PASSWORD_HASH)).run();
  ctx.waitUntil(cleanup(env).catch(()=>{}));return json({ok:true},200,{'Set-Cookie':`${ADMIN_COOKIE}=${value}; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=28800`});
 }
 if(path==='/api/admin-logout'&&method==='POST'){const value=cookieValue(req,ADMIN_COOKIE);if(value)await sql(env,'DELETE FROM admin_sessions WHERE hash=?',await hash(value)).run();return json({ok:true},200,{'Set-Cookie':`${ADMIN_COOKIE}=; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=0`});}
 if(path==='/api/login'&&method==='POST'){
  const ip=req.headers.get('cf-connecting-ip')||'unknown';await limit(env,'login:'+await hash(ip),10,600000);
  const input=await body(req),code=normalize(input.code);if(!/^[A-HJ-NP-Z2-9]{20}$/.test(code))error(401,'Code invalide ou accès désactivé.');
  const p=await sql(env,'SELECT * FROM projects WHERE code_hash=? AND active=1',await hash(code)).first();if(!p)error(401,'Code invalide ou accès désactivé.');
  const value=token();await sql(env,'INSERT INTO sessions (hash,project_id,version,expires) VALUES (?,?,?,?)',await hash(value),p.id,p.access_version,Date.now()+14*DAY).run();
  ctx.waitUntil(cleanup(env).catch(()=>{}));return json({ok:true},200,{'Set-Cookie':cookie(value,14*86400)});
 }
 if(path==='/api/logout'&&method==='POST'){const value=req.headers.get('cookie')?.split(';').map(x=>x.trim()).find(x=>x.startsWith(COOKIE+'='))?.slice(COOKIE.length+1);if(value)await sql(env,'DELETE FROM sessions WHERE hash=?',await hash(value)).run();return json({ok:true},200,{'Set-Cookie':cookie('',0)});}
 if(path==='/api/chantier'&&method==='GET')return json(await detail(env,await session(req,env)));
 if(path==='/api/admin/me'&&method==='GET'){await requireAdmin(req,env);return json({ok:true});}
 if(path.startsWith('/api/admin/')){
  await requireAdmin(req,env);
  if(method!=='GET')await limit(env,'admin-write',240,600000);
  if(path==='/api/admin/projects'&&method==='GET'){const result=await sql(env,'SELECT * FROM projects ORDER BY updated_at DESC LIMIT 500').all();return json(result.results.map(safeProject));}
  if(path==='/api/admin/projects'&&method==='POST'){
   const data=await body(req),id=uuid(),code=newCode(),now=Date.now();
   await sql(env,'INSERT INTO projects (id,title,client,location,code_hash,created_at,updated_at) VALUES (?,?,?,?,?,?,?)',id,text(data.title,160),text(data.client,120),text(data.location,180,false),await hash(normalize(code)),now,now).run();return json({id,code},201);
  }
  const match=path.match(/^\/api\/admin\/projects\/([0-9a-f-]{36})(?:\/(code|updates|photos))?$/);
  if(match){const [,id,action]=match,p=await project(env,id);
   if(!action&&method==='GET')return json(await detail(env,p));
   if(!action&&method==='PATCH'){const d=await body(req);if(!Number.isInteger(d.progress)||d.progress<0||d.progress>100||!STATUS.includes(d.status)||typeof d.active!=='boolean')error(400,'Avancement ou statut invalide.');const version=p.access_version+(Number(d.active)!==p.active?1:0);await sql(env,'UPDATE projects SET title=?,client=?,location=?,progress=?,status=?,active=?,access_version=?,updated_at=? WHERE id=?',text(d.title,160),text(d.client,120),text(d.location,180,false),d.progress,d.status,Number(d.active),version,Date.now(),id).run();return json({ok:true});}
   if(action==='code'&&method==='POST'){const code=newCode();await db(env).batch([sql(env,'UPDATE projects SET code_hash=?,access_version=access_version+1,updated_at=? WHERE id=?',await hash(normalize(code)),Date.now(),id),sql(env,'DELETE FROM sessions WHERE project_id=?',id)]);return json({code});}
   if(action==='updates'&&method==='POST'){const data=await body(req),now=Date.now();await db(env).batch([sql(env,'INSERT INTO updates (id,project_id,body,created_at) VALUES (?,?,?,?)',uuid(),id,text(data.body,3000),now),sql(env,'UPDATE projects SET updated_at=? WHERE id=?',now,id)]);return json({ok:true},201);}
   if(action==='photos'&&method==='POST'){
    const count=await sql(env,'SELECT count(*) AS count FROM photos WHERE project_id=?',id).first();if(count.count>=500)error(409,'La limite de 500 photos par chantier est atteinte.');
    await limit(env,'uploads',100,DAY);
    const raw=await bytes(req,8*1024*1024);let mime;
    if(raw[0]===255&&raw[1]===216&&raw[2]===255)mime='image/jpeg';
    else if([137,80,78,71,13,10,26,10].every((v,i)=>raw[i]===v))mime='image/png';
    else if(new TextDecoder().decode(raw.slice(0,4))==='RIFF'&&new TextDecoder().decode(raw.slice(8,12))==='WEBP')mime='image/webp';
    else error(415,'Choisissez une photo JPEG, PNG ou WebP.');
    const caption=text(url.searchParams.get('caption')||'',240,false),photoId=uuid(),key='chantiers/'+id+'/'+photoId,now=Date.now();
    await env.BUCKET.put(key,raw,{httpMetadata:{contentType:mime}});
    try{await db(env).batch([sql(env,'INSERT INTO photos (id,project_id,object_key,caption,mime,size,created_at) VALUES (?,?,?,?,?,?,?)',photoId,id,key,caption,mime,raw.length,now),sql(env,'UPDATE projects SET updated_at=? WHERE id=?',now,id)]);}catch(e){await env.BUCKET.delete(key).catch(()=>{});throw e;}
    return json({id:photoId},201);
   }
  }
  const photoMatch=path.match(/^\/api\/admin\/photos\/([0-9a-f-]{36})$/);
  if(photoMatch&&method==='DELETE'){const photo=await sql(env,'SELECT * FROM photos WHERE id=?',photoMatch[1]).first();if(!photo)error(404,'Photo introuvable.');await env.BUCKET.delete(photo.object_key);await db(env).batch([sql(env,'DELETE FROM photos WHERE id=?',photo.id),sql(env,'UPDATE projects SET updated_at=? WHERE id=?',Date.now(),photo.project_id)]);return json({ok:true});}
  error(404,'Page introuvable.');
 }
 const photoMatch=path.match(/^\/api\/photos\/([0-9a-f-]{36})$/);
 if(photoMatch&&method==='GET'){const viewer=await admin(req,env)?null:await session(req,env);const photo=await sql(env,'SELECT * FROM photos WHERE id=?',photoMatch[1]).first();if(!photo||viewer&&viewer.id!==photo.project_id)error(404,'Photo introuvable.');const file=await env.BUCKET.get(photo.object_key);if(!file)error(404,'Photo indisponible.');return new Response(file.body,{headers:{'Content-Type':photo.mime,'Content-Disposition':'inline'}});}
 if(path.startsWith('/api/'))error(404,'Page introuvable.');
 if(!['GET','HEAD'].includes(method))error(405,'Méthode non autorisée.');
 const key=path==='/'?'/index.html':['/suivi','/suivi/','/admin','/admin/'].includes(path)?'/portail.html':path;
 const asset=assets[key];if(!asset)error(404,'Page introuvable.');const binary=Uint8Array.from(atob(asset[1]),c=>c.charCodeAt(0));return new Response(method==='HEAD'?null:binary,{headers:{'Content-Type':asset[0]}});
}
export default {async fetch(req,env,ctx){let response;try{response=await route(req,env,ctx);}catch(e){if(!e.status)console.error('endry_request_failed',{path:new URL(req.url).pathname,message:e.message});response=json({error:e.status?e.message:'Le service est temporairement indisponible. Votre demande n’a pas pu être confirmée. Réessayez.'},e.status||503);}
 const h=new Headers(response.headers);h.set('Cache-Control','private, no-store');h.set('X-Content-Type-Options','nosniff');h.set('Referrer-Policy','no-referrer');h.set('X-Frame-Options','DENY');h.set('Permissions-Policy','camera=(), microphone=(), geolocation=()');
 if(new URL(req.url).pathname.startsWith('/api/')||['/suivi','/admin','/portail.html'].includes(new URL(req.url).pathname)){h.set('X-Robots-Tag','noindex, nofollow');h.set('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' blob: data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");}
 return new Response(response.body,{status:response.status,headers:h});}};
