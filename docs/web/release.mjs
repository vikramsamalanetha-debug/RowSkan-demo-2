import {sealBackup,openBackup,validateImport} from './backup-crypto.mjs';

const byId=id=>document.getElementById(id);
const originalNotify=notify;
notify=function(message){(document.querySelector('dialog[open]')||document.body).append(byId('toast'));originalNotify(message);};
const showError=e=>notify(e instanceof Error?e.message:String(e));
function download(data,name){const url=URL.createObjectURL(new Blob([JSON.stringify(data)],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
function secretDialog(creating){
 return new Promise(resolve=>{
  const dialog=document.createElement('dialog');
  dialog.innerHTML=`<h2>${creating?'Protect your backup':'Unlock your backup'}</h2><p>Keep the password safely. We cannot recover it.</p><form><label>Backup password<input name="password" type="password" autocomplete="off" required ${creating?'minlength="12"':''} style="width:100%;margin-top:8px"></label>${creating?'<label>Confirm password<input name="confirm" type="password" autocomplete="off" required style="width:100%;margin-top:8px"></label>':''}<p class="hint" role="status"></p><div class="actions"><button type="button">Cancel</button><button class="primary">${creating?'Export':'Unlock'}</button></div></form>`;
  document.body.append(dialog);let value=null;
  dialog.querySelector('[type="button"]').onclick=()=>dialog.close();
  dialog.querySelector('form').onsubmit=e=>{e.preventDefault();const input=dialog.querySelector('[name="password"]');if(creating&&input.value!==dialog.querySelector('[name="confirm"]').value){dialog.querySelector('[role="status"]').textContent='Passwords do not match.';return}value=input.value;dialog.close();};
  dialog.onclose=()=>{dialog.remove();resolve(value)};dialog.showModal();
 });
}
byId('export').onclick=async()=>{
 const password=await secretDialog(true);if(password===null)return;
 const button=byId('export');button.disabled=true;
 try{await refresh();const data=await sealBackup({format:'rowskan-backup',version:1,exported:new Date().toISOString(),vehicles},password);download(data,'RowSkan-browser-backup-'+new Date().toISOString().slice(0,10)+'.rowskan-web');notify('Encrypted browser backup exported.');localStorage.setItem('rowskan-last-backup',new Date().toISOString());}
 catch(e){showError(e)}finally{button.disabled=false}
};
byId('importfile').accept='.rowskan-web,.json,application/json';
byId('importfile').onchange=async e=>{
 try{
  const file=e.target.files[0];if(!file)return;if(file.size>140*1024*1024)throw Error('Backup exceeds the browser import limit.');
  let data=JSON.parse(await file.text());
  if(data.format==='rowskan-web-encrypted'){const password=await secretDialog(false);if(password===null)return;data=await openBackup(data,password);}
  await refresh();const additions=validateImport(data,vehicles);
  await tx('readwrite',store=>additions.forEach(v=>store.add(v)));
  await refresh();notify(`${additions.length} vehicles imported. Existing records preserved.`);
 }catch(e){showError(e)}finally{e.target.value=''}
};
const rawSubmit=byId('form').onsubmit;
let loadedVersion=null;
byId('form').onsubmit=async e=>{
 e.preventDefault();const vin=byId('vin').value.trim().toUpperCase();
 if(vin&&!/^[A-HJ-NPR-Z0-9]{17}$/.test(vin)){notify('Enter a 17-character VIN or leave it blank.');setStep(0);return;}
 if(step===1&&editing){
  const current=await new Promise((resolve,reject)=>{const r=db.transaction('vehicles').objectStore('vehicles').get(editing);r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)});
  if(!current||JSON.stringify(current)!==loadedVersion){notify('This record changed in another tab. Reopen it before saving.');return;}
 }
 isSaving=true;clearTimeout(draftTimer);
 try{await draftWrites;await rawSubmit(e);if(!byId('editor').open)await dropDraft(draftKey());}
 catch(e){showError(e)}finally{isSaving=false}
};
let draftTimer,isSaving=false,draftWrites=Promise.resolve(),draftReady=false;
const draftKey=()=>editing?'edit-'+editing:'new-vehicle';
const draftTx=fn=>new Promise((resolve,reject)=>{const t=db.transaction('drafts','readwrite');fn(t.objectStore('drafts'));t.oncomplete=resolve;t.onerror=()=>reject(t.error);t.onabort=()=>reject(t.error)});
const dropDraft=id=>draftTx(s=>s.delete(id));
function persistDraft(){
 if(!draftReady||isSaving||!byId('editor').open)return draftWrites;
 const data={id:draftKey(),fields:Object.fromEntries(fields.map(f=>[f,byId(f).value])),photos:[...draftPhotos],step,base:loadedVersion};
 draftWrites=draftWrites.catch(()=>{}).then(()=>draftTx(s=>s.put(data)));
 draftWrites.catch(()=>notify('Draft could not be saved. Check browser storage.'));
 return draftWrites;
}
function scheduleDraft(){clearTimeout(draftTimer);draftTimer=setTimeout(persistDraft,250);}
const rawOpen=openEditor;
openEditor=async function(vehicle=null){
 draftReady=false;loadedVersion=vehicle?JSON.stringify(vehicle):null;rawOpen(vehicle);byId('next').disabled=true;
 try{
  await draftWrites;
  const draft=await new Promise((resolve,reject)=>{const r=db.transaction('drafts').objectStore('drafts').get(draftKey());r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)});
  if(draft){if(vehicle)loadedVersion=draft.base??null;for(const f of fields)byId(f).value=draft.fields[f]??'';draftPhotos=[...draft.photos];setStep(draft.step===1?1:0);thumbs();byId('photoMsg').textContent='Recovered your unfinished vehicle entry.';}
  draftReady=true;
 }catch(e){showError(e)}finally{byId('next').disabled=false}
};
byId('form').addEventListener('input',scheduleDraft);
byId('form').addEventListener('change',scheduleDraft);
byId('thumbs').addEventListener('click',scheduleDraft);
byId('editor').addEventListener('click',()=>setTimeout(scheduleDraft,0));
for(const id of ['camera','gallery']){const original=byId(id).onchange;byId(id).onchange=async e=>{await original(e);await persistDraft()};}
byId('closeEditor').onclick=async()=>{await persistDraft();byId('editor').close();notify('Unfinished entry kept on this browser.');};
byId('editor').addEventListener('cancel',e=>{e.preventDefault();byId('closeEditor').click()});
const discard=document.createElement('button');discard.type='button';discard.textContent='Discard draft';discard.className='danger';
discard.onclick=async()=>{if(!confirm('Discard this unfinished entry? Saved vehicles stay unchanged.'))return;isSaving=true;clearTimeout(draftTimer);try{await draftWrites;await dropDraft(draftKey());byId('editor').close();}finally{isSaving=false}};
byId('editor').querySelector('.dialoghead').prepend(discard);
document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden'){clearTimeout(draftTimer);persistDraft()}});

const workspace=byId('workspaceName');workspace.value=localStorage.getItem('rowskan-workspace')||'My inventory';
function setWorkspace(){const name=workspace.value.trim().slice(0,80)||'My inventory';localStorage.setItem('rowskan-workspace',name);document.querySelector('.workspace').replaceChildren(document.createTextNode(name),document.createElement('br'),Object.assign(document.createElement('small'),{textContent:'Local workspace · Free'}));}
workspace.onchange=setWorkspace;setWorkspace();
byId('protectStorage').onclick=async()=>{try{const persistent=await navigator.storage?.persist?.();notify(persistent?'Persistent storage granted. Keep exporting backups.':'Browser did not grant persistent storage. Export regular backups.')}catch(e){showError(e)}};
async function storageStatus(){try{const info=await navigator.storage?.estimate?.();byId('storageInfo').textContent=info?`${Math.round((info.usage||0)/1048576)} MB used in this browser. Clearing site data or uninstalling can erase inventory.`:'Local browser storage. Keep regular backups.';}catch{}}
byId('mode').disabled=true;byId('mode').value='solo';localStorage.setItem('rowskan-mode','solo');
byId('mode').insertAdjacentHTML('afterend','<p class="hint">This browser edition is for a solo owner. Team device permissions belong to the native app and cannot be secured by a browser window’s width.</p>');

let installPrompt;
window.addEventListener('beforeinstallprompt',e=>{e.preventDefault();installPrompt=e;byId('installApp').hidden=false});
byId('installApp').onclick=async()=>{if(installPrompt){await installPrompt.prompt();installPrompt=null;byId('installApp').hidden=true}else notify('Use your browser menu: Install app or Add to Home Screen.')};
if('serviceWorker' in navigator){navigator.serviceWorker.register('./sw.js').catch(()=>notify('Offline installation unavailable. Online inventory still works.'));}
const badge=byId('connectionBadge');const connection=()=>{badge.textContent=navigator.onLine?'● Local inventory · Online':'● Local inventory · Offline'};
window.addEventListener('online',connection);window.addEventListener('offline',connection);connection();
storageStatus();

// Serialize the final conflict/VIN check and write in one IndexedDB transaction.
window.rowskanSave=(vehicle,previousId)=>new Promise((resolve,reject)=>{
 const transaction=db.transaction('vehicles','readwrite'),store=transaction.objectStore('vehicles');let failure;
 const request=store.getAll();
 request.onsuccess=()=>{
  const records=request.result,current=records.find(v=>v.id===previousId);
  if(previousId&&(!current||JSON.stringify(current)!==loadedVersion)){failure=Error('Record changed in another tab. Reopen it before saving.');transaction.abort();return;}
  if(vehicle.vin&&records.some(v=>v.id!==vehicle.id&&v.vin===vehicle.vin)){failure=Error('This VIN is already in inventory.');transaction.abort();return;}
  store.put({...vehicle,updated:Date.now()});
 };
 transaction.oncomplete=resolve;
 transaction.onerror=()=>reject(failure||transaction.error);
 transaction.onabort=()=>reject(failure||transaction.error||Error('Save canceled'));
});

const scanButton=document.createElement('button');scanButton.type='button';scanButton.textContent='Scan VIN barcode';
byId('decode').parentElement.insertAdjacentElement('afterend',scanButton);
scanButton.style.marginTop='8px';
scanButton.onclick=async()=>{
 if(!('BarcodeDetector' in window)||!navigator.mediaDevices?.getUserMedia){notify('Live barcode scanning is not supported in this browser. Use manual VIN entry or the native app.');return;}
 const dialog=document.createElement('dialog');dialog.innerHTML='<div class="dialoghead"><h2>Scan VIN barcode</h2><button aria-label="Close scanner">×</button></div><p>Aim at the barcode on the door jamb or vehicle paperwork.</p><video autoplay playsinline muted style="width:100%;max-height:55vh;background:#132e2b;border-radius:8px"></video><p class="hint" role="status">Starting camera…</p>';
 document.body.append(dialog);let stream,stopped=false,timer;
 const stop=()=>{stopped=true;clearTimeout(timer);stream?.getTracks().forEach(track=>track.stop());dialog.remove()};
 dialog.querySelector('button').onclick=()=>dialog.close();dialog.onclose=stop;dialog.showModal();
 try{
  const supported=await BarcodeDetector.getSupportedFormats();
  const formats=['code_39','code_128','pdf417','data_matrix','qr_code'].filter(f=>supported.includes(f));
  if(!formats.length)throw Error('No supported VIN barcode reader.');
  const detector=new BarcodeDetector({formats});
  stream=await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:'environment'}},audio:false});
  if(stopped){stream.getTracks().forEach(t=>t.stop());return;}
  const video=dialog.querySelector('video');video.srcObject=stream;await video.play();
  const message=dialog.querySelector('[role="status"]');message.textContent='Looking for a 17-character VIN…';
  async function detect(){
   if(stopped)return;
   try{
    const results=await detector.detect(video);
    for(const result of results){let value=String(result.rawValue||'').trim().toUpperCase();if(value.length===18&&value.startsWith('I'))value=value.slice(1);if(/^[A-HJ-NPR-Z0-9]{17}$/.test(value)){byId('vin').value=value;scheduleDraft();dialog.close();notify('VIN scanned. Tap Decode VIN to look up details.');return;}}
   }catch{message.textContent='Keep the barcode steady, or close and enter the VIN manually.';}
   if(!stopped)timer=setTimeout(detect,250);
  }
  detect();
 }catch(e){dialog.close();notify('Camera or barcode reader unavailable. Enter the VIN manually.');}
};
