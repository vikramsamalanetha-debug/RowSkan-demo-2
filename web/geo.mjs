export function validateGps(input){
 if(input==null)return null;
 if(typeof input!=='object'||!Number.isFinite(input.lat)||!Number.isFinite(input.lon)||input.lat< -90||input.lat>90||input.lon< -180||input.lon>180)throw Error('Enter valid latitude and longitude.');
 if(input.accuracyMeters!=null&&(!Number.isFinite(input.accuracyMeters)||input.accuracyMeters<0||input.accuracyMeters>1000000))throw Error('Invalid GPS accuracy.');
 if(!['gps','manual'].includes(input.source)||typeof input.capturedAt!=='string'||!Number.isFinite(Date.parse(input.capturedAt)))throw Error('Invalid GPS location metadata.');
 return {lat:input.lat,lon:input.lon,accuracyMeters:input.accuracyMeters??null,capturedAt:input.capturedAt,source:input.source};
}
const rad=n=>n*Math.PI/180;
export function distanceMeters(lat1,lon1,lat2,lon2){const a=Math.sin(rad(lat2-lat1)/2)**2+Math.cos(rad(lat1))*Math.cos(rad(lat2))*Math.sin(rad(lon2-lon1)/2)**2;return 6371000*2*Math.atan2(Math.sqrt(Math.min(1,a)),Math.sqrt(Math.max(0,1-a)));}
export function bearingDegrees(lat1,lon1,lat2,lon2){const a=rad(lat1),b=rad(lat2),delta=rad(lon2-lon1);return (Math.atan2(Math.sin(delta)*Math.cos(b),Math.cos(a)*Math.sin(b)-Math.sin(a)*Math.cos(b)*Math.cos(delta))*180/Math.PI+360)%360;}
export const cardinal=bearing=>['N','NE','E','SE','S','SW','W','NW'][Math.floor((bearing+22.5)/45)%8];
export function offsetGps(center,east,north){const cosine=Math.cos(rad(center.lat));if(Math.abs(cosine)<.001)throw Error('Enter coordinates directly near the poles.');return validateGps({lat:Math.max(-90,Math.min(90,center.lat+north/111195)),lon:((center.lon+east/(111195*cosine)+540)%360)-180,accuracyMeters:null,source:'manual',capturedAt:new Date().toISOString()});}
export function gpsFromPosition(position){return validateGps({lat:position.coords.latitude,lon:position.coords.longitude,accuracyMeters:position.coords.accuracy,capturedAt:new Date(position.timestamp).toISOString(),source:'gps'});}
export const gpsSummary=gps=>gps?`${gps.lat.toFixed(6)}, ${gps.lon.toFixed(6)} · ${gps.source==='manual'?'manually adjusted; accuracy unknown':'accuracy ±'+Math.round(gps.accuracyMeters)+' m'} · ${new Date(gps.capturedAt).toLocaleString()}`:'No GPS pin saved. Stand beside the vehicle and capture its location.';
export function captureGps(){return new Promise((resolve,reject)=>{if(!navigator.geolocation){reject(Error('Location is unavailable in this browser. Enter coordinates manually.'));return;}navigator.geolocation.getCurrentPosition(p=>{try{resolve(gpsFromPosition(p))}catch(e){reject(e)}},e=>reject(Error(e.code===1?'Location permission denied. Enable it in browser settings, or enter coordinates manually.':e.code===2?'Location unavailable. Move outside or enter coordinates manually.':'Location timed out. Retry outside or enter coordinates manually.')),{enableHighAccuracy:true,timeout:25000,maximumAge:0});});}
