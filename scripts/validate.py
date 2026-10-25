from pathlib import Path
import argparse,plistlib,zipfile

root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--ipa',type=Path);args=p.parse_args()
swift=list((root/'Duet').glob('*.swift'))
assert len(swift)>=6,'Native source files missing'
for file in swift:
    text=file.read_text(encoding='utf-8')
    assert 'import WebKit' not in text and 'WKWebView' not in text and 'loadHTMLString' not in text,'Web UI is not allowed: '+file.name
assert 'glassEffect' in (root/'Duet/NativeStyle.swift').read_text(encoding='utf-8')
assert 'maximumZoomScale = 4' in (root/'Duet/NativePhotos.swift').read_text(encoding='utf-8')
assert (root/'Duet/Assets.xcassets/BrandGPT.imageset/Contents.json').is_file()
if args.ipa:
    with zipfile.ZipFile(args.ipa) as z:
        assert z.testzip() is None
        names=z.namelist()
        assert not any(n.lower().endswith(('.html','.js','.css')) for n in names),'A web interface was bundled in the native IPA'
        assert 'Payload/Duet.app/Duet' in names
        assert z.read('Payload/Duet.app/Duet')[:4]==b'\xcf\xfa\xed\xfe'
        info=plistlib.loads(z.read('Payload/Duet.app/Info.plist'))
        assert info['CFBundleShortVersionString']=='0.2.0'
print('Native-only source validation passed'+(' and IPA verified without HTML/JS/CSS' if args.ipa else ''))
