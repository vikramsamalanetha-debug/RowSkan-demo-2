import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'sync_engine.dart';

class SyncScreen extends StatefulWidget {
 final SyncEngine engine;
 const SyncScreen(this.engine,{super.key});
 @override State<SyncScreen> createState()=>_SyncScreenState();
}
class _SyncScreenState extends State<SyncScreen> {
 final endpoint=TextEditingController(),label=TextEditingController(text:'My RowSkan device'),code=TextEditingController();
 String output='',role='capture';bool busy=false;List<Map<String,dynamic>> conflicts=[];
 SyncEngine get engine=>widget.engine;
 @override void initState(){super.initState();endpoint.text=engine.identity.profile?.endpoint??'';engine.addListener(changed);loadConflicts();}
 void changed(){if(mounted){setState((){});loadConflicts();}}
 Future<void> loadConflicts() async {final rows=await engine.store.syncConflicts();if(mounted)setState(()=>conflicts=rows);}
 @override void dispose(){engine.removeListener(changed);endpoint.dispose();label.dispose();code.dispose();super.dispose();}
 Future<void> run(Future<void> Function() action) async {
  setState(()=>busy=true);
  try{await action();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> reset() async {
  final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Revoke all other devices?'),content:const Text('Every other device will need a new approval. Inventory already saved on those devices cannot be remotely erased. Local inventory is kept.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Revoke approvals'))]));
  if(yes==true)await run(engine.resetPairing);
 }
 @override Widget build(BuildContext context){
  if(!engine.initialized)return const Center(child:Text('Secure device storage is not ready. Local inventory remains available.'));
  return ListView(children:[
   Text('Your devices. Your inventory.',style:Theme.of(context).textTheme.headlineMedium),const SizedBox(height:12),
   const Text('Approved native apps transfer encrypted records, GPS pins and photos while both are online. Inventory stays on your devices. A reachable WebSocket relay is required; the relay keeps no inventory history. Browser inventory is separate.'),const SizedBox(height:16),
   Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(engine.status),const SizedBox(height:8),Text('${engine.peerCount} connected devices · Device ${engine.deviceId.substring(0,12)}'),if(engine.configured)Text('Role: ${engine.store.syncRole}'),if(engine.configured)Wrap(spacing:8,children:[FilledButton.icon(onPressed:busy?null:()=>run(engine.connect),icon:const Icon(Icons.sync),label:const Text('Connect / Sync')),TextButton(onPressed:busy?null:()=>run(engine.disconnect),child:const Text('Pause sync'))])]))),const SizedBox(height:20),
   TextField(controller:label,maxLength:80,decoration:const InputDecoration(labelText:'Device name')),const SizedBox(height:12),
   TextField(controller:endpoint,autocorrect:false,decoration:const InputDecoration(labelText:'Relay address',hintText:'wss://your-server.example/relay')),const SizedBox(height:12),
   if(!engine.configured)FilledButton(onPressed:busy?null:()=>run(() async {await engine.createWorkspace(endpoint.text,label.text);}),child:const Text('Create owner workspace')),
   if(engine.configured)OutlinedButton(onPressed:busy?null:()=>run(() async {await engine.disconnect();await engine.identity.updateEndpoint(endpoint.text);}),child:const Text('Save relay address')),
   const SizedBox(height:24),Text('Pair a device',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:8),
   const Text('On the joining device, generate a request. Give it to the owner. The owner approves it and returns a private approval code. Paste that approval on the joining device. Pairing shares this device’s saved inventory with the workspace.'),const SizedBox(height:12),
   OutlinedButton(onPressed:busy?null:()=>run(() async {output=await engine.identity.requestCode(label.text,desktop:engine.store.desktop);}),child:const Text('Generate this device’s request')),
   const SizedBox(height:12),TextField(controller:code,minLines:3,maxLines:6,autocorrect:false,enableSuggestions:false,decoration:const InputDecoration(labelText:'Paste request or approval code')),const SizedBox(height:12),
   if(engine.isOwner)...[
    DropdownButtonFormField<String>(initialValue:role,decoration:const InputDecoration(labelText:'Approve joining device as'),items:const [DropdownMenuItem(value:'capture',child:Text('Phone / capture')),DropdownMenuItem(value:'manager',child:Text('Trusted desktop / manager'))],onChanged:busy?null:(v)=>setState(()=>role=v!)),const SizedBox(height:8),
    const Text('Approve only devices you trust. The desktop role is owner-authorized; device type is not hardware-verified. Capture devices cannot delete shared records or remove saved photos.'),
    OutlinedButton(onPressed:busy?null:()=>run(() async {output=await engine.identity.grant(code.text,role:role);}),child:const Text('Approve pasted request')),
   ],
   if(!engine.isOwner)OutlinedButton(onPressed:busy?null:()=>run(() async {await engine.acceptGrant(code.text);endpoint.text=engine.identity.profile!.endpoint;output='';code.clear();}),child:const Text('Accept owner approval')),
   if(output.isNotEmpty)...[const SizedBox(height:12),const Text('Share directly with the intended device. Approval codes contain private workspace access. Verify the device name and request with its owner.'),const SizedBox(height:8),SelectableText(output,style:const TextStyle(fontSize:11)),TextButton.icon(onPressed:()=>Clipboard.setData(ClipboardData(text:output)),icon:const Icon(Icons.copy),label:const Text('Copy code'))],
   if(engine.isOwner)...[const SizedBox(height:24),OutlinedButton(onPressed:busy?null:reset,child:const Text('Revoke all other device approvals'))],
   const SizedBox(height:24),Text('Conflicts (${conflicts.length})',style:Theme.of(context).textTheme.titleLarge),
   if(conflicts.isEmpty)const Padding(padding:EdgeInsets.symmetric(vertical:12),child:Text('No changes waiting for review.')),
   for(final conflict in conflicts)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(conflict['reason'] as String),SelectableText(_summary(conflict)),if(engine.isOwner)Wrap(spacing:8,children:[TextButton(onPressed:busy?null:()=>run(() async {await engine.store.resolveSyncConflict(conflict['id'] as String,useIncoming:false);await loadConflicts();}),child:const Text('Keep this device’s version')),TextButton(onPressed:busy?null:()=>run(() async {await engine.store.resolveSyncConflict(conflict['id'] as String);await loadConflicts();await engine.inventoryChanged?.call();}),child:const Text('Use incoming version'))])else const Text('Review on the owner device.')]))) ,
   const SizedBox(height:24),const Text('Sync runs while the app is open. Offline edits are queued locally. Keep regular encrypted backups: sync is not a backup. Revoking approvals cannot remove previously shared inventory. Hosting and paid cloud storage are not provisioned by this app.'),const SizedBox(height:24),
  ]);
 }
 String _summary(Map<String,dynamic> conflict){final op=jsonDecode(conflict['operation'] as String) as Map,record=op['record'] as Map;return 'Incoming: ${record['year']} ${record['make']} ${record['model']}\nVIN ${record['vin']} · ${record['location']}\n${record['notes']}';}
}
