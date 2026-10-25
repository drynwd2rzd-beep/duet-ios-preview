from pathlib import Path
import argparse, hashlib, json, plistlib, re, zipfile

root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--ipa',type=Path)
args=parser.parse_args()
required=['Duet/DuetApp.swift','Duet/Info.plist','Duet/Web/index.html','Duet/Web/native-adapt.css','Duet/Web/local-state.js','Duet/Web/assets/lucide.js','Duet/Web/assets/openai.svg','Duet/Web/assets/claude.svg','Duet/Assets.xcassets/AppIcon.appiconset/Icon-1024.png']
for name in required:
    file=root/name
    assert file.is_file() and file.stat().st_size>0, f'Missing: {name}'
with (root/'Duet/Info.plist').open('rb') as f: info=plistlib.load(f)
assert info['NSCameraUsageDescription']
html=(root/'Duet/Web/index.html').read_text(encoding='utf-8')
assert 'window.duetUIReady=true' in html
assert 'native-command' in html
assert not re.search(r'(?:src|href)=["\x27]https?://',html), 'Runtime remote resource remains'
assert '@import url' not in html, 'Remote font import remains'
for item in json.loads((root/'Duet/Web/assets/manifest.json').read_text(encoding='utf-8')):
    assert hashlib.sha256((root/'Duet/Web/assets'/item['file']).read_bytes()).hexdigest()==item['sha256'], item['file']
swift=(root/'Duet/DuetApp.swift').read_text(encoding='utf-8')
assert '#available(iOS 26.0' in swift and '.glassEffect(' in swift
if args.ipa:
    with zipfile.ZipFile(args.ipa) as archive:
        names=set(archive.namelist())
        for name in ['Payload/Duet.app/Duet','Payload/Duet.app/Info.plist','Payload/Duet.app/Web/index.html','Payload/Duet.app/Web/assets/lucide.js']:
            assert name in names,f'IPA missing {name}'
        binary=archive.read('Payload/Duet.app/Duet')
        assert binary[:4] in [b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca'], 'Expected iPhone Mach-O executable'
        packaged=plistlib.loads(archive.read('Payload/Duet.app/Info.plist'))
        assert packaged['CFBundleIdentifier']=='app.duet.preview'
print('Project validation passed'+(' and IPA structure verified' if args.ipa else ' (Xcode compilation is still required)'))
