import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'geo_math.dart';

Future<Map<String,dynamic>> captureGps() async {
 if(!await Geolocator.isLocationServiceEnabled())throw StateError('Turn on device location services, then try again.');
 var permission=await Geolocator.checkPermission();
 if(permission==LocationPermission.denied)permission=await Geolocator.requestPermission();
 if(permission==LocationPermission.denied||permission==LocationPermission.deniedForever)throw StateError('Location permission is off. Enable it in device settings, or enter coordinates manually.');
 final fix=await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.best,timeLimit:Duration(seconds:25)));
 return validateGps({'lat':fix.latitude,'lon':fix.longitude,'accuracyMeters':fix.accuracy,'source':'gps','capturedAt':fix.timestamp.toUtc().toIso8601String()})!;
}
String gpsSummary(Map<String,dynamic>? gps){
 if(gps==null)return 'No GPS pin saved. Add one while standing beside the vehicle.';
 return '${(gps['lat'] as num).toStringAsFixed(6)}, ${(gps['lon'] as num).toStringAsFixed(6)}\n${gps['source']=='manual'?'Manually adjusted · accuracy unknown':'GPS accuracy ±${(gps['accuracyMeters'] as num?)?.round()??'?'} m'} · ${gps['capturedAt']}';
}
class VehicleLocationField extends StatefulWidget {
 final Map<String,dynamic>? value;final ValueChanged<Map<String,dynamic>> onChanged;
 const VehicleLocationField({super.key,required this.value,required this.onChanged});
 @override State<VehicleLocationField> createState()=>_VehicleLocationFieldState();
}
class _VehicleLocationFieldState extends State<VehicleLocationField>{
 bool busy=false;
 Future<void> capture() async {setState(()=>busy=true);try{final gps=await captureGps();if(mounted)widget.onChanged(gps);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}finally{if(mounted)setState(()=>busy=false);}}
 Future<void> adjust() async {final value=await Navigator.push<Map<String,dynamic>>(context,MaterialPageRoute(builder:(_)=>AdjustVehiclePin(initial:widget.value)));if(value!=null&&mounted)widget.onChanged(value);}
 @override Widget build(BuildContext context)=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
  Text('Vehicle GPS location',style:Theme.of(context).textTheme.titleMedium),const SizedBox(height:8),Text(gpsSummary(widget.value)),
  const SizedBox(height:10),Wrap(spacing:10,runSpacing:8,children:[FilledButton.tonalIcon(onPressed:busy?null:capture,icon:const Icon(Icons.my_location),label:Text(busy?'Getting location…':widget.value==null?'Save current GPS':'Vehicle moved: update GPS')),OutlinedButton(onPressed:busy?null:adjust,child:const Text('Adjust pin / enter coordinates'))]),
  const SizedBox(height:8),const Text('Stand beside the vehicle. Location stays with its local record. GPS can be several spaces off; keep the yard row and space too.',style:TextStyle(fontSize:12)),
 ])));
}
class FindVehicle extends StatefulWidget {
 final Map<String,dynamic> target;final String title,yard;
 const FindVehicle({super.key,required this.target,required this.title,required this.yard});
 @override State<FindVehicle> createState()=>_FindVehicleState();
}
class _FindVehicleState extends State<FindVehicle> with WidgetsBindingObserver {
 StreamSubscription<Position>? subscription;Position? fix;String status='Tap Start walking guide to use your location.';bool running=false;
 @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);}
 @override void dispose(){WidgetsBinding.instance.removeObserver(this);subscription?.cancel();super.dispose();}
 @override void didChangeAppLifecycleState(AppLifecycleState state){if(state!=AppLifecycleState.resumed&&running){stop();}}
 void stop(){subscription?.cancel();subscription=null;if(mounted)setState((){running=false;status='Guide paused. Tap Start to resume.';});}
 Future<void> start() async {
  if(running)return;setState((){running=true;status='Getting your current position…';});
  try{final first=await captureGps();if(!mounted||!running)return;
   setState(()=>status='Location acquired. Waiting for live updates…');
   // Start a foreground-only stream. No background-location permission is used.
   subscription=Geolocator.getPositionStream(locationSettings:const LocationSettings(accuracy:LocationAccuracy.best,distanceFilter:1)).listen((position){if(mounted)setState((){fix=position;status='Live guide · north is up';});},onError:(Object e){stop();if(mounted)setState(()=>status='Location unavailable. Check permission and try again.');});
   if(mounted)setState(()=>initial=first);
  }catch(e){if(mounted)setState((){running=false;status=e.toString();});}
 }
 Map<String,dynamic>? initial;
 Future<void> maps() async {
  final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Open Maps?'),content:const Text('The saved vehicle coordinates will be sent to Google Maps. Its route may not include private yard aisles.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),TextButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Open Maps'))]));
  if(ok!=true)return;
  final uri=Uri.https('www.google.com','/maps/dir/',{'api':'1','destination':'${widget.target['lat']},${widget.target['lon']}','travelmode':'walking'});
  if(!await launchUrl(uri,mode:LaunchMode.externalApplication)&&mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not open Maps.')));
 }
 @override Widget build(BuildContext context){
  final lat=fix?.latitude??(initial?['lat'] as num?)?.toDouble(),lon=fix?.longitude??(initial?['lon'] as num?)?.toDouble();
  final accuracy=fix?.accuracy??(initial?['accuracyMeters'] as num?)?.toDouble();
  final targetLat=(widget.target['lat'] as num).toDouble(),targetLon=(widget.target['lon'] as num).toDouble();
  final distance=lat==null||lon==null?null:distanceMeters(lat,lon,targetLat,targetLon);
  final bearing=lat==null||lon==null?null:bearingDegrees(lat,lon,targetLat,targetLon);
  final tolerance=(accuracy??0)+((widget.target['accuracyMeters'] as num?)?.toDouble()??0);
  return Scaffold(appBar:AppBar(title:const Text('Find this vehicle')),body:ListView(padding:const EdgeInsets.all(20),children:[Text(widget.title,style:Theme.of(context).textTheme.headlineSmall),Text(widget.yard.isEmpty?'Yard location not entered':widget.yard),const SizedBox(height:16),
   SizedBox(height:280,child:CustomPaint(painter:YardGuidePainter(distance:distance,bearing:bearing))),
   Text(distance==null?'Location not started':'${distance<1000?distance.round().toString()+' m':(distance/1000).toStringAsFixed(2)+' km'} · ${cardinal(bearing!)} (${bearing.round()}° from north)',textAlign:TextAlign.center,style:Theme.of(context).textTheme.headlineSmall),
   const SizedBox(height:12),Text(status,textAlign:TextAlign.center),
   if(accuracy!=null)Text('Your accuracy ±${accuracy.round()} m · vehicle ${widget.target['accuracyMeters']==null?'manually pinned':'±${(widget.target['accuracyMeters'] as num).round()} m'}',textAlign:TextAlign.center),
   if(distance!=null&&distance<=math.max(5,tolerance))const Padding(padding:EdgeInsets.all(12),child:Text('You are within the GPS uncertainty area. Check the vehicle photo, VIN, and row/space to identify the correct vehicle.',textAlign:TextAlign.center)),
   const SizedBox(height:16),FilledButton.icon(onPressed:running?stop:start,icon:Icon(running?Icons.pause:Icons.navigation),label:Text(running?'Pause guide':'Start walking guide')),const SizedBox(height:10),OutlinedButton(onPressed:maps,child:const Text('Open walking directions in Google Maps')),
   const SizedBox(height:16),Text('Saved pin: ${gpsSummary(widget.target)}'),const SizedBox(height:12),const Text('Straight-line yard guide, not a routed path. North stays at the top; the diagram does not follow the phone’s orientation. Follow accessible yard aisles. Your live position is not stored.'),
  ]));
 }
}
class YardGuidePainter extends CustomPainter {
 final double? distance,bearing;YardGuidePainter({this.distance,this.bearing});
 @override void paint(Canvas c,Size s){final center=Offset(s.width/2,s.height/2),radius=math.min(s.width,s.height)*.38;final paint=Paint()..color=const Color(0xffd6e2d9)..style=PaintingStyle.stroke..strokeWidth=1;
  for(var i=1;i<=3;i++)c.drawCircle(center,radius*i/3,paint);
  c.drawLine(Offset(center.dx,center.dy-radius),Offset(center.dx,center.dy+radius),paint);c.drawLine(Offset(center.dx-radius,center.dy),Offset(center.dx+radius,center.dy),paint);
  void label(String t,Offset at,Color color){final text=TextPainter(text:TextSpan(text:t,style:TextStyle(color:color,fontSize:13,fontWeight:FontWeight.bold)),textDirection:TextDirection.ltr)..layout();text.paint(c,at-Offset(text.width/2,text.height/2));}
  label('N',Offset(center.dx,center.dy-radius-18),const Color(0xff182d33));label('E',Offset(center.dx+radius+18,center.dy),const Color(0xff182d33));label('S',Offset(center.dx,center.dy+radius+18),const Color(0xff182d33));label('W',Offset(center.dx-radius-18,center.dy),const Color(0xff182d33));
  c.drawCircle(center,8,Paint()..color=const Color(0xff246ad3));label('You',center+const Offset(0,22),const Color(0xff246ad3));
  if(distance!=null&&bearing!=null){final scale=math.max(20,distance!*1.3),r=radius*math.min(1,distance!/scale),a=bearing!*math.pi/180;final target=center+Offset(math.sin(a)*r,-math.cos(a)*r);c.drawLine(center,target,Paint()..color=const Color(0xff136b54)..strokeWidth=2);c.drawCircle(target,9,Paint()..color=const Color(0xffd97420));label('Vehicle',target+const Offset(0,-22),const Color(0xff9e4c0c));label('Outer ring ${scale.round()} m',Offset(center.dx,s.height-6),const Color(0xff6d7d80));}
 }
 @override bool shouldRepaint(covariant YardGuidePainter old)=>old.distance!=distance||old.bearing!=bearing;
}
class AdjustVehiclePin extends StatefulWidget {
 final Map<String,dynamic>? initial;const AdjustVehiclePin({super.key,this.initial});
 @override State<AdjustVehiclePin> createState()=>_AdjustVehiclePinState();
}
class _AdjustVehiclePinState extends State<AdjustVehiclePin>{
 late TextEditingController latitude,longitude;Map<String,dynamic>? anchor;double range=50;String error='';
 @override void initState(){super.initState();anchor=widget.initial;latitude=TextEditingController(text:widget.initial?['lat'].toString()??'');longitude=TextEditingController(text:widget.initial?['lon'].toString()??'');}
 @override void dispose(){latitude.dispose();longitude.dispose();super.dispose();}
 void pick(Offset point,Size size){if(anchor==null)return;try{final gps=offsetGps(anchor!,((point.dx/size.width)-.5)*range*2,(.5-point.dy/size.height)*range*2);setState((){latitude.text=(gps['lat'] as num).toStringAsFixed(7);longitude.text=(gps['lon'] as num).toStringAsFixed(7);});}catch(e){setState(()=>error=e.toString());}}
 void save(){try{final gps=validateGps({'lat':double.tryParse(latitude.text),'lon':double.tryParse(longitude.text),'accuracyMeters':null,'source':'manual','capturedAt':DateTime.now().toUtc().toIso8601String()});Navigator.pop(context,gps);}catch(e){setState(()=>error='Enter valid latitude (-90 to 90) and longitude (-180 to 180).');}}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Adjust vehicle pin')),body:ListView(padding:const EdgeInsets.all(20),children:[const Text('Enter coordinates, or tap the local yard grid around the saved pin. This grid has no satellite imagery. North is up.'),const SizedBox(height:16),
  if(anchor!=null)...[SizedBox(height:240,child:LayoutBuilder(builder:(c,size)=>GestureDetector(onTapDown:(d)=>pick(d.localPosition,Size(size.maxWidth,240)),onPanUpdate:(d)=>pick(d.localPosition,Size(size.maxWidth,240)),child:CustomPaint(painter:PinEditorPainter(anchor:anchor!,latitude:double.tryParse(latitude.text),longitude:double.tryParse(longitude.text),range:range),child:const SizedBox.expand())))),Slider(value:range,min:10,max:200,divisions:19,label:'±${range.round()} m',onChanged:(n)=>setState(()=>range=n)),Text('Grid extent ±${range.round()} m from saved reference')],
  const SizedBox(height:16),TextField(controller:latitude,decoration:const InputDecoration(labelText:'Latitude'),keyboardType:const TextInputType.numberWithOptions(decimal:true,signed:true)),const SizedBox(height:12),TextField(controller:longitude,decoration:const InputDecoration(labelText:'Longitude'),keyboardType:const TextInputType.numberWithOptions(decimal:true,signed:true)),if(error.isNotEmpty)Text(error,style:const TextStyle(color:Colors.red)),const SizedBox(height:16),FilledButton(onPressed:save,child:const Text('Use corrected pin')),const SizedBox(height:12),const Text('Manual corrections have no measured GPS accuracy. Saving this screen updates the intake field; save the vehicle to confirm the change.'),
 ]));
}

