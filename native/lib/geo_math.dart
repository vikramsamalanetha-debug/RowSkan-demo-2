import 'dart:math' as math;

Map<String,dynamic>? validateGps(dynamic input){
 if(input==null)return null;
 if(input is! Map)throw FormatException('Invalid vehicle GPS location.');
 final lat=input['lat'],lon=input['lon'],accuracy=input['accuracyMeters'];
 if(lat is! num||lon is! num||!lat.isFinite||!lon.isFinite||lat < -90||lat>90||lon < -180||lon>180)throw FormatException('Invalid GPS coordinates.');
 if(accuracy!=null&&(accuracy is! num||!accuracy.isFinite||accuracy<0||accuracy>1000000))throw FormatException('Invalid GPS accuracy.');
 if(input['source']=='gps'&&accuracy==null)throw FormatException('GPS accuracy is required.');
 if(!['gps','manual'].contains(input['source']))throw FormatException('Invalid GPS source.');
 final at=input['capturedAt'];if(at is! String||DateTime.tryParse(at)==null)throw FormatException('Invalid GPS timestamp.');
 return {'lat':lat.toDouble(),'lon':lon.toDouble(),'accuracyMeters':accuracy?.toDouble(),'capturedAt':at,'source':input['source']};
}
double _rad(double value)=>value*math.pi/180;
double distanceMeters(double lat1,double lon1,double lat2,double lon2){
 final a=math.pow(math.sin(_rad(lat2-lat1)/2),2)+math.cos(_rad(lat1))*math.cos(_rad(lat2))*math.pow(math.sin(_rad(lon2-lon1)/2),2);
 return 6371000*2*math.atan2(math.sqrt(a.clamp(0,1)),math.sqrt((1-a).clamp(0,1)));
}
double bearingDegrees(double lat1,double lon1,double lat2,double lon2){
 final delta=_rad(lon2-lon1),a=_rad(lat1),b=_rad(lat2);
 return (math.atan2(math.sin(delta)*math.cos(b),math.cos(a)*math.sin(b)-math.sin(a)*math.cos(b)*math.cos(delta))*180/math.pi+360)%360;
}
String cardinal(double bearing)=>['N','NE','E','SE','S','SW','W','NW'][((bearing+22.5)/45).floor()%8];
Map<String,dynamic> offsetGps(Map<String,dynamic> center,double east,double north){
 final lat=(center['lat'] as num).toDouble(),lon=(center['lon'] as num).toDouble();
 final cosine=math.cos(_rad(lat));
 if(cosine.abs()<0.001)throw StateError('Manual offset is unavailable near the poles. Enter coordinates instead.');
 final latitude=(lat+north/111195).clamp(-90.0,90.0);
 final longitude=((lon+east/(111195*cosine)+540)%360)-180;
 return {'lat':latitude,'lon':longitude,'accuracyMeters':null,'source':'manual','capturedAt':DateTime.now().toUtc().toIso8601String()};
}
