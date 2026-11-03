import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

const statuses = ['Available', 'In storage', 'For parts', 'Released'];
const vehicleFields = ['vin','year','make','model','color','mileage','location','keys','notes','status'];
bool validVin(String vin) => RegExp(r'^[A-HJ-NPR-Z0-9]{17}$').hasMatch(vin.toUpperCase());
bool canDelete(String mode, {required bool desktop}) => mode == 'solo' || desktop;

class RecordConflict implements Exception {
  final String message;
  RecordConflict(this.message);
  @override String toString() => message;
}

/// All mutation policies live here, including photo and mode restrictions.
class Store {
  final Directory? directory;
  final bool? desktopOverride;
  Store({this.directory,this.desktopOverride});
  late Database db;
  late Directory root;
  bool get desktop => desktopOverride ?? (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  bool get _ffi => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Future<void> open() async {
    root = directory ?? Directory(p.join((await getApplicationSupportDirectory()).path, 'RowSkan'));
    await Directory(p.join(root.path,'photos')).create(recursive:true);
    if (_ffi) sqfliteFfiInit();
    final factory = _ffi ? databaseFactoryFfi : databaseFactory;
    db = await factory.openDatabase(p.join(root.path,'inventory.sqlite'), options:OpenDatabaseOptions(
      version:2,
      onConfigure:(db) async {
        await db.execute('PRAGMA foreign_keys=ON');
        await db.execute('PRAGMA busy_timeout=5000');
      },
      onCreate:(db,version) async {
        await db.execute('CREATE TABLE vehicles(id TEXT PRIMARY KEY, vin TEXT, data TEXT NOT NULL, updated INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, revision INTEGER NOT NULL DEFAULT 1)');
        await db.execute("CREATE UNIQUE INDEX unique_vin ON vehicles(vin) WHERE deleted=0 AND vin IS NOT NULL AND vin<>''");
        await db.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        await db.execute('CREATE TABLE events(id TEXT PRIMARY KEY, vehicle_id TEXT NOT NULL, kind TEXT NOT NULL, created INTEGER NOT NULL)');
        await db.execute('CREATE TABLE drafts(id TEXT PRIMARY KEY, data TEXT NOT NULL, updated INTEGER NOT NULL)');
      },
      onUpgrade:(db,oldVersion,newVersion) async {
        if(oldVersion<2){
          await db.execute('ALTER TABLE vehicles ADD COLUMN revision INTEGER NOT NULL DEFAULT 1');
          await db.execute('CREATE TABLE drafts(id TEXT PRIMARY KEY, data TEXT NOT NULL, updated INTEGER NOT NULL)');
        }
      },
    ));
  }

  Future<String> setting(String key, String fallback) async {
    final rows=await db.query('settings',where:'key=?',whereArgs:[key]);
    return rows.isEmpty ? fallback : rows.first['value'] as String;
  }
  Future<void> setSetting(String key,String value) async {
    if(!['mode','industry','workspace'].contains(key)) throw StateError('Unknown setting.');
    if(key=='mode'){
      if(!['solo','team'].contains(value)) throw StateError('Invalid operating mode.');
      if(await setting('mode','solo')=='team'&&!desktop) throw StateError('A team phone cannot change its role.');
    }
    if(value.length>120) throw StateError('Setting is too long.');
    await db.insert('settings',{'key':key,'value':value},conflictAlgorithm:ConflictAlgorithm.replace);
  }

  Map<String,dynamic> _row(Map<String,Object?> row) => {
    ...Map<String,dynamic>.from(jsonDecode(row['data'] as String) as Map),
    '_revision':row['revision'],
  };
  Future<List<Map<String,dynamic>>> all() async => (await db.query('vehicles',where:'deleted=0',orderBy:'updated DESC')).map(_row).toList();
  Future<List<Map<String,dynamic>>> deleted() async => (await db.query('vehicles',where:'deleted=1',orderBy:'updated DESC')).map(_row).toList();

  Map<String,dynamic> validate(Map<String,dynamic> input) {
    final v=<String,dynamic>{};
    final id=input['id'] ?? const Uuid().v4();
    if(id is! String || !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id)) throw StateError('Invalid record identifier.');
    v['id']=id;
    for(final f in vehicleFields){
      final s=(input[f]??'').toString().trim();
      if(s.length>(f=='notes'?8000:160)) throw StateError('$f is too long.');
      v[f]=s;
    }
    v['vin']=(v['vin'] as String).toUpperCase();
    if((v['vin'] as String).isNotEmpty&&!validVin(v['vin'] as String)) throw StateError('Use a 17-character VIN without I, O or Q, or leave it blank.');
    if((v['make'] as String).isEmpty||(v['model'] as String).isEmpty) throw StateError('Make and model are required.');
    if(!statuses.contains(v['status'])) throw StateError('Choose a valid status.');
    if((v['keys'] as String).isEmpty)v['keys']='Unknown';
    if(!['Yes','No','Unknown'].contains(v['keys'])) throw StateError('Invalid keys selection.');
    for(final f in ['year','mileage']){
      final s=v[f] as String;
      if(s.isEmpty)continue;
      final n=int.tryParse(s);
      if(n==null||(f=='year'?(n<1886||n>2100):(n<0||n>9999999))) throw StateError('Invalid $f.');
    }
    final photos=input['photos']??<String>[];
    if(photos is! List||photos.length>12) throw StateError('Maximum 12 photos per vehicle.');
    final names=<String>[];
    for(final name in photos){
      if(name is! String||!RegExp(r'^[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp|heic|heif)$',caseSensitive:false).hasMatch(name)) throw StateError('Invalid photo filename.');
      if(names.contains(name)) throw StateError('Duplicate photograph.');
      names.add(name);
    }
    v['photos']=names;
    if(input['_revision']!=null){
      if(input['_revision'] is! int)throw StateError('Invalid record revision.');
      v['_revision']=input['_revision'];
    }
    return v;
  }

