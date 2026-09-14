// Run locally in an interactive terminal; no password appears in process arguments or files.
import {randomBytes,pbkdf2Sync} from 'node:crypto';
import {emitKeypressEvents} from 'node:readline';
if(!process.stdin.isTTY){console.error('Lancez ce script dans un terminal interactif.');process.exit(1);}
emitKeypressEvents(process.stdin);process.stdin.setRawMode(true);
let password='',first=null;
console.log('Choisissez une phrase secrète unique (minimum 20 caractères). La saisie est masquée.');
process.stdin.on('keypress',(str,key)=>{
 if(key.ctrl&&key.name==='c'){process.stdin.setRawMode(false);process.exit(1);}
 if(key.name==='return'){
  if(password.length<20){console.log('Minimum 20 caractères. Recommencez.');password='';return;}
  if(first===null){first=password;password='';console.log('Confirmez la phrase secrète :');return;}
  if(first!==password){first=null;password='';console.log('Les saisies diffèrent. Recommencez :');return;}
  const salt=randomBytes(16),digest=pbkdf2Sync(password,salt,100000,32,'sha256');
  process.stdin.setRawMode(false);console.log('\nÀ enregistrer comme secret ADMIN_PASSWORD_HASH (ne pas publier) :\n'+`pbkdf2-sha256$100000$${salt.toString('hex')}$${digest.toString('hex')}`);process.exit(0);
 }else if(key.name==='backspace'){password=password.slice(0,-1);}else if(!key.ctrl&&!key.meta&&str&&password.length<256){password+=str;}
});
