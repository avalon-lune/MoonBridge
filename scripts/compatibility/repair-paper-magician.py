from pathlib import Path
import json,struct,zlib,hashlib,collections,re
import argparse
parser=argparse.ArgumentParser(description="Build the validated Paper Magician KiriKiri Z compatibility overlay.")
parser.add_argument('--game-dir',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--report',type=Path,required=True)
parser.add_argument('--only-script')
args=parser.parse_args();g=args.game_dir.resolve()
KNOWN_ARCHIVES = {'data.xp3': '9f7f8696ba3cc3ea6d8a532aaf74b7a5a1004cc99c896b22b2b927da14a31368', 'patch.xp3': 'a924bc6b6ee954396cc447d2c2f72e11d7982322755fe6a70cbb80e358aeebff', 'patch2.xp3': '4c8e262981e8de9c81961b4de3075344d91dc0d7ab4436d3574127d9317837a6'}
for name,expected in KNOWN_ARCHIVES.items():
 actual=hashlib.sha256((g/name).read_bytes()).hexdigest()
 if actual != expected:raise SystemExit('This repair recipe does not match the imported game archive: '+name)

def chunks(b):
 p=0
 while p+12<=len(b):
  tag=b[p:p+4];size=struct.unpack_from('<Q',b,p+4)[0];assert p+12+size<=len(b);yield tag,b[p+12:p+12+size];p+=12+size
items={};skips=[];errors=[]
for archive,encoding in [('data.xp3','cp932'),('patch.xp3','cp932'),('patch2.xp3','gbk')]:
 with (g/archive).open('rb') as f:
  assert f.read(11)==b'XP3\r\n \n\x1a\x8bg\x01';off=struct.unpack('<Q',f.read(8))[0];indices=[]
  for _ in range(8):
   f.seek(off);flag=f.read(1)[0];size=struct.unpack('<Q',f.read(8))[0]
   if flag&1:
    orig=struct.unpack('<Q',f.read(8))[0];idx=zlib.decompress(f.read(size));assert len(idx)==orig
   else:idx=f.read(size)
   indices.append(idx)
   if not flag&0x80:break
   off=struct.unpack('<Q',f.read(8))[0]
  for tag,record in chunks(b''.join(indices)):
   if tag!=b'File':continue
   parts=dict(chunks(record));info=parts[b'info'];flags,orig,comp,n=struct.unpack_from('<IQQH',info);name=info[22:22+n*2].decode('utf-16le')
   if Path(name).suffix.lower() not in ['.tjs','.ks','.asd']:continue
   data=bytearray()
   for pos in range(0,len(parts[b'segm']),28):
    sf,so,sz,co=struct.unpack_from('<IQQQ',parts[b'segm'],pos);f.seek(so);b=f.read(co);data.extend(zlib.decompress(b) if sf&1 else b)
   data=bytes(data)
   if flags or (b'\0' in data[:128] and not data.startswith((b'\xff\xfe',b'\xfe\xff'))) or data.startswith(b'TJS2'):
    skips.append((archive,name,'binary or protected'));continue
   try:
    if data.startswith((b'\xff\xfe',b'\xfe\xff')):text=data.decode('utf-16');codec='utf-16'
    elif data.startswith(b'\xef\xbb\xbf'):text=data.decode('utf-8-sig');codec='utf-8'
    else:text=data.decode(encoding);codec=encoding
   except UnicodeDecodeError as e:errors.append((archive,name,str(e)));continue
   items[Path(name).name.lower()]={'archive':archive,'name':name,'text':text,'encoding':codec,'source_sha256':hashlib.sha256(data).hexdigest()}
print('Scripts',len(items),'skips',skips,'errors',errors,flush=True)
assert not errors
payload=bytearray();index=bytearray();changes=[]
def ch(t,d):return t+struct.pack('<Q',len(d))+d
for key,item in items.items():
 if args.only_script and key != args.only_script.lower():continue
 name=item['name'];text=item['text']
 if key=='mainwindow.tjs':
  assert text.count('setLayerPos(0, 0);')==2 and text.count('setLayerPos(x, y);')==1
  text=text.replace('setLayerPos(0, 0);', 'if(typeof setLayerPos != "undefined") setLayerPos(0, 0);').replace('setLayerPos(x, y);', 'if(typeof setLayerPos != "undefined") setLayerPos(x, y);')
 text=re.sub(r'(?m)^(\s*)(?:innerSunken|showScrollBars)\s*=\s*(?:true|false);', r'\1/* MoonBridge: obsolete window decoration omitted for KiriKiri Z. */', text)
 if key=='menus.tjs':
  assert text.count('super.MenuItem(window, caption);')==1
  text=text.replace('super.MenuItem(window, caption);', 'if(!(window instanceof "Window")) window = global.kag;\n\t\tsuper.MenuItem(window, caption);')
 if key=='config.tjs':text='if(typeof global.MenuItem == "undefined") Plugins.link("menu.dll");\r\nif(typeof global.KAGParser == "undefined") Plugins.link("KAGParser.dll");\r\n'+text
 data=b'\xff\xfe'+text.encode('utf-16le');packed=zlib.compress(data);offset=19+len(payload);payload.extend(packed)
 entry=ch(b'info',struct.pack('<IQQH',0,len(data),len(packed),len(name))+name.encode('utf-16le'))+ch(b'segm',struct.pack('<IQQQ',1,offset,len(data),len(packed)))+ch(b'adlr',struct.pack('<I',zlib.adler32(data)));index.extend(ch(b'File',entry))
 changes.append({k:v for k,v in item.items() if k!='text'}|{'converted_sha256':hashlib.sha256(data).hexdigest()})
zi=zlib.compress(index);result=b'XP3\r\n \n\x1a\x8bg\x01'+struct.pack('<Q',19+len(payload))+payload+b'\x01'+struct.pack('<QQ',len(zi),len(index))+zi
args.output.write_bytes(result);args.report.write_text(json.dumps({'files':changes,'skips':skips,'overlay_sha256':hashlib.sha256(result).hexdigest()},ensure_ascii=False,indent=2));print('Overlay',len(result),'bytes',flush=True)
