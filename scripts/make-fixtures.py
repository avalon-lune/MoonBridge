#!/usr/bin/env python3
"""Build tiny auditable Win32/Win64 PE probes. No SDK, downloaded executable or commercial game."""
from pathlib import Path
import struct,zipfile,io
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'tests/fixtures'
OUT.mkdir(parents=True,exist_ok=True)
def probe(bits,gui=False,translated=False):
    base=0x400000 if bits==32 else 0x140000000
    data=bytearray(0x600)
    def put(off,fmt,*v):struct.pack_into('<'+fmt,data,off,*v)
    word='I' if bits==32 else 'Q'
    # Import descriptors, lookup tables and import address tables.
    put(0,'IIIII',0x2060,0,0,0x2100,0x2080)
    put(20,'IIIII',0x20a0,0,0,0x2110,0x20c0)
    put(0x60,word,0x2140);put(0x80,word,0x2140)
    put(0xa0,word,0x2160);put(0xc0,word,0x2160)
    data[0x100:0x10d]=b'kernel32.dll\0';data[0x110:0x11b]=b'user32.dll\0'
    data[0x140:0x14e]=b'\0\0ExitProcess\0';data[0x160:0x16e]=b'\0\0MessageBoxW\0'
    text=('汉化补丁样例：中文显示正常。' if translated else '中文显示测试 / 日本語の表示テスト')+'\r\nMoonBridge '+str(bits)+'-bit Windows GUI probe.\r\nThis is a self-test, not a commercial game.'
    title='MoonBridge '+str(bits)+'-bit GUI / 自检样例'
    for off,s in [(0x200,text),(0x450,title)]:
        b=(s+'\0').encode('utf-16le');data[off:off+len(b)]=b
    code=bytearray()
    if bits==32:
        if gui:
            code+=b'\x6a\x00\x68'+struct.pack('<I',base+0x2450)+b'\x68'+struct.pack('<I',base+0x2200)+b'\x6a\x00\xff\x15'+struct.pack('<I',base+0x20c0)
        code+=b'\x6a'+bytes([0 if gui else 37])+b'\xff\x15'+struct.pack('<I',base+0x2080)
    else:
        code+=b'\x48\x83\xec\x28'
        if gui:
            code+=b'\x31\xc9\x48\xba'+struct.pack('<Q',base+0x2200)+b'\x49\xb8'+struct.pack('<Q',base+0x2450)+b'\x45\x31\xc9'
            after=0x1000+len(code)+6;code+=b'\xff\x15'+struct.pack('<i',0x20c0-after)
        code+=b'\xb9'+struct.pack('<I',0 if gui else 37)
        after=0x1000+len(code)+6;code+=b'\xff\x15'+struct.pack('<i',0x2080-after)
    optional=bytearray(224 if bits==32 else 240)
    def opt(off,fmt,*v):struct.pack_into('<'+fmt,optional,off,*v)
    opt(0,'H',0x10b if bits==32 else 0x20b);optional[2]=14
    opt(4,'III',0x200,0x600,0);opt(16,'II',0x1000,0x1000)
    if bits==32:opt(24,'II',0x2000,base)
    else:opt(24,'Q',base)
    opt(32,'II',0x1000,0x200);opt(40,'HHHHHH',6,0,0,0,6,0)
    opt(56,'II',0x3000,0x200);opt(68,'HH',2,0x100)
    if bits==32:opt(72,'IIIIII',0x100000,0x1000,0x100000,0x1000,0,16);dirbase=96
    else:opt(72,'QQQQII',0x100000,0x1000,0x100000,0x1000,0,16);dirbase=112
    opt(dirbase+8,'II',0x2000,60)
    head=bytearray(0x80);head[:2]=b'MZ';struct.pack_into('<I',head,0x3c,0x80)
    head+=b'PE\0\0'+struct.pack('<HHIIIHH',0x14c if bits==32 else 0x8664,2,0,0,0,len(optional),0x102 if bits==32 else 0x22)+optional
    for name,vsize,rva,size,offset,flags in [(b'.text',len(code),0x1000,0x200,0x200,0x60000020),(b'.rdata',0x600,0x2000,0x600,0x400,0x40000040)]:
        head+=struct.pack('<8sIIIIIIHHI',name,vsize,rva,size,offset,0,0,0,0,flags)
    return bytes(head).ljust(0x200,b'\0')+bytes(code).ljust(0x200,b'\0')+bytes(data)
for bits in [32,64]:
    folder=OUT/('probe'+str(bits));folder.mkdir(exist_ok=True)
    (folder/'Probe.exe').write_bytes(probe(bits))
    (folder/'Game.exe').write_bytes(probe(bits,True))
    (folder/'原版台词.txt').write_text('Original dialogue / 原版 / 日本語',encoding='utf-8')
    patch=io.BytesIO()
    with zipfile.ZipFile(patch,'w',zipfile.ZIP_DEFLATED) as z:
        z.writestr('原版台词.txt','汉化后文本 / Translated dialogue')
        z.writestr('GameCN.exe',probe(bits,True,True))
    (folder/'汉化补丁.zip').write_bytes(patch.getvalue())
    package=OUT/('MoonBridge-自检-'+str(bits)+'位.zip')
    with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED) as z:
        for f in folder.iterdir():z.write(f,'月渡 自检/日本語/'+f.name)
with zipfile.ZipFile(OUT/'unsafe-path.zip','w') as z:z.writestr('../escape.txt','must never be extracted')
print('Created auditable PE32 / PE32+ probes, Unicode packages, bundled translation patches and traversal rejection fixture.')
