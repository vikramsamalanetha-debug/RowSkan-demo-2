import {test} from 'node:test';
import assert from 'node:assert/strict';
import {validateGps,distanceMeters,bearingDegrees,cardinal,offsetGps,gpsFromPosition} from '../web/geo.mjs';
import {validateImport,sealBackup,openBackup} from '../web/backup-crypto.mjs';
const gps={lat:35.65,lon:-88.39,accuracyMeters:7,source:'gps',capturedAt:'2026-11-03T12:00:00Z'};
test('distance and bearing support cardinal directions and dateline',()=>{
 assert.equal(distanceMeters(0,0,0,0),0);assert.ok(Math.abs(distanceMeters(0,0,0,1)-111195)<1);
 assert.equal(bearingDegrees(0,0,1,0),0);assert.equal(bearingDegrees(0,0,0,1),90);
 assert.ok(Math.abs(distanceMeters(0,179.999,0,-179.999)-222.39)<1);assert.equal(cardinal(359),'N');assert.equal(cardinal(225),'SW');
});
test('manual correction keeps direction and labels accuracy unknown',()=>{
 const p=offsetGps(gps,30,40);assert.ok(Math.abs(distanceMeters(gps.lat,gps.lon,p.lat,p.lon)-50)<.2);assert.equal(p.accuracyMeters,null);assert.equal(p.source,'manual');
});
test('invalid location metadata rejected and older records remain valid',()=>{
 assert.equal(validateGps(undefined),null);assert.deepEqual(validateGps(gps),gps);
 for(const change of [{lat:NaN},{lon:190},{lat:-91},{accuracyMeters:-1},{accuracyMeters:null},{capturedAt:'bad'},{source:'guess'}])assert.throws(()=>validateGps({...gps,...change}));
});
test('GPS capture timestamp and accuracy preserved',()=>{
 assert.deepEqual(gpsFromPosition({timestamp:Date.parse(gps.capturedAt),coords:{latitude:gps.lat,longitude:gps.lon,accuracy:gps.accuracyMeters}}),{...gps,capturedAt:new Date(gps.capturedAt).toISOString()});
});
test('encrypted backup/import keeps GPS with vehicle and rejects corrupt coordinates',async()=>{
 const car={id:'geo-car',make:'Ford',model:'F150',status:'Available',photos:[],gps};const data={format:'rowskan-backup',version:1,vehicles:[car]};
 const encrypted=await sealBackup(data,'long gps test password');const restored=await openBackup(encrypted,'long gps test password');assert.deepEqual(validateImport(restored)[0].gps,gps);
 assert.throws(()=>validateImport({...data,vehicles:[{...car,gps:{...gps,lat:999}}]}));
});
