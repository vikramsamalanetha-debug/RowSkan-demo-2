import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowskan/store.dart';
import 'package:rowskan/backup_crypto.dart';

void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 late Directory directory;
 late Store store;
 Map<String,dynamic> vehicle(String id)=>{'id':id,'year':'2020','make':'Ford','model':'F-150','status':'Available','photos':<String>[]};
 setUp(() async {directory=await Directory.systemTemp.createTemp('rowskan-hardening-');store=Store(directory:directory);await store.open();});
 tearDown(() async {await store.db.close();await directory.delete(recursive:true);});
 test('stale updates fail instead of losing a newer edit',() async {
  await store.save(vehicle('a'));final first=(await store.all()).single;
  await store.save({...first,'location':'Row A'});
  await expectLater(store.save({...first,'location':'Row B'}),throwsA(isA<RecordConflict>()));
  expect((await store.all()).single['location'],'Row A');
 });
 test('draft survives reopen and is cleared only by committed save',() async {
  await store.saveDraft('new-vehicle',{'make':'Ford','photos':[]});await store.db.close();
  store=Store(directory:directory);await store.open();
  expect((await store.draft('new-vehicle'))!['make'],'Ford');
  await store.save(vehicle('a'),draftId:'new-vehicle');expect(await store.draft('new-vehicle'),isNull);
 });
 test('phone cannot bypass team restrictions through store calls',() async {
  await store.setSetting('mode','team');await store.save(vehicle('a'));
  await store.db.close();store=Store(directory:directory,desktopOverride:false);await store.open();
  await expectLater(store.setSetting('mode','solo'),throwsStateError);
  await expectLater(store.remove('a'),throwsStateError);
  expect((await store.all()).length,1);
 });
 test('team phone cannot remove an existing photograph',() async {
  final file=File('${directory.path}/capture.jpg');await file.writeAsBytes([255,216,255,217]);
  final name=await store.copyPhoto(file.path);await store.save({...vehicle('a'),'photos':[name]});
  await store.setSetting('mode','team');await store.db.close();
  store=Store(directory:directory,desktopOverride:false);await store.open();
  final first=(await store.all()).single;
  await expectLater(store.save({...first,'photos':<String>[]}),throwsStateError);
  expect((await store.all()).single['photos'],[name]);
 });
 test('invalid second backup record cannot partially import first record',() async {
  final archive=Archive();final data=utf8.encode(jsonEncode({'format':'rowskan-native','version':1,'vehicles':[vehicle('a'),{...vehicle('b'),'status':'invalid'}]}));
  archive.addFile(ArchiveFile('inventory.json',data.length,data));
  await expectLater(store.importBackup(ZipEncoder().encode(archive)),throwsStateError);
  expect(await store.all(),isEmpty);
 });
 test('ZIP traversal and compressed oversized declarations rejected before extraction',(){
  final archive=Archive();archive.addFile(ArchiveFile('../escape',1,[1]));
  expect(()=>inspectZipDirectory(ZipEncoder().encode(archive)),throwsStateError);
 });
 test('audit includes creation, deletion and restore',() async {
  await store.save(vehicle('a'));await store.remove('a');await store.restoreLast();
  expect((await store.audit()).map((e)=>e['kind']).toSet(),{'created','deleted','restored'});
 });
 test('encrypted backup requires matching password and detects tampering',() async {
  final crypto=BackupCrypto();final bytes=await crypto.encrypt([1,2,3],'strong backup password');
  expect(await crypto.decrypt(bytes,'strong backup password'),[1,2,3]);
  await expectLater(crypto.decrypt(bytes,'wrong password'),throwsStateError);
  final data=jsonDecode(utf8.decode(bytes)) as Map<String,dynamic>;data['mac']=base64Encode(List.filled(16,0));
  await expectLater(crypto.decrypt(utf8.encode(jsonEncode(data)),'strong backup password'),throwsStateError);
 });
}
