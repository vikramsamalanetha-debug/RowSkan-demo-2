import {test} from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import {WebSocket} from 'ws';
import {createRelay} from '../server.mjs';
const room='a'.repeat(64),otherRoom='b'.repeat(64);
async function connect(url,group,peer){const ws=new WebSocket(url);await once(ws,'open');const reply=once(ws,'message');ws.send(JSON.stringify({type:'join',room:group,peer}));await reply;return ws;}
test('frames reach only same-room peers and are not replayed to new peers',async()=>{
 const relay=createRelay();const address=await relay.listen();const url=`ws://127.0.0.1:${address.port}/relay`;
 try{
  const a=await connect(url,room,'device_aaaaaaaaa1'),b=await connect(url,room,'device_bbbbbbbbb2'),c=await connect(url,otherRoom,'device_ccccccccc3');
  let leaked=false;c.on('message',()=>{leaked=true});
  const received=once(b,'message');const frame=Buffer.alloc(64,72);a.send(frame);assert.deepEqual((await received)[0],frame);
  const d=await connect(url,room,'device_ddddddddd4');let replayed=false;d.on('message',()=>{replayed=true});
  await new Promise(r=>setTimeout(r,60));assert.equal(leaked,false);assert.equal(replayed,false);
 }finally{await relay.close();}
});
test('plaintext rejected after joining',async()=>{
 const relay=createRelay();const address=await relay.listen();
 try{const ws=await connect(`ws://127.0.0.1:${address.port}/relay`,room,'device_aaaaaaaaa1');const closed=once(ws,'close');ws.send('vehicle data');assert.equal((await closed)[0],1008);}
 finally{await relay.close();}
});
test('invalid rooms and oversized frames rejected',async()=>{
 const relay=createRelay({maxFrameBytes:128});const address=await relay.listen();const url=`ws://127.0.0.1:${address.port}/relay`;
 try{
  const bad=new WebSocket(url);await once(bad,'open');let closed=once(bad,'close');bad.send(JSON.stringify({type:'join',room:'guess',peer:'device_aaaaaaaaa1'}));assert.equal((await closed)[0],1008);
  const ws=await connect(url,room,'device_aaaaaaaaa1');ws.on('error',()=>{});closed=once(ws,'close');ws.send(Buffer.alloc(256));assert.equal((await closed)[0],1009);
 }finally{await relay.close();}
});
test('peers must finish joining and room capacity is enforced',async()=>{
 const relay=createRelay({maxRoomPeers:1,handshakeMs:80});const address=await relay.listen();const url=`ws://127.0.0.1:${address.port}/relay`;
 try{
  const idle=new WebSocket(url);await once(idle,'open');assert.equal((await once(idle,'close'))[0],1008);
  await connect(url,room,'device_aaaaaaaaa1');const duplicate=new WebSocket(url);await once(duplicate,'open');const closed=once(duplicate,'close');duplicate.send(JSON.stringify({type:'join',room,peer:'device_bbbbbbbbb2'}));assert.equal((await closed)[0],1008);
 }finally{await relay.close();}
});
test('HTTP endpoint does not expose room or inventory state',async()=>{
 const relay=createRelay();const address=await relay.listen();
 try{
  const health=await fetch(`http://127.0.0.1:${address.port}/healthz`);assert.deepEqual(await health.json(),{status:'ok',storesInventory:false});
  const inventory=await fetch(`http://127.0.0.1:${address.port}/inventory`);assert.equal(inventory.status,404);
 }finally{await relay.close();}
});
