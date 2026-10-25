"""Convert the approved standalone fragment to a local, full-screen app document."""
from pathlib import Path
import argparse
import re

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('source',type=Path)
args=parser.parse_args()
s=args.source.read_text(encoding='utf-8')
s=s.replace(' class="viz-dotted-background"','')
s=re.sub(r"@import url\('https://fonts.googleapis.com/[^\n]+\);",'',s)
s=s.replace("https://unpkg.com/@lobehub/icons-static-svg@latest/icons/openai.svg",'assets/openai.svg').replace("https://unpkg.com/@lobehub/icons-static-svg@latest/icons/claude.svg",'assets/claude.svg')
s=re.sub(r'^ if\(globalThis.Tweak\).*$', '', s, flags=re.M)
# Escape attribute quotes as well as markup; names and attachment filenames are user input.
s=s.replace('return n.innerHTML}', 'return n.innerHTML.replace(/"/g,\'&quot;\').replace(/\x27/g,\'&#39;\')}')
s=s.replace("function close(){sheet.hidden=true}","function close(){sheet.hidden=true;publishNativeShell()}",1)
s=s.replace("if(field)field.focus()}","if(field)field.focus();publishNativeShell()}",1)
s=s.replace("applyFont();applyTheme();applyWallpapers()}","applyFont();applyTheme();applyWallpapers();publishNativeShell()}",1)
s=s.replace("fitKeyboardViewport();icons()}\n function showThread", "fitKeyboardViewport();icons();publishNativeShell()}\n function showThread",1)
s=s.replace("arrive(root.querySelector('.dm-detail'),12,0);save()}","arrive(root.querySelector('.dm-detail'),12,0);save();publishNativeShell()}",1)
s=s.replace("function feedback(text,tone='neutral'){", "function feedback(text,tone='neutral'){nativePost({type:'haptic',style:tone==='success'?'success':'light'});",1)
s=s.replace("function animateIdeaCompletion(id){", "function animateIdeaCompletion(id){nativePost({type:'haptic',style:'selection'});",1)
s=s.replace("state.outbox.push({targets,contexts,text", "nativePost({type:'haptic',style:'light'});state.outbox.push({targets,contexts,text",1)
hooks=(ROOT/'scripts/native-hooks.js').read_text(encoding='utf-8')
# Function declarations must precede the early applyAppearance call; hook initialization uses the fully-built DOM.
declarations='\n'.join(line for line in hooks.splitlines() if line.startswith(' function '))
initializers='\n'.join(line for line in hooks.splitlines() if not line.startswith(' function '))
s=s.replace(' function actionButton(',declarations+'\n function actionButton(',1)
s=s.replace(' showPage(state.page,false);',' showPage(state.page,false);\n'+initializers,1)
s=s.replace('<script>\n(()=>{','<link rel="stylesheet" href="native-adapt.css">\n<script>\n(()=>{',1)
font=next((ROOT/'Duet/Web/assets').glob('cormorant.*'))
font_format='woff2' if font.suffix=='.woff2' else 'truetype'
head='''<!doctype html>
<html lang="zh-CN"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="color-scheme" content="light dark">
<meta http-equiv="Content-Security-Policy" content="default-src 'self' data: blob:; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data: blob:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
<title>Duet</title>
<script src="assets/lucide.js"></script><script src="local-state.js"></script>
<style>@font-face{font-family:'Cormorant Garamond';src:url('assets/FONTFILE') format('FONTFORMAT');font-weight:400 500;font-style:normal;font-display:swap}svg.lucide{display:inline-block;vertical-align:middle;flex-shrink:0}button{cursor:pointer}button:disabled{cursor:default}</style>
</head><body>
'''.replace('FONTFILE',font.name).replace('FONTFORMAT',font_format)
(ROOT/'Duet/Web/index.html').write_text(head+s+'\n</body></html>\n',encoding='utf-8',newline='\n')
print('Web/index.html',len((head+s).encode('utf-8')),'bytes')
