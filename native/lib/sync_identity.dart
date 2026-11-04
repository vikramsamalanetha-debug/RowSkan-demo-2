import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

String encodeCode(Map<String,dynamic> value)=>base64UrlEncode(utf8.encode(jsonEncode(value)));
Map<String,dynamic> decodeCode(String value){
 if(value.length>20000)throw StateError('Pairing code is too long.');
 final decoded=jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(value.trim()))));
 if(decoded is! Map)throw StateError('Invalid pairing code.');
 return Map<String,dynamic>.from(decoded);
}
Future<String> hashBytes(List<int> bytes) async =>(await Sha256().hash(bytes)).bytes.map((n)=>n.toRadixString(16).padLeft(2,'0')).join();
List<int> decodeBytes(dynamic value,int length){
 if(value is! String)throw StateError('Invalid key.');
 final result=base64Decode(value);if(result.length!=length)throw StateError('Invalid key length.');return result;
}
abstract class KeyVault {
 Future<String?> read(String key);
 Future<void> write(String key,String value);
}
class PlatformKeyVault implements KeyVault {
 final storage=const FlutterSecureStorage();
 @override Future<String?> read(String key)=>storage.read(key:'rowskan-$key');
 @override Future<void> write(String key,String value)=>storage.write(key:'rowskan-$key',value:value);
}
class MemoryKeyVault implements KeyVault {
 final values=<String,String>{};
 @override Future<String?> read(String key)async=>values[key];
 @override Future<void> write(String key,String value)async{values[key]=value;}
}
class SyncProfile {
 final String workspace,ownerKey,secret,certificate,endpoint;
 final int epoch;
 SyncProfile({required this.workspace,required this.ownerKey,required this.secret,required this.certificate,required this.endpoint,required this.epoch});
 Map<String,dynamic> toJson()=>{'workspace':workspace,'ownerKey':ownerKey,'secret':secret,'certificate':certificate,'endpoint':endpoint,'epoch':epoch};
 static SyncProfile parse(Map<String,dynamic> data){
  final profile=SyncProfile(workspace:data['workspace'] as String,ownerKey:data['ownerKey'] as String,secret:data['secret'] as String,certificate:data['certificate'] as String,endpoint:data['endpoint'] as String,epoch:data['epoch'] as int);
  if(!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(profile.workspace)||profile.epoch<1)throw StateError('Invalid workspace.');
  decodeBytes(profile.ownerKey,32);decodeBytes(profile.secret,32);validateEndpoint(profile.endpoint);return profile;
 }
}
Uri validateEndpoint(String endpoint){
 final uri=Uri.parse(endpoint.trim());
 final loopback=['localhost','127.0.0.1','::1'].contains(uri.host);
 if(uri.host.isEmpty||uri.userInfo.isNotEmpty||uri.hasQuery||uri.hasFragment||!(uri.scheme=='wss'||(uri.scheme=='ws'&&loopback)))throw StateError('Use a wss:// relay address. Plain ws:// is allowed only for local testing.');
 return uri;
}
class Member {
 final String id,publicKey,role,label;
 final bool owner;
 Member(this.id,this.publicKey,this.role,this.label,this.owner);
 bool get canManage=>role=='owner'||role=='manager';
}
class SyncIdentity {
 final KeyVault vault;
 final signing=Ed25519();
 late SimpleKeyPair keyPair;
 late String publicKey,id;
 SyncProfile? profile;
 SyncIdentity(this.vault);
 Future<void> open() async {
  var seed=await vault.read('identity-seed');
  if(seed==null){seed=base64Encode(await SecretKeyData.random(length:32).extractBytes());await vault.write('identity-seed',seed);}
  keyPair=await signing.newKeyPairFromSeed(decodeBytes(seed,32));publicKey=base64Encode((await keyPair.extractPublicKey()).bytes);id=(await hashBytes(base64Decode(publicKey))).substring(0,40);
  final saved=await vault.read('workspace');if(saved!=null){profile=SyncProfile.parse(Map<String,dynamic>.from(jsonDecode(saved) as Map));if((await member(profile!.certificate)).publicKey!=publicKey)throw StateError('Device identity does not match its workspace approval.');}
 }
 bool get isOwner=>profile?.ownerKey==publicKey;
 Future<String> _sign(Map<String,dynamic> data) async {
  final payload=jsonEncode(data);final signature=await signing.sign(utf8.encode(payload),keyPair:keyPair);
  return jsonEncode({'payload':payload,'signature':base64Encode(signature.bytes)});
 }
 Future<Map<String,dynamic>> _verify(String text,String public) async {
  if(text.length>64000)throw StateError('Signed message too large.');
  final wrapper=jsonDecode(text) as Map;final payload=wrapper['payload'];if(payload is! String)throw StateError('Missing signature payload.');
  final signature=Signature(decodeBytes(wrapper['signature'],64),publicKey:SimplePublicKey(decodeBytes(public,32),type:KeyPairType.ed25519));
  if(!await signing.verify(utf8.encode(payload),signature:signature))throw StateError('Signature verification failed.');
  final data=jsonDecode(payload);if(data is! Map)throw StateError('Invalid signed payload.');return Map<String,dynamic>.from(data);
 }
 Future<String> requestCode(String label,{required bool desktop}) async =>encodeCode({'format':'rowskan-pair-request','v':1,'publicKey':publicKey,'proof':await _sign({'publicKey':publicKey,'label':label.trim().substring(0,label.trim().length.clamp(0,80).toInt()),'desktop':desktop})});
 Future<void> createWorkspace(String endpoint,{required String label}) async {
  if(label.trim().isEmpty||label.trim().length>80)throw StateError('Use a device name of 1 to 80 characters.');
  validateEndpoint(endpoint);final secret=base64Encode(await SecretKeyData.random(length:32).extractBytes());final workspace=const Uuid().v4();
  final certificate=await _sign({'workspace':workspace,'epoch':1,'publicKey':publicKey,'role':'owner','label':label});
  profile=SyncProfile(workspace:workspace,ownerKey:publicKey,secret:secret,certificate:certificate,endpoint:endpoint.trim(),epoch:1);await _persist();
 }
 Future<String> grant(String request,{required String role}) async {
  if(!isOwner||!['capture','manager'].contains(role))throw StateError('Only the workspace owner can approve a device.');
  final data=decodeCode(request);if(data['format']!='rowskan-pair-request'||data['v']!=1)throw StateError('Invalid pairing request.');
  final public=data['publicKey'] as String;decodeBytes(public,32);final proof=await _verify(data['proof'] as String,public);
  if(proof['publicKey']!=public)throw StateError('Pairing key mismatch.');
  if(role=='manager'&&proof['desktop']!=true)throw StateError('Issue phone devices a capture role.');
  final p=profile!;final certificate=await _sign({'workspace':p.workspace,'epoch':p.epoch,'publicKey':public,'role':role,'label':proof['label']});
  return encodeCode({'format':'rowskan-pair-grant','v':1,...p.toJson(),'certificate':certificate});
 }
 Future<void> acceptGrant(String code) async {
  final data=decodeCode(code);if(data['format']!='rowskan-pair-grant'||data['v']!=1)throw StateError('Invalid pairing approval.');
  final candidate=SyncProfile.parse(data),old=profile;profile=candidate;
  try{final device=await member(candidate.certificate);if(device.publicKey!=publicKey)throw StateError('This approval belongs to another device.');await _persist();}catch(_){profile=old;rethrow;}
 }
 Future<Member> member(String certificate) async {
  final p=profile;if(p==null)throw StateError('Workspace is not configured.');
  final data=await _verify(certificate,p.ownerKey);
  if(data['workspace']!=p.workspace||data['epoch']!=p.epoch||!['owner','capture','manager'].contains(data['role']))throw StateError('Invalid or expired device approval.');
  final public=data['publicKey'] as String;decodeBytes(public,32);
  if(data['role']=='owner'&&public!=p.ownerKey)throw StateError('Owner certificate mismatch.');
  return Member((await hashBytes(base64Decode(public))).substring(0,40),public,data['role'] as String,(data['label']??'Device').toString(),public==p.ownerKey);
 }
 Future<String> signPacket(Map<String,dynamic> payload) async {
  final p=profile;if(p==null)throw StateError('No workspace.');
  return jsonEncode({'certificate':p.certificate,'message':await _sign({...payload,'workspace':p.workspace,'epoch':p.epoch})});
 }
 Future<({Member author,Map<String,dynamic> data})> verifyPacket(String packet) async {
  if(packet.length>64000)throw StateError('Sync packet is too large.');
  final outer=jsonDecode(packet) as Map;final author=await member(outer['certificate'] as String);final data=await _verify(outer['message'] as String,author.publicKey);
  final p=profile!;if(data['workspace']!=p.workspace||data['epoch']!=p.epoch)throw StateError('Workspace mismatch.');return (author:author,data:data);
 }
 Future<void> resetPairing() async {
  if(!isOwner)throw StateError('Only the owner can reset pairing.');
  final p=profile!;final epoch=p.epoch+1;
  final certificate=await _sign({'workspace':p.workspace,'epoch':epoch,'publicKey':publicKey,'role':'owner','label':'Workspace owner'});
  profile=SyncProfile(workspace:p.workspace,ownerKey:p.ownerKey,secret:base64Encode(await SecretKeyData.random(length:32).extractBytes()),certificate:certificate,endpoint:p.endpoint,epoch:epoch);await _persist();
 }
 Future<void> updateEndpoint(String endpoint) async {
  validateEndpoint(endpoint);final p=profile!;profile=SyncProfile(workspace:p.workspace,ownerKey:p.ownerKey,secret:p.secret,certificate:p.certificate,endpoint:endpoint.trim(),epoch:p.epoch);await _persist();
 }
 Future<String> get room async=>hashBytes([...base64Decode(profile!.secret),...utf8.encode(profile!.workspace),...utf8.encode('|${profile!.epoch}')]);
 Future<void> _persist()=>vault.write('workspace',jsonEncode(profile!.toJson()));
}
