"""Apply RowSkan platform permissions after flutter create. Safe to rerun."""
from pathlib import Path
import plistlib
root=Path(__file__).resolve().parents[1]
p=root/'android/app/src/main/AndroidManifest.xml'
s=p.read_text()
for permission in ['android.permission.INTERNET','android.permission.CAMERA','android.permission.ACCESS_COARSE_LOCATION','android.permission.ACCESS_FINE_LOCATION']:
    tag=f'<uses-permission android:name="{permission}"/>'
    if permission not in s:s=s.replace('<application',tag+'\n    <application',1)
s=s.replace('android:label="rowskan"','android:label="RowSkan"');p.write_text(s)
for rel in ['ios/Runner/Info.plist','macos/Runner/Info.plist']:
    p=root/rel
    if not p.exists():continue
    with p.open('rb') as f:d=plistlib.load(f)
    d['CFBundleDisplayName']='RowSkan'
    d['NSLocationWhenInUseUsageDescription']='Save a vehicle GPS pin and guide you to it while RowSkan is open.'
    d['NSLocationUsageDescription']='Save and find vehicle locations in your yard.'
    d['NSCameraUsageDescription']='Scan vehicle VIN barcodes and take inventory photos.'
    d['NSPhotoLibraryUsageDescription']='Choose vehicle photographs for your local inventory.'
    with p.open('wb') as f:plistlib.dump(d,f)
for rel in ['macos/Runner/DebugProfile.entitlements','macos/Runner/Release.entitlements']:
    p=root/rel
    if not p.exists():continue
    with p.open('rb') as f:d=plistlib.load(f)
    d['com.apple.security.personal-information.location']=True
    d['com.apple.security.network.client']=True
    d['com.apple.security.files.user-selected.read-write']=True
    with p.open('wb') as f:plistlib.dump(d,f)
# Plugin minimum deployment targets. Xcode may require updating its target too.
p=root/'ios/Podfile'
if p.exists():
    import re
    s=p.read_text();s=re.sub(r"#?\s*platform :ios, '[^']+'", "platform :ios, '15.5'",s);p.write_text(s)
print('RowSkan permissions configured. Review Apple deployment target in Xcode.')


# Keep Xcode project targets aligned with scanner plugin requirements.
p=root/'ios/Runner.xcodeproj/project.pbxproj'
if p.exists():
    import re
    s=p.read_text()
    s=re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;', 'IPHONEOS_DEPLOYMENT_TARGET = 15.5;',s)
    p.write_text(s)


# geolocator needs foreground location only; omit the always-location permission.
p=root/'ios/Podfile'
if p.exists():
    s=p.read_text()
    marker='flutter_additional_ios_build_settings(target)'
    patch="""
    if target.name == 'geolocator_apple'
      target.build_configurations.each do |config|
        config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)']
        config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] << 'BYPASS_PERMISSION_LOCATION_ALWAYS=1'
      end
    end
"""
    if 'BYPASS_PERMISSION_LOCATION_ALWAYS=1' not in s and marker in s:
        p.write_text(s.replace(marker,marker+patch))
