#!/usr/bin/env python3
"""Restore pinned project-local runtime components; no system package installation."""
from pathlib import Path
import hashlib,json,urllib.request,subprocess,shutil,xml.etree.ElementTree as ET,os
ROOT=Path(__file__).resolve().parents[1]
CACHE=ROOT/'Library/Cache'
CACHE.mkdir(parents=True,exist_ok=True)
ITEMS=[
 ('wine','11.0_1','https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.0_1/wine-stable-11.0_1-osx64.tar.xz','b50dc50ec7f41d58b115a6b685d4d1315ba3c797bd3aa0f49213f2703cb82388'),
 ('7zip','26.05','https://github.com/ip7z/7zip/releases/download/26.05/7z2605-mac.tar.xz','12ef6830317743cfd3f0ab1724bde43fcc270d8b6d8564f8c12c2a2b7f993570'),
 ('gstreamer','1.28.6','https://gstreamer.freedesktop.org/data/pkg/osx/1.28.6/gstreamer-1.0-1.28.6-universal.pkg','a8eb366c59b7e9e5dc049848fed6bcd203a8878aa7517c051639fda78797c6ad')]
def merge(src,dst):
 if src.is_symlink():
  if dst.is_symlink() or dst.exists():
   if dst.is_dir() and not dst.is_symlink():raise RuntimeError('Directory conflict: '+str(dst))
   dst.unlink()
  dst.parent.mkdir(parents=True,exist_ok=True);dst.symlink_to(os.readlink(src))
 elif src.is_dir():
  dst.mkdir(parents=True,exist_ok=True)
  for child in src.iterdir():merge(child,dst/child.name)
 else:
  dst.parent.mkdir(parents=True,exist_ok=True)
  if dst.is_symlink():dst.unlink()
  shutil.copy2(src,dst)
manifest=[]
for name,version,url,expected in ITEMS:
 destination=CACHE/url.rsplit('/',1)[-1]
 if not destination.exists():
  partial=destination.with_suffix(destination.suffix+'.partial')
  print('Downloading '+name,flush=True)
  req=urllib.request.Request(url,headers={'User-Agent':'MoonBridge/0.1'})
  with urllib.request.urlopen(req,timeout=90) as response,open(partial,'wb') as out:
   while True:
    block=response.read(1024*1024)
    if not block:break
    out.write(block)
  partial.replace(destination)
 digest=hashlib.sha256()
 with open(destination,'rb') as source:
  for block in iter(lambda:source.read(1024*1024),b''):digest.update(block)
 if digest.hexdigest()!=expected:raise RuntimeError('Checksum mismatch: '+str(destination)+'. Remove this failed download and try again.')
 print('SHA-256 verified: '+name,flush=True)
 if name in ['wine','7zip']:
  folder=ROOT/'Runtime'/('Wine' if name=='wine' else 'Tools');folder.mkdir(parents=True,exist_ok=True)
  subprocess.run(['/usr/bin/tar','-xf',str(destination),'-C',str(folder)],check=True)
 else:
  expanded=CACHE/'gstreamer-expanded'
  if not expanded.exists():subprocess.run(['/usr/sbin/pkgutil','--expand-full',str(destination),str(expanded)],check=True)
  media=ROOT/'Runtime/Media';media.mkdir(parents=True,exist_ok=True)
  for payload in expanded.rglob('Payload'):
   if payload.is_dir():
    info=ET.parse(payload.parent/'PackageInfo').getroot();location=info.attrib.get('install-location','/')
    merge(payload,media/location.lstrip('/'))
  framework=media/'Library/Frameworks/GStreamer.framework';versions=framework/'Versions'
  if not (versions/'Current').exists():(versions/'Current').symlink_to('1.0')
  plugin=versions/'1.0/lib/gstreamer-1.0/libgstpython.dylib'
  if plugin.exists():
   disabled=media/'DisabledPlugins';disabled.mkdir(exist_ok=True)
   if (disabled/plugin.name).exists():(disabled/plugin.name).unlink()
   shutil.move(str(plugin),str(disabled/plugin.name))
 manifest.append(dict(name=name,version=version,url=url,sha256=expected,verified=True))
(ROOT/'metadata').mkdir(exist_ok=True)
(ROOT/'metadata/runtime-sources.json').write_text(json.dumps(manifest,indent=2))
print('Project-local runtime ready. Rosetta is a host prerequisite; this script does not install it.')
