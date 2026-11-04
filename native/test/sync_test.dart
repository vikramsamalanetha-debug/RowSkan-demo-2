import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowskan/store.dart';
import 'package:rowskan/sync_identity.dart';
import 'package:rowskan/sync_engine.dart';

Map<String,dynamic> vehicle({String id='vehicle-one',List<String> photos=const []})=>{'id':id,'make':'Honda','model':'Accord','year':'2020','status':'Available','photos':photos,'gps':{'lat':33.1,'lon':-84.2,'accuracyMeters':4,'source':'gps','capturedAt':'2026-11-04T00:00:00Z'}};
Future<void> eventually(Future<bool> Function() check) async {
 final until=DateTime.now().add(const Duration(seconds:20));
 while(DateTime.now().isBefore(until)){if(await check())return;await Future<void>.delayed(const Duration(milliseconds:30));}
 throw StateError('Sync did not converge before timeout.');
}
// Opaque relay fixture: deliberately knows no inventory, signatures or keys.
class RelayFixture {
 late HttpServer server;final clients=<WebSocket,String>{};final frames=<List<int>>[];
 Future<String> start() async {
  server=await HttpServer.bind(InternetAddress.loopbackIPv4,0);
  server.listen((request) async {
   final socket=await WebSocketTransformer.upgrade(request);
   socket.listen((event){
    if(event is String){final join=jsonDecode(event) as Map;clients[socket]=join['room'] as String;socket.add(jsonEncode({'type':'joined'}));}
    else if(event is List<int>){frames.add(event);for(final entry in clients.entries){if(entry.key!=socket&&entry.value==clients[socket])entry.key.add(event);}}
   },onDone:()=>clients.remove(socket),onError:(Object _){});
  });return 'ws://127.0.0.1:${server.port}/relay';
 }
 Future<void> close() async {for(final socket in clients.keys.toList()){await socket.close();}await server.close(force:true);}
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('owner certificates bind identity, role, epoch and signed payload',() async {
  final owner=SyncIdentity(MemoryKeyVault()),phone=SyncIdentity(MemoryKeyVault()),stranger=SyncIdentity(MemoryKeyVault());
  await owner.open();await phone.open();await stranger.open();await owner.createWorkspace('wss://relay.example/relay',label:'Owner');
  final request=await phone.requestCode('Capture phone',desktop:false),grant=await owner.grant(request,role:'capture');
  await phone.acceptGrant(grant);expect((await phone.member(phone.profile!.certificate)).role,'capture');
  await expectLater(stranger.acceptGrant(grant),throwsStateError);
  await expectLater(owner.grant(request,role:'manager'),throwsStateError);
  final packet=await phone.signPacket({'type':'operation','text':'original'});
  expect((await owner.verifyPacket(packet)).author.canManage,isFalse);
  final outer=jsonDecode(packet) as Map,wrapper=jsonDecode(outer['message'] as String) as Map;
  wrapper['payload']=(wrapper['payload'] as String).replaceFirst('original','tampered');outer['message']=jsonEncode(wrapper);
  await expectLater(owner.verifyPacket(jsonEncode(outer)),throwsStateError);
  await owner.resetPairing();await expectLater(owner.verifyPacket(packet),throwsStateError);
 });
 test('repository enforces capture policy, preserves conflicts and tombstones',() async {
  final dir=await Directory.systemTemp.createTemp('rowskan-sync-policy-'),store=Store(directory:dir,desktopOverride:false);await store.open();
  addTearDown(() async {await store.db.close();await dir.delete(recursive:true);});
  await store.photo('saved.jpg').writeAsBytes([1,2,3]);await store.save(vehicle(photos:['saved.jpg']));
  await store.setSyncRole('capture');await expectLater(store.remove('vehicle-one'),throwsStateError);
  await expectLater(store.setSetting('mode','solo'),throwsStateError);
  var current=(await store.all()).single;
  Map<String,dynamic> operation(String id,Map<String,dynamic> record,{String kind='upsert',int base=1,int rev=2,bool deleted=false})=>{'id':id,'recordId':'vehicle-one','record':record,'kind':kind,'baseRevision':base,'revision':rev,'deleted':deleted};
  await expectLater(store.applySyncOperation(operation('bad-delete',current,kind:'delete',deleted:true),'proof',role:'capture',owner:false),throwsStateError);
  await expectLater(store.applySyncOperation(operation('bad-photo',{...current,'photos':<String>[]}), 'proof',role:'capture',owner:false),throwsStateError);
  await store.setSyncRole('owner');await store.save({...current,'notes':'owner edit'});
  expect(await store.applySyncOperation(operation('conflict',{...current,'notes':'incoming edit'}),'proof',role:'manager',owner:false),'conflict');
  expect((await store.all()).single['notes'],'owner edit');expect((await store.syncConflicts()).length,1);
  await store.resolveSyncConflict('conflict');expect((await store.all()).single['notes'],'incoming edit');
  current=(await store.all()).single;await store.remove('vehicle-one');
  await expectLater(store.applySyncOperation(operation('stale-phone',current,base:current['_revision'] as int,rev:(current['_revision'] as int)+1),'proof',role:'capture',owner:false),throwsStateError);
  expect(await store.all(),isEmpty);
 });
 test('two devices transfer encrypted records, GPS, chunked photos and deletion',() async {
  final relay=RelayFixture(),url=await relay.start();
  final aDir=await Directory.systemTemp.createTemp('rowskan-owner-'),bDir=await Directory.systemTemp.createTemp('rowskan-phone-');
  final a=Store(directory:aDir,desktopOverride:true),b=Store(directory:bDir,desktopOverride:false);await a.open();await b.open();
  final owner=SyncEngine(a,vault:MemoryKeyVault()),phone=SyncEngine(b,vault:MemoryKeyVault());
  addTearDown(() async {await owner.disconnect();await phone.disconnect();owner.dispose();phone.dispose();await relay.close();await a.db.close();await b.db.close();await aDir.delete(recursive:true);await bDir.delete(recursive:true);});
  await owner.open(autoConnect:false);await phone.open(autoConnect:false);await owner.createWorkspace(url,'Owner desktop');
  final request=await phone.identity.requestCode('Yard phone',desktop:false);await phone.acceptGrant(await owner.identity.grant(request,role:'capture'));
  await owner.connect();await phone.connect();await eventually(() async=>owner.peerCount==1&&phone.peerCount==1);
  final bytes=List<int>.generate(1500000,(i)=>i%251);await a.photo('yard-car.jpg').writeAsBytes(bytes);await a.save(vehicle(photos:['yard-car.jpg']));
  await eventually(() async {
   final files=await Directory('${b.root.path}/sync-stage').list().toList();
   return files.whereType<File>().isNotEmpty;
  });
  await phone.disconnect();
  expect(await b.all(),isEmpty);
  final parts=await Directory('${b.root.path}/sync-stage').list().toList();expect(parts.whereType<File>(),isNotEmpty);
  await phone.connect();
  await eventually(() async=>(await b.all()).length==1);
  expect(await b.photo('yard-car.jpg').readAsBytes(),bytes);expect((await b.all()).single['gps']['lat'],33.1);
  expect(relay.frames.any((frame)=>utf8.decode(frame).contains('Honda')),isFalse);
  expect(relay.frames.any((frame)=>utf8.decode(frame).contains('yard-car.jpg')),isFalse);
  await expectLater(b.remove('vehicle-one'),throwsStateError);
  await phone.disconnect();final item=(await a.all()).single;await a.save({...item,'notes':'offline pending edit'});
  await phone.connect();await eventually(() async=>(await b.all()).single['notes']=='offline pending edit');
  await a.remove('vehicle-one');await eventually(() async=>(await b.all()).isEmpty);
  expect((await b.deleted()).length,1);
 },timeout:const Timeout(Duration(seconds:60)));
}
