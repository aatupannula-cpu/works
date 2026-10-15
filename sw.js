const V='tp-v1',CORE=['./','index.html','manifest.webmanifest','icon-192.png','icon-512.png'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(V).then(c=>c.addAll(CORE)).then(()=>self.skipWaiting()))});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==V).map(x=>caches.delete(x)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',e=>{
  const r=e.request,u=new URL(r.url);
  if(r.method!=='GET'||u.hostname.endsWith('supabase.co'))return;
  const put=res=>{const cp=res.clone();caches.open(V).then(c=>c.put(r,cp));return res};
  if(u.origin===location.origin)e.respondWith(fetch(r).then(put).catch(()=>caches.match(r).then(m=>m||caches.match('index.html'))));
  else if(u.hostname==='cdn.jsdelivr.net')e.respondWith(caches.match(r).then(m=>m||fetch(r).then(put)));
});
