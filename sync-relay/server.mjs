import http from 'node:http';
import {pathToFileURL} from 'node:url';
import {WebSocketServer,WebSocket} from 'ws';

// Transport groundwork only; clients MUST encrypt/authenticate every frame.
// No database, disk writes, inventory endpoint, replay history or retry queue.
export function createRelay({maxFrameBytes=262144,maxConnections=512,maxRoomPeers=8,handshakeMs=5000}={}){
 const rooms=new Map(),attempts=new Map();
 const server=http.createServer((req,res)=>{
  res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');
  if(req.method==='GET'&&req.url==='/healthz'){res.writeHead(200,{'Content-Type':'application/json'});res.end('{"status":"ok","storesInventory":false}');}
  else{res.writeHead(404);res.end();}
 });
 const sockets=new WebSocketServer({noServer:true,maxPayload:maxFrameBytes,perMessageDeflate:false});
 server.on('upgrade',(req,socket,head)=>{
  if(req.url!=='/relay'||sockets.clients.size>=maxConnections){socket.end('HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\n\r\n');return;}
  const now=Date.now(),ip=req.socket.remoteAddress||'unknown';
  for(const [key,value] of attempts)if(value.expires<now)attempts.delete(key);
  if(attempts.size>=10000&&!attempts.has(ip)){socket.end('HTTP/1.1 503 Service Unavailable\r\n\r\n');return;}
  const bucket=attempts.get(ip)||{count:0,expires:now+60000};bucket.count++;attempts.set(ip,bucket);
  if(bucket.count>30){socket.end('HTTP/1.1 429 Too Many Requests\r\n\r\n');return;}
  sockets.handleUpgrade(req,socket,head,ws=>sockets.emit('connection',ws,req));
 });
 sockets.on('connection',ws=>{
  let room=null,peer=null,alive=true,sentBytes=0,windowStart=Date.now();
  const timer=setTimeout(()=>ws.close(1008,'Join timeout'),handshakeMs);timer.unref();
  ws.on('error',()=>{});ws.on('pong',()=>{alive=true});
  ws.on('message',(data,isBinary)=>{
   if(!room){
    if(isBinary||data.length>1024){ws.close(1008,'Invalid join');return;}
    let join;try{join=JSON.parse(data.toString())}catch{ws.close(1008,'Invalid join');return;}
    if(join.type!=='join'||typeof join.room!=='string'||!/^[a-f0-9]{64}$/.test(join.room)||typeof join.peer!=='string'||!/^[a-zA-Z0-9_-]{16,80}$/.test(join.peer)){ws.close(1008,'Invalid join');return;}
    const members=rooms.get(join.room)||new Map();
    if(members.size>=maxRoomPeers||members.has(join.peer)){ws.close(1008,'Room limit');return;}
    room=join.room;peer=join.peer;members.set(peer,ws);rooms.set(room,members);clearTimeout(timer);
    ws.send(JSON.stringify({type:'joined',peers:members.size}));return;
   }
   if(!isBinary||data.length<32){ws.close(1008,'Encrypted binary frame required');return;}
   const now=Date.now();if(now-windowStart>=1000){windowStart=now;sentBytes=0;}sentBytes+=data.length;
   if(sentBytes>4*1024*1024){ws.close(1008,'Rate limit');return;}
   for(const other of rooms.get(room)?.values()||[]){
    if(other===ws||other.readyState!==WebSocket.OPEN)continue;
    if(other.bufferedAmount>2*maxFrameBytes){other.close(1013,'Backpressure');continue;}
    other.send(data,{binary:true});
   }
  });
  ws.on('close',()=>{clearTimeout(timer);if(room){const members=rooms.get(room);members?.delete(peer);if(!members?.size)rooms.delete(room);}});
  ws.rowskanHeartbeat=()=>{if(!alive){ws.terminate();return;}alive=false;ws.ping();};
 });
 const heartbeat=setInterval(()=>{for(const ws of sockets.clients)ws.rowskanHeartbeat?.();},30000);heartbeat.unref();
 return {
  server,
  listen:(port=0,host='127.0.0.1')=>new Promise(resolve=>server.listen(port,host,()=>resolve(server.address()))),
  close:async()=>{clearInterval(heartbeat);for(const ws of sockets.clients)ws.terminate();await new Promise(resolve=>sockets.close(resolve));await new Promise(resolve=>server.close(resolve));rooms.clear();attempts.clear();},
 };
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const relay=createRelay();const port=Number(process.env.PORT||8787),host=process.env.BIND_HOST||'127.0.0.1';
 await relay.listen(port,host);console.log(`RowSkan relay listening on ${host}:${port}. No message persistence.`);
 for(const signal of ['SIGTERM','SIGINT'])process.on(signal,async()=>{await relay.close();process.exit(0)});
}