  Future<void> _event(DatabaseExecutor t,String id,String kind) async {
    await t.insert('events',{'id':const Uuid().v4(),'vehicle_id':id,'kind':kind,'created':DateTime.now().millisecondsSinceEpoch});
  }
  Future<void> save(Map<String,dynamic> input,{String? draftId}) async {
    final v=validate(input);
    for(final name in v['photos'] as List<String>){if(!await photo(name).exists())throw StateError('A photograph is missing. Retake or remove it before saving.');}
    await db.transaction((t) async {
      final rows=await t.query('vehicles',where:'id=?',whereArgs:[v['id']]);
      var revision=1;
      if(rows.isNotEmpty){
        final old=rows.first;
        if(old['deleted']==1)throw StateError('This vehicle was deleted. Restore it first.');
        if(v['_revision']!=old['revision'])throw RecordConflict('This vehicle changed while you were editing. Reopen it to avoid overwriting newer work.');
        revision=(old['revision'] as int)+1;
        final settings=await t.query('settings',where:'key=?',whereArgs:['mode']);
        if(settings.isNotEmpty&&settings.first['value']=='team'&&!desktop){
          final original=(jsonDecode(old['data'] as String)['photos'] as List).cast<String>();
          if(!original.every((v['photos'] as List<String>).contains))throw StateError('Saved team photos can only be removed on desktop.');
        }
      }
      final encoded=Map<String,dynamic>.from(v)..remove('_revision');
      final record={'id':v['id'],'vin':v['vin'],'data':jsonEncode(encoded),'updated':DateTime.now().millisecondsSinceEpoch,'deleted':0,'revision':revision};
      if(rows.isEmpty){await t.insert('vehicles',record);}else{await t.update('vehicles',record,where:'id=?',whereArgs:[v['id']]);}
      await _event(t,v['id'] as String,rows.isEmpty?'created':'updated');
      if(draftId!=null)await t.delete('drafts',where:'id=?',whereArgs:[draftId]);
    });
  }
  Future<void> remove(String id) async {
    if(!canDelete(await setting('mode','solo'),desktop:desktop))throw StateError('Team records can only be deleted on desktop.');
    await db.transaction((t) async {
      final rows=await t.query('vehicles',where:'id=? AND deleted=0',whereArgs:[id]);
      if(rows.isEmpty)throw StateError('Vehicle not found.');
      await t.update('vehicles',{'deleted':1,'revision':(rows.first['revision'] as int)+1,'updated':DateTime.now().millisecondsSinceEpoch},where:'id=?',whereArgs:[id]);
      await _event(t,id,'deleted');
    });
  }
  Future<void> restoreLast() async {
    if(!canDelete(await setting('mode','solo'),desktop:desktop))throw StateError('Restore is desktop-only in team mode.');
    await db.transaction((t) async {
      final rows=await t.query('vehicles',where:'deleted=1',orderBy:'updated DESC',limit:1);
      if(rows.isEmpty)throw StateError('No deleted vehicles to restore.');
      final r=rows.first;
      await t.update('vehicles',{'deleted':0,'revision':(r['revision'] as int)+1,'updated':DateTime.now().millisecondsSinceEpoch},where:'id=?',whereArgs:[r['id']]);
      await _event(t,r['id'] as String,'restored');
    });
  }

