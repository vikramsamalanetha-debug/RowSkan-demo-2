import 'package:flutter_test/flutter_test.dart';
import 'package:rowskan/geo_math.dart';
import 'package:rowskan/store.dart';
import 'dart:io';
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 final gps={'lat':35.6500,'lon':-88.3900,'accuracyMeters':7.0,'source':'gps','capturedAt':'2026-11-03T12:00:00Z'};
 test('distance and bearing handle cardinal directions and date line',(){
  expect(distanceMeters(0,0,0,0),0);
  expect(distanceMeters(0,0,0,1),closeTo(111195,1));
  expect(bearingDegrees(0,0,1,0),closeTo(0,0.001));
  expect(bearingDegrees(0,0,0,1),closeTo(90,0.001));
  expect(distanceMeters(0,179.999,0,-179.999),closeTo(222.39,1));
  expect(cardinal(359),'N');expect(cardinal(225),'SW');
 });
 test('manual offset moves correct distance and does not invent accuracy',(){
  final moved=offsetGps(gps,30,40);
  expect(distanceMeters(35.65,-88.39,moved['lat'] as double,moved['lon'] as double),closeTo(50,0.2));
  expect(moved['source'],'manual');expect(moved['accuracyMeters'],isNull);
 });
 test('coordinates, timestamps and accuracy are validated',(){
  expect(validateGps(null),isNull);expect(validateGps(gps)!['lat'],35.65);
  expect(()=>validateGps({...gps,'lat':double.nan}),throwsFormatException);
  expect(()=>validateGps({...gps,'lon':190}),throwsFormatException);
  expect(()=>validateGps({...gps,'accuracyMeters':-2}),throwsFormatException);
  expect(()=>validateGps({...gps,'capturedAt':'bad'}),throwsFormatException);
 });
 test('GPS persists in inventory, drafts and backup transfer',() async {
  final dir=await Directory.systemTemp.createTemp('rowskan-gps-');final otherDir=await Directory.systemTemp.createTemp('rowskan-gps-import-');
  final store=Store(directory:dir),other=Store(directory:otherDir);await store.open();await other.open();
  try{
   await store.save({'id':'gps-test','make':'Ford','model':'F-150','status':'Available','photos':[],'gps':gps});
   expect((await store.all()).single['gps'],gps);
   await store.saveDraft('new-vehicle',{'gps':gps});expect((await store.draft('new-vehicle'))!['gps'],gps);
   await other.importBackup(await store.backup());expect((await other.all()).single['gps'],gps);
  }finally{await store.db.close();await other.db.close();await dir.delete(recursive:true);await otherDir.delete(recursive:true);}
 });
}