class PinEditorPainter extends CustomPainter {
 final Map<String,dynamic> anchor;final double? latitude,longitude;final double range;
 PinEditorPainter({required this.anchor,required this.latitude,required this.longitude,required this.range});
 @override void paint(Canvas canvas,Size size){
  canvas.drawRect(Offset.zero&size,Paint()..color=const Color(0xffedf3e8));
  final grid=Paint()..color=const Color(0xffc9d8c9)..strokeWidth=1;
  for(var i=1;i<4;i++){canvas.drawLine(Offset(size.width*i/4,0),Offset(size.width*i/4,size.height),grid);canvas.drawLine(Offset(0,size.height*i/4),Offset(size.width,size.height*i/4),grid);}
  canvas.drawCircle(Offset(size.width/2,size.height/2),4,Paint()..color=const Color(0xff6d7d80));
  final lat=latitude??(anchor['lat'] as num).toDouble(),lon=longitude??(anchor['lon'] as num).toDouble();
  final north=(lat-(anchor['lat'] as num))*111195,east=(((lon-(anchor['lon'] as num)+540)%360)-180)*111195*math.cos((anchor['lat'] as num)*math.pi/180);
  final point=Offset((size.width/2+east/(range*2)*size.width).clamp(8,size.width-8).toDouble(),(size.height/2-north/(range*2)*size.height).clamp(8,size.height-8).toDouble());
  canvas.drawCircle(point,9,Paint()..color=const Color(0xffd97420));
  final text=TextPainter(text:const TextSpan(text:'N ↑   ·   Tap or drag to move pin',style:TextStyle(color:Color(0xff182d33),fontSize:13)),textDirection:TextDirection.ltr)..layout();text.paint(canvas,Offset((size.width-text.width)/2,8));
 }
 @override bool shouldRepaint(covariant PinEditorPainter old)=>old.latitude!=latitude||old.longitude!=longitude||old.range!=range;
}