  Future<void> saveDraft(String id,Map<String,dynamic> data) async {
    if(!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id))throw StateError('Invalid draft.');
    await db.insert('drafts',{'id':id,'data':jsonEncode(data),'updated':DateTime.now().millisecondsSinceEpoch},conflictAlgorithm:ConflictAlgorithm.replace);
  }
  Future<Map<String,dynamic>?> draft(String id) async {
    final rows=await db.query('drafts',where:'id=?',whereArgs:[id]);
    return rows.isEmpty?null:Map<String,dynamic>.from(jsonDecode(rows.first['data'] as String) as Map);
  }
  Future<void> discardDraft(String id) async {await db.delete('drafts',where:'id=?',whereArgs:[id]);}
  Future<List<Map<String,dynamic>>> audit({int limit=100}) async => (await db.query('events',orderBy:'created DESC',limit:limit.clamp(1,1000).toInt())).map((r)=>Map<String,dynamic>.from(r)).toList();

  Future<String> copyPhoto(String source) async {
    final extension=p.extension(source).toLowerCase();
    if(!['.jpg','.jpeg','.png','.webp','.heic','.heif'].contains(extension))throw StateError('Choose a JPEG, PNG, WebP or HEIC photograph.');
    final file=File(source);
    if(await file.length()>25*1024*1024)throw StateError('Photograph exceeds 25 MB.');
    final name='${const Uuid().v4()}$extension';
    final tmp=File(p.join(root.path,'photos', '.$name.tmp'));
    try{await file.copy(tmp.path);await tmp.rename(photo(name).path);}finally{if(await tmp.exists())await tmp.delete();}
    return name;
  }
  File photo(String name){
    if(p.basename(name)!=name||name=='.'||name=='..')throw StateError('Invalid photo path.');
    return File(p.join(root.path,'photos',name));
  }

  Future<List<int>> backup() async {
    // Snapshot metadata in one SQLite transaction. Photos are immutable files.
    final records=await db.transaction((t) async => (await t.query('vehicles',where:'deleted=0',orderBy:'updated DESC')).map(_row).toList());
    final archive=Archive();
    final payload=utf8.encode(jsonEncode({'format':'rowskan-native','version':1,'exported':DateTime.now().toUtc().toIso8601String(),'vehicles':records}));
    archive.addFile(ArchiveFile('inventory.json',payload.length,payload));
    var total=payload.length;
    for(final name in records.expand((v)=>(v['photos'] as List).cast<String>()).toSet()){
      final f=photo(name);
      if(!await f.exists())throw StateError('Backup stopped: a photograph is missing.');
      total+=await f.length();if(total>200*1024*1024)throw StateError('This workspace exceeds the 200 MB backup limit in this build.');
      final bytes=await f.readAsBytes();archive.addFile(ArchiveFile('photos/$name',bytes.length,bytes));
    }
    return ZipEncoder().encode(archive);
  }

  /// Validate everything first, then stage immutable files and commit all rows.
  /// An error leaves inventory unchanged and removes newly staged photographs.
  Future<int> importBackup(List<int> bytes) async {
    if(bytes.length>220*1024*1024)throw StateError('Backup exceeds 220 MB.');
    inspectZipDirectory(bytes);
    final archive=ZipDecoder().decodeBytes(bytes,verify:true);
    final manifest=archive.findFile('inventory.json');
    if(manifest==null)throw StateError('Not a RowSkan backup.');
    final data=jsonDecode(utf8.decode(manifest.content as List<int>));
    if(data is! Map||data['format']!='rowskan-native'||data['version']!=1||data['vehicles'] is! List)throw StateError('Unsupported backup.');
    final records=data['vehicles'] as List;
    if(records.length>10000)throw StateError('Too many records.');
    final known=await db.query('vehicles',columns:['id','vin']);
    final ids=known.map((v)=>v['id']).toSet();
    final vins=known.map((v)=>v['vin']).where((v)=>v!=null&&v!='').toSet();
    final additions=<Map<String,dynamic>>[];
    final sources=<String,ArchiveFile>{};
    for(final item in records){
      if(item is! Map)throw StateError('Invalid record.');
      final v=validate(Map<String,dynamic>.from(item));
      if(ids.contains(v['id'])||((v['vin'] as String).isNotEmpty&&vins.contains(v['vin'])))continue;
      for(final name in v['photos'] as List<String>){
        final file=archive.findFile('photos/$name');
        if(file==null||!file.isFile||file.size>25*1024*1024)throw StateError('Missing or oversized photograph.');
        sources[name]=file;
      }
      additions.add(v);ids.add(v['id']);if((v['vin'] as String).isNotEmpty)vins.add(v['vin']);
    }
    final staged=<String>[];
    final names=<String,String>{};
    try{
      for(final entry in sources.entries){
        final name='${const Uuid().v4()}${p.extension(entry.key)}';
        staged.add(name);await photo(name).writeAsBytes(entry.value.content as List<int>,flush:true);names[entry.key]=name;
      }
      await db.transaction((t) async {
        for(final input in additions){
          final v=Map<String,dynamic>.from(input)..remove('_revision');
          v['photos']=(v['photos'] as List<String>).map((n)=>names[n]!).toList();
          await t.insert('vehicles',{'id':v['id'],'vin':v['vin'],'data':jsonEncode(v),'updated':DateTime.now().millisecondsSinceEpoch,'deleted':0,'revision':1});
          await _event(t,v['id'] as String,'imported');
        }
      });
      return additions.length;
    }catch(_){for(final name in staged){try{if(await photo(name).exists())await photo(name).delete();}catch(_){}}rethrow;}
  }
}

