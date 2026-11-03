import {test} from 'node:test';
import assert from 'node:assert/strict';
import {sealBackup,openBackup,validateImport} from '../web/backup-crypto.mjs';
const car={id:'a',vin:'1HGCM82633A004352',year:'2003',make:'Honda',model:'Accord',status:'Available',photos:[]};
const payload=vehicles=>({format:'rowskan-backup',version:1,vehicles});
test('encrypted backups require correct password and reject tampering',async()=>{
 const sealed=await sealBackup(payload([car]),'my strong password');
 assert.deepEqual(await openBackup(sealed,'my strong password'),payload([car]));
 await assert.rejects(openBackup(sealed,'another password'),/Wrong password/);
 const changed={...sealed,ciphertext:'A'+sealed.ciphertext.slice(1)};
 if(changed.ciphertext===sealed.ciphertext)changed.ciphertext='B'+sealed.ciphertext.slice(1);
 await assert.rejects(openBackup(changed,'my strong password'),/Wrong password/);
});
test('import validation rejects bad records without mutating existing records',()=>{
 const existing=[];
 assert.throws(()=>validateImport(payload([car,{...car,id:'b',vin:'bad'}]),existing),/VIN/);
 assert.equal(existing.length,0);
});
test('duplicates are skipped and safe fields are normalized',()=>{
 assert.equal(validateImport(payload([car]),[car]).length,0);
 assert.equal(validateImport(payload([car,{...car,id:'b'}])).length,1);
 assert.equal(validateImport(payload([{...car,vin:car.vin.toLowerCase()}]))[0].vin,car.vin);
});
test('untrusted photo URLs and traversal record IDs rejected',()=>{
 assert.throws(()=>validateImport(payload([{...car,photos:['javascript:alert(1)']}])));
 assert.throws(()=>validateImport(payload([{...car,id:'../escape'}])));
});
