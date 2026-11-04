import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'store.dart';
import 'sync_identity.dart';
import 'sync_transport.dart';

Future<String> fileHash(File file) async =>(await Sha256().hashStream(file.openRead())).bytes.map((n)=>n.toRadixString(16).padLeft(2,'0')).join();
class PendingSync {
 final SyncPeer peer;final Member author;final String packet;final Map<String,dynamic> operation,files;
 final complete=<String>{};final retries=<String,int>{};
 PendingSync(this.peer,this.author,this.packet,this.operation,this.files);
}
class SyncEngine extends ChangeNotifier {
 final Store store;final SyncIdentity identity;
 late final SyncTransport transport;
 String status='Set up or pair a workspace to sync devices.';
 bool initialized=false,enabled=false,disposed=false;
 final active=<String,String>{},pumping=<String>{};
 final pending=<String,PendingSync>{};
 StreamSubscription<void>? changes;Timer? retry;
 final Future<void> Function()? inventoryChanged;
 SyncEngine(this.store,{KeyVault? vault,this.inventoryChanged}):identity=SyncIdentity(vault??PlatformKeyVault()){
  transport=SyncTransport(identity:identity,onMessage:_message,onPeer:_peer,onStatus:(text){status=text;if(!transport.connected){active.clear();pending.clear();}_notify();});
 }
 bool get configured=>identity.profile!=null;
 bool get isOwner=>identity.isOwner;
 int get peerCount=>transport.peers.length;
 String get deviceId=>identity.id;
 void _notify(){if(!disposed)notifyListeners();}
 Future<void> open({bool autoConnect=true}) async {
  await identity.open();initialized=true;
  if(configured){await _configure();if(autoConnect)unawaited(connect().catchError((Object e){status='Relay unavailable: $e';_notify();}));}
  changes=store.syncChanges.listen((_){for(final peer in transport.peers.values){unawaited(_pump(peer));}});
  retry=Timer.periodic(const Duration(seconds:20),(_){if(!enabled||disposed)return;if(!transport.connected){unawaited(connect().catchError((Object e){status='Relay unavailable. Local work is safe.';_notify();}));}else{for(final peer in transport.peers.values){final id=active[peer.member.id];unawaited(id==null?_pump(peer):_offer(peer,id));}}});
  _notify();
 }
 Future<void> _configure() async {
  final profile=identity.profile!;final member=await identity.member(profile.certificate);
  await store.setSyncRole(member.role);
  if(member.role=='capture'){await store.db.insert('settings',{'key':'mode','value':'team'},conflictAlgorithm:ConflictAlgorithm.replace);}
  final tag='${profile.workspace}:${profile.epoch}';
  if(await store.setting('sync-workspace-tag','')!=tag){await store.resetSyncJournal();await store.db.insert('settings',{'key':'sync-workspace-tag','value':tag},conflictAlgorithm:ConflictAlgorithm.replace);}
  await Directory(p.join(store.root.path,'sync-stage')).create(recursive:true);
 }
 Future<void> createWorkspace(String endpoint,String label) async {
  if(configured)throw StateError('This device already owns or belongs to a workspace.');
  if(!store.desktop&&await store.setting('mode','solo')=='team')throw StateError('Create a team workspace on the owner desktop.');
  await disconnect();await identity.createWorkspace(endpoint,label:label);await _configure();status='Workspace created. Approve another device to begin.';_notify();
 }
 Future<void> acceptGrant(String code) async {await disconnect();await identity.acceptGrant(code);await _configure();status='Pairing approved. Connect when both devices are online.';_notify();await inventoryChanged?.call();}
 Future<void> resetPairing() async {await disconnect();await identity.resetPairing();await _configure();status='All previous device approvals were revoked. Issue new approvals to reconnect.';_notify();}
 Future<void> connect() async {if(!configured)throw StateError('Configure pairing first.');enabled=true;await transport.connect();}
 Future<void> disconnect() async {enabled=false;active.clear();pending.clear();await transport.disconnect();}
 Future<void> pauseForBackground() async {final wasEnabled=enabled;await disconnect();enabled=wasEnabled;}
 Future<void> _peer(SyncPeer peer) async {active.remove(peer.member.id);await _pump(peer);}
 Future<void> _pump(SyncPeer peer) async {
  if(!transport.connected||active.containsKey(peer.member.id)||!pumping.add(peer.member.id))return;
  try{final rows=await store.syncPending(peer.member.id);if(rows.isEmpty)return;final id=rows.first['id'] as String;active[peer.member.id]=id;await _offer(peer,id);}
  catch(e){active.remove(peer.member.id);status='A vehicle could not sync: $e';_notify();}
  finally{pumping.remove(peer.member.id);}
 }
 Future<String> _packet(Map<String,dynamic> row) async {
  if(row['packet'] is String)return row['packet'] as String;
  final op=Map<String,dynamic>.from(jsonDecode(row['operation'] as String) as Map),record=store.validate(Map<String,dynamic>.from(op['record'] as Map));
  final files=<String,dynamic>{};
  for(final name in record['photos'] as List<String>){final file=store.photo(name);if(!await file.exists())throw StateError('A saved photograph is missing.');final size=await file.length();if(size>25*1024*1024)throw StateError('Photo exceeds transfer limit.');files[name]={'hash':await fileHash(file),'size':size};}
  op['files']=files;final packet=await identity.signPacket({'type':'operation','operation':op});
  await store.cacheSyncPacket(row['id'] as String,jsonEncode(op),packet);return packet;
 }
 Future<void> _offer(SyncPeer peer,String id) async {
  final row=await store.syncOperation(id);if(row==null){active.remove(peer.member.id);return;}
  await transport.send(peer,{'type':'offer','packet':await _packet(row)});
 }
 File _stage(String hash){if(!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash))throw StateError('Invalid photo hash.');return File(p.join(store.root.path,'sync-stage','$hash.part'));}
 Future<void> _message(SyncPeer peer,Map<String,dynamic> body) async {
  switch(body['type']){
   case 'offer':await _receiveOffer(peer,body);break;
   case 'need':await _sendChunk(peer,body);break;
   case 'chunk':await _receiveChunk(peer,body);break;
   case 'ack':
    final id=body['id'];if(id is! String||active[peer.member.id]!=id||!['applied','duplicate','conflict','rejected'].contains(body['status']))return;
    await store.syncReceipt(id,peer.member.id,body['status'] as String);active.remove(peer.member.id);
    if(body['status']=='conflict'||body['status']=='rejected')status='Some changes need owner review. Check synchronization conflicts.';
    await _pump(peer);_notify();break;
  }
 }
 Future<void> _receiveOffer(SyncPeer peer,Map<String,dynamic> body) async {
  String? id;
  try{
   final packet=body['packet'];if(packet is! String)throw StateError('Missing operation signature.');
   final signed=await identity.verifyPacket(packet);if(signed.data['type']!='operation')throw StateError('Invalid operation packet.');
   final op=Map<String,dynamic>.from(signed.data['operation'] as Map);id=op['id'] as String;
   if(!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id))throw StateError('Invalid operation ID.');
   if(await store.syncOperation(id)!=null){await transport.send(peer,{'type':'ack','id':id,'status':'duplicate'});return;}
   if((op['kind']=='delete'||op['kind']=='restore'||op['deleted']==true)&&!signed.author.canManage)throw StateError('A capture device attempted to delete shared data.');
   if(op['kind']=='resolve'&&!signed.author.owner)throw StateError('Conflict resolution needs the owner.');
   final record=store.validate(Map<String,dynamic>.from(op['record'] as Map)),files=Map<String,dynamic>.from(op['files'] as Map);
   if(files.length!=(record['photos'] as List).length)throw StateError('Photo manifest mismatch.');
   for(final name in record['photos'] as List<String>){final data=files[name];if(data is! Map||data['hash'] is! String||!RegExp(r'^[a-f0-9]{64}$').hasMatch(data['hash'] as String)||data['size'] is! int||data['size']<0||data['size']>25*1024*1024)throw StateError('Invalid photo manifest.');}
   final key='${peer.member.id}:$id';
   if(pending.keys.any((k)=>k.startsWith('${peer.member.id}:')&&k!=key))throw StateError('A photo transfer is already in progress.');
   final transfer=pending.putIfAbsent(key,()=>PendingSync(peer,signed.author,packet,op,files));await _nextPhoto(transfer);
  }catch(e){if(id!=null){pending.remove('${peer.member.id}:$id');await transport.send(peer,{'type':'ack','id':id,'status':'rejected'});}status='Sync change rejected: $e';_notify();}
 }
 Future<void> _nextPhoto(PendingSync transfer) async {
  final id=transfer.operation['id'] as String;
  for(final entry in transfer.files.entries){
   if(transfer.complete.contains(entry.key))continue;
   final expected=entry.value as Map,hash=expected['hash'] as String,size=expected['size'] as int,destination=store.photo(entry.key),partial=_stage(hash);
   if(await destination.exists()){
    if(await destination.length()!=size||await fileHash(destination)!=hash)throw StateError('A photo filename collision was detected. Existing photo kept.');
    transfer.complete.add(entry.key);continue;
   }
   var length=await partial.exists()?await partial.length():0;
   if(length>size){await partial.delete();length=0;}
   if(length==size){
    if(!await partial.exists())await partial.writeAsBytes([],flush:true);
    if(await fileHash(partial)!=hash){await partial.delete();final attempts=(transfer.retries[entry.key]??0)+1;transfer.retries[entry.key]=attempts;if(attempts>2)throw StateError('Photo verification failed. Transfer was not committed.');length=0;}
    else{await partial.rename(destination.path);transfer.complete.add(entry.key);continue;}
   }
   await transport.send(transfer.peer,{'type':'need','id':id,'name':entry.key,'hash':hash,'offset':length});return;
  }
  final result=await store.applySyncOperation(transfer.operation,transfer.packet,role:transfer.author.role,owner:transfer.author.owner);
  await store.syncReceipt(id,transfer.peer.member.id,'received');pending.remove('${transfer.peer.member.id}:$id');
  await transport.send(transfer.peer,{'type':'ack','id':id,'status':result});
  status=result=='conflict'?'A vehicle needs owner review. Both versions were kept.':'Inventory synchronized.';
  await inventoryChanged?.call();_notify();
 }
 Future<void> _sendChunk(SyncPeer peer,Map<String,dynamic> body) async {
  final id=body['id'],name=body['name'],offset=body['offset'];
  if(id is! String||name is! String||offset is! int||offset<0||active[peer.member.id]!=id)return;
  final row=await store.syncOperation(id);if(row==null)return;
  final op=Map<String,dynamic>.from(jsonDecode(row['operation'] as String) as Map),files=op['files'] as Map?;
  final expected=files?[name];if(expected is! Map||body['hash']!=expected['hash']||offset>=(expected['size'] as int))return;
  final file=store.photo(name);if(!await file.exists()||await file.length()!=expected['size'])throw StateError('Source photo changed during transfer.');
  final input=await file.open();
  try{await input.setPosition(offset);final bytes=await input.read(32768);await transport.send(peer,{'type':'chunk','id':id,'name':name,'hash':expected['hash'],'offset':offset,'bytes':base64Encode(bytes)});}
  finally{await input.close();}
 }
 Future<void> _receiveChunk(SyncPeer peer,Map<String,dynamic> body) async {
  final id=body['id'],name=body['name'],offset=body['offset'],encoded=body['bytes'];
  if(id is! String||name is! String||offset is! int||encoded is! String||encoded.length>44000)return;
  final transfer=pending['${peer.member.id}:$id'];if(transfer==null)return;
  final expected=transfer.files[name];if(expected is! Map||body['hash']!=expected['hash'])return;
  final bytes=base64Decode(encoded);if(bytes.isEmpty||bytes.length>32768||offset<0||offset+bytes.length>(expected['size'] as int))throw StateError('Invalid photo chunk.');
  final partial=_stage(expected['hash'] as String),length=await _stage(expected['hash'] as String).exists()?await partial.length():0;
  if(offset!=length){await _nextPhoto(transfer);return;}
  await partial.writeAsBytes(bytes,mode:FileMode.append,flush:true);await _nextPhoto(transfer);
 }
 @override void dispose(){disposed=true;enabled=false;retry?.cancel();changes?.cancel();unawaited(transport.disconnect());super.dispose();}
}