/// Bound ZIP expansion BEFORE decompressing. Reject multi-volume and ZIP64 files,
/// duplicate paths, symlinks, traversal and excessive uncompressed sizes.
void inspectZipDirectory(List<int> bytes){
  int u16(int o)=>bytes[o]|bytes[o+1]<<8;
  int u32(int o)=>bytes[o]|bytes[o+1]<<8|bytes[o+2]<<16|bytes[o+3]<<24;
  if(bytes.length<22)throw StateError('Invalid ZIP.');
  var end=-1;
  for(var i=bytes.length-22;i>=0&&i>=bytes.length-65557;i--){if(u32(i)==0x06054b50&&i+22+u16(i+20)==bytes.length){end=i;break;}}
  if(end<0||u16(end+4)!=0||u16(end+6)!=0)throw StateError('Unsupported ZIP.');
  final entries=u16(end+10),offset=u32(end+16),length=u32(end+12);
  if(entries==65535||offset<0||offset+length!=end||entries>120001||u16(end+8)!=entries)throw StateError('Unsupported ZIP directory.');
  var at=offset,total=0;
  final names=<String>{};
  for(var i=0;i<entries;i++){
    if(at<0||at+46>end||u32(at)!=0x02014b50)throw StateError('Invalid ZIP directory.');
    final flags=u16(at+8),method=u16(at+10),size=u32(at+24),nameLength=u16(at+28),extra=u16(at+30),comment=u16(at+32);
    if(size<0||size==0xffffffff||(flags&1)!=0||![0,8].contains(method)||at+46+nameLength+extra+comment>end)throw StateError('Unsupported ZIP entry.');
    final name=utf8.decode(bytes.sublist(at+46,at+46+nameLength));
    if(!names.add(name)||name.contains('..')||name.contains('\\')||name.startsWith('/')||name.contains(':')||((u32(at+38)>>16)&0xf000)==0xa000)throw StateError('Unsafe ZIP path.');
    if(name!='inventory.json'&&!RegExp(r'^photos/[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp|heic|heif)$',caseSensitive:false).hasMatch(name))throw StateError('Unexpected backup entry.');
    if(size>(name=='inventory.json'?16*1024*1024:25*1024*1024))throw StateError('Backup entry too large.');
    total+=size;if(total>220*1024*1024)throw StateError('Expanded backup exceeds limit.');
    at+=46+nameLength+extra+comment;
  }
  if(at!=end||!names.contains('inventory.json'))throw StateError('Invalid backup directory.');
}
