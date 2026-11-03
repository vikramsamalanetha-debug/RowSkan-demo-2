import {validateGps} from './geo.mjs';
const encoder=new TextEncoder(), decoder=new TextDecoder();
const b64=bytes=>{let text='';for(let i=0;i<bytes.length;i+=8192)text+=String.fromCharCode(...bytes.subarray(i,i+8192));return btoa(text)};
const unb64=text=>Uint8Array.from(atob(text),c=>c.charCodeAt(0));
async function derive(password,salt){
 const raw=await crypto.subtle.importKey('raw',encoder.encode(password),'PBKDF2',false,['deriveKey']);
 return crypto.subtle.deriveKey({name:'PBKDF2',hash:'SHA-256',salt,iterations:210000},raw,{name:'AES-GCM',length:256},false,['encrypt','decrypt']);
}
export async function sealBackup(payload,password){
 if(typeof password!=='string'||password.length<12)throw Error('Use at least 12 characters for your backup password.');
 const salt=crypto.getRandomValues(new Uint8Array(16)),iv=crypto.getRandomValues(new Uint8Array(12));
 const bytes=encoder.encode(JSON.stringify(payload));
 if(bytes.length>100*1024*1024)throw Error('Backup exceeds the 100 MB browser limit.');
 const ciphertext=await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:encoder.encode('RowSkan browser backup v1')},await derive(password,salt),bytes);
 return {format:'rowskan-web-encrypted',version:1,iterations:210000,salt:b64(salt),iv:b64(iv),ciphertext:b64(new Uint8Array(ciphertext))};
}
export async function openBackup(input,password){
 if(input?.format!=='rowskan-web-encrypted'||input.version!==1||input.iterations!==210000)throw Error('Unsupported browser backup.');
 if(typeof input.ciphertext!=='string'||input.ciphertext.length>140*1024*1024)throw Error('Backup is too large.');
 const salt=unb64(input.salt),iv=unb64(input.iv);
 if(salt.length!==16||iv.length!==12)throw Error('Invalid backup.');
 try{
  const plain=await crypto.subtle.decrypt({name:'AES-GCM',iv,additionalData:encoder.encode('RowSkan browser backup v1')},await derive(password,salt),unb64(input.ciphertext));
  return JSON.parse(decoder.decode(plain));
 }catch{throw Error('Wrong password or damaged backup. Inventory was not changed.');}
}
export function validateImport(input,existing=[]){
 if(input?.format!=='rowskan-backup'||input.version!==1||!Array.isArray(input.vehicles)||input.vehicles.length>10000)throw Error('Unsupported inventory backup.');
 const ids=new Set(existing.map(v=>v.id)),vins=new Set(existing.map(v=>v.vin).filter(Boolean)),result=[];
 const statuses=['Available','In storage','For parts','Released'];
 for(const item of input.vehicles){
  if(!item||typeof item.id!=='string'||!/^[A-Za-z0-9_-]{1,80}$/.test(item.id)||!Array.isArray(item.photos)||item.photos.length>12)throw Error('Invalid vehicle record.');
  const v={id:item.id,created:Number(item.created)||Date.now(),stock:String(item.stock||'Imported').slice(0,60),photos:item.photos,sample:!!item.sample};
  for(const f of ['vin','year','make','model','color','mileage','location','keys','notes','status']){
   if(item[f]!=null&&!['string','number'].includes(typeof item[f]))throw Error('Invalid vehicle field.');
   v[f]=String(item[f]??'').trim();if(v[f].length>(f==='notes'?8000:160))throw Error('Vehicle field is too long.');
  }
  v.gps=validateGps(item.gps);
  v.vin=v.vin.toUpperCase();
  if(v.vin&&!/^[A-HJ-NPR-Z0-9]{17}$/.test(v.vin))throw Error('Invalid VIN.');
  if(!v.make||!v.model||!statuses.includes(v.status))throw Error('Vehicle details are incomplete.');
  if(v.year&&(!/^\d{4}$/.test(v.year)||Number(v.year)<1886||Number(v.year)>2100))throw Error('Invalid year.');
  if(v.mileage&&(!/^\d+$/.test(v.mileage)||Number(v.mileage)>9999999))throw Error('Invalid mileage.');
  for(const photo of v.photos)if(typeof photo!=='string'||photo.length>6*1024*1024||!/^data:image\/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$/.test(photo))throw Error('Invalid photograph.');
  if(ids.has(v.id)||(v.vin&&vins.has(v.vin)))continue;
  ids.add(v.id);if(v.vin)vins.add(v.vin);result.push(v);
 }
 return result;
}

