const VERSION='rowskan-shell-v2';
const SHELL=['./','./index.html','./manifest.webmanifest','./icon.svg','./web/backup-crypto.mjs','./web/release.mjs','./privacy.html'];
self.addEventListener('install',event=>{event.waitUntil(caches.open(VERSION).then(cache=>cache.addAll(SHELL)));});
self.addEventListener('activate',event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('rowskan-shell-')&&k!==VERSION).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));});
self.addEventListener('fetch',event=>{
 const url=new URL(event.request.url);
 if(event.request.method!=='GET'||url.origin!==self.location.origin)return;
 if(event.request.mode==='navigate'){
  event.respondWith(fetch(event.request).catch(()=>caches.match(new URL('./index.html',self.registration.scope).href)));return;
 }
 if(!SHELL.some(path=>new URL(path,self.registration.scope).href===url.href))return;
 event.respondWith(caches.match(event.request).then(hit=>hit||fetch(event.request)));
});
