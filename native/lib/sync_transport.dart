import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import 'sync_identity.dart';

class SyncPeer {
 final Member member;
 final SecretKey sendKey,receiveKey;
 final String session;
 int sent=0,received=0;
 Future<void> outgoing=Future.value();
 SyncPeer(this.member,this.sendKey,this.receiveKey,this.session);
}
/// Authenticated ephemeral sessions over the opaque relay. The workspace key
/// protects discovery; signed X25519 handshakes derive distinct direction keys.
class SyncTransport {
 final SyncIdentity identity;
 final Future<void> Function(SyncPeer,Map<String,dynamic>) onMessage;
 final Future<void> Function(SyncPeer) onPeer;
 final void Function(String) onStatus;
 final cipher=AesGcm.with256bits(),exchange=X25519();
 final peers=<String,SyncPeer>{};
 final seenHello=<String>{};
 WebSocket? socket;
 SimpleKeyPair? ephemeral;
 String? helloPacket,localNonce;
 Future<void> incoming=Future.value();
 int connection=0;
 bool connecting=false;
 SyncTransport({required this.identity,required this.onMessage,required this.onPeer,required this.onStatus});
 bool get connected=>socket?.readyState==WebSocket.open;
 Future<void> connect() async {
  if(connecting||connected)return;
  connecting=true;final generation=++connection;
  try{
   final p=identity.profile;if(p==null)throw StateError('Pair a workspace first.');
   final key=await exchange.newKeyPair();ephemeral=key;
   localNonce=base64Encode(await SecretKeyData.random(length:16).extractBytes());
   helloPacket=await identity.signPacket({'type':'hello','actor':identity.id,'ephemeral':base64Encode((await key.extractPublicKey()).bytes),'nonce':localNonce,'time':DateTime.now().millisecondsSinceEpoch,'id':const Uuid().v4()});
   final ws=await WebSocket.connect(validateEndpoint(p.endpoint).toString()).timeout(const Duration(seconds:15));
   if(generation!=connection){await ws.close();return;}
   ws.pingInterval=const Duration(seconds:20);socket=ws;
   ws.listen((event){
    incoming=incoming.catchError((Object e){onStatus('Sync message rejected: $e');}).then((_) async {if(generation==connection)await _receive(event,generation);});
    incoming.catchError((Object e){onStatus('Sync message rejected: $e');});
   },onDone:(){if(generation==connection){socket=null;peers.clear();onStatus('Disconnected. Your local changes are kept.');}},onError:(Object e){if(generation==connection)onStatus('Relay connection failed. Your data stays local.');});
   ws.add(jsonEncode({'type':'join','room':await identity.room,'peer':identity.id}));
   onStatus('Connecting to relay…');
  }finally{connecting=false;}
 }
 Future<void> disconnect() async {connection++;connecting=false;final ws=socket;socket=null;peers.clear();ephemeral=null;helloPacket=null;await ws?.close();onStatus('Offline. Local inventory remains available.');}
 Future<List<int>> _seal(Map<String,dynamic> header,String payload,SecretKey key) async {
  final box=await cipher.encrypt(utf8.encode(payload),secretKey:key,aad:utf8.encode(jsonEncode(header)));
  final bytes=utf8.encode(jsonEncode({'header':header,'nonce':base64Encode(box.nonce),'mac':base64Encode(box.mac.bytes),'ciphertext':base64Encode(box.cipherText)}));
  if(bytes.length>250000)throw StateError('Sync frame exceeds transport limit.');return bytes;
 }
 Future<String> _open(Map outer,SecretKey key) async {
  final nonce=decodeBytes(outer['nonce'],12),mac=decodeBytes(outer['mac'],16);
  final encrypted=outer['ciphertext'];if(encrypted is! String||encrypted.length>340000)throw StateError('Invalid encrypted frame.');
  final bytes=await cipher.decrypt(SecretBox(base64Decode(encrypted),nonce:nonce,mac:Mac(mac)),secretKey:key,aad:utf8.encode(jsonEncode(outer['header'])));
  return utf8.decode(bytes);
 }
 Future<void> _hello() async {
  if(!connected||helloPacket==null)return;final p=identity.profile!;
  helloPacket=await identity.signPacket({'type':'hello','actor':identity.id,'ephemeral':base64Encode((await ephemeral!.extractPublicKey()).bytes),'nonce':localNonce,'time':DateTime.now().millisecondsSinceEpoch,'id':const Uuid().v4()});
  socket!.add(await _seal({'type':'hello','workspace':p.workspace,'epoch':p.epoch},helloPacket!,SecretKey(decodeBytes(p.secret,32))));
 }
 Future<void> _receive(dynamic event,int generation) async {
  if(event is String){final data=jsonDecode(event);if(data is Map&&data['type']=='joined'){onStatus('Connected. Waiting for an approved device.');await _hello();}return;}
  if(event is! List<int>||event.length>250000)throw StateError('Invalid sync frame.');
  final outer=jsonDecode(utf8.decode(event)) as Map,header=Map<String,dynamic>.from(outer['header'] as Map),p=identity.profile!;
  if(header['workspace']!=p.workspace||header['epoch']!=p.epoch)throw StateError('Workspace mismatch.');
  if(header['type']=='hello'){
   final verified=await identity.verifyPacket(await _open(outer,SecretKey(decodeBytes(p.secret,32))));
   final data=verified.data,member=verified.author;
   if(member.id==identity.id)return;
   final time=data['time'];if(data['type']!='hello'||data['actor']!=member.id||time is! int||(DateTime.now().millisecondsSinceEpoch-time).abs()>300000)throw StateError('Handshake is stale. Check both device clocks.');
   final nonce=data['nonce'] as String;decodeBytes(nonce,16);final public=decodeBytes(data['ephemeral'],32);
   final helloKey='${member.id}|$nonce';
   if(seenHello.contains(helloKey)&&peers.containsKey(member.id))return;
   if(seenHello.length>=256)seenHello.clear();seenHello.add(helloKey);
   final localPublic=base64Encode((await ephemeral!.extractPublicKey()).bytes);
   final entries=[{'id':identity.id,'ephemeral':localPublic,'nonce':localNonce},{'id':member.id,'ephemeral':data['ephemeral'],'nonce':nonce}]..sort((a,b)=>(a['id'] as String).compareTo(b['id'] as String));
   final transcript=jsonEncode({'workspace':p.workspace,'epoch':p.epoch,'peers':entries});
   final shared=await exchange.sharedSecretKey(keyPair:ephemeral!,remotePublicKey:SimplePublicKey(public,type:KeyPairType.x25519));
   final hkdf=Hkdf(hmac:Hmac.sha256(),outputLength:32);
   final send=await hkdf.deriveKey(secretKey:shared,nonce:decodeBytes(p.secret,32),info:utf8.encode('$transcript|${identity.id}|${member.id}'));
   final receive=await hkdf.deriveKey(secretKey:shared,nonce:decodeBytes(p.secret,32),info:utf8.encode('$transcript|${member.id}|${identity.id}'));
   if(generation!=connection)return;
   final peer=SyncPeer(member,send,receive,await hashBytes(utf8.encode(transcript)));peers[member.id]=peer;
   // Reply once per new session so late joiners learn our ephemeral key too.
   await _hello();onStatus('Connected to ${peers.length} approved device(s).');await onPeer(peer);return;
  }
  if(header['type']!='data'||header['to']!=identity.id)return;
  final peer=peers[header['from']];if(peer==null||header['session']!=peer.session)return;
  final sequence=header['sequence'];if(sequence is! int||sequence<=peer.received)return;
  if(sequence!=peer.received+1)throw StateError('Sync frame gap. Reconnect to resume.');
  final data=jsonDecode(await _open(outer,peer.receiveKey));
  if(generation!=connection||data is! Map)return;
  peer.received=sequence;await onMessage(peer,Map<String,dynamic>.from(data));
 }
 Future<void> send(SyncPeer peer,Map<String,dynamic> body){
  final generation=connection;
  peer.outgoing=peer.outgoing.catchError((Object e){}).then((_) async {
   if(generation!=connection||!connected||peers[peer.member.id]!=peer)return;
   final p=identity.profile!;final header={'type':'data','workspace':p.workspace,'epoch':p.epoch,'from':identity.id,'to':peer.member.id,'session':peer.session,'sequence':++peer.sent};
   final bytes=await _seal(header,jsonEncode(body),peer.sendKey);if(generation==connection&&connected)socket!.add(bytes);
  });return peer.outgoing;
 }
}
