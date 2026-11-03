#!/usr/bin/env python3
"""Prepare the pinned optional KiriKiri Z runtime; never modify a game."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import urllib.request

VERSION = '1.4.0.8'
RELEASE = 'https://github.com/krkrz/krkrz/releases/tag/1.4.0r2'
URL = 'https://github.com/krkrz/krkrz/releases/download/1.4.0r2/krkrz_20171225r2.7z'
SHA256 = 'a58da24a2e14eac102f0fd8bf66106b22ad238d17a317b8d44b65d68efb574df'
EXPECTED = {
    'tvpwin32.exe': '9228f50103b2a7bf95c241bef945fa254750840fd1ce4d4ff0b9a5078724175f',
    'plugin/wuvorbis.dll': '6867cd5e481326315383e9d3cfc18f9f63a5ba38ae53d5ca5833a14366c3f0c7',
    'plugin/krdstheora.dll': '5a169a4c6d82b3f1407c2f0a2989a3727cba815fe99fbba23c9b1761f20df47f',
    'plugin/menu.dll': '81477e01e3bfc1d385c2e7a051adeed568ad97f48a58fdcc5f888736b8749081',
    'plugin/KAGParser.dll': 'aaea83468935c4006432d69aa90629dc6b6edbf43b1144b3cdf8f7c58612863e',
    'plugin/kropus.dll': '67961948af6c18708d5cbf60728e4048487aac9f284c4afd375edd929c0c3580',
    'plugin/krwic.dll': '629b6908e2a6523142763a534a1caefdcb96f6f0628b72bc654b0bff7a596dfc',
    'plugin/extrans.dll': '4877232604b39d620ca1122e2089828bad7c4c8c5b69b136fbc8c1974dda1e66',
}

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def validate(folder):
    for name, expected in EXPECTED.items():
        p = folder / name
        if not p.is_file() or digest(p) != expected:
            raise RuntimeError('Missing or changed pinned component: ' + str(p))
    if not (folder / 'LICENSE.txt').is_file():
        raise RuntimeError('Missing upstream license')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, help='Use an existing official 7z archive')
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--seven-zip', type=Path, help='Override the 7zz executable for an isolated check')
    args = parser.parse_args()
    root = args.root.resolve()
    target = root / 'Runtime/Compatibility' / ('KiriKiriZ-' + VERSION)
    if target.exists():
        validate(target)
        print('Pinned KiriKiri Z already ready: ' + str(target))
        return
    seven_zip = args.seven_zip or root / 'Runtime/Tools/7zz'
    if not seven_zip.is_file() or not os.access(seven_zip, os.X_OK):
        raise RuntimeError('Prepare 7-Zip first with scripts/bootstrap-runtime.py')
    cache = root / 'Library/Cache/Compatibility'
    cache.mkdir(parents=True, exist_ok=True)
    archive = args.archive.resolve() if args.archive else cache / URL.rsplit('/', 1)[-1]
    if not archive.exists():
        if args.archive:
            raise FileNotFoundError(archive)
        partial = archive.with_suffix(archive.suffix + '.partial')
        request = urllib.request.Request(URL, headers={'User-Agent': 'MoonBridge/0.1.1'})
        with urllib.request.urlopen(request, timeout=90) as response, partial.open('wb') as out:
            shutil.copyfileobj(response, out, 1024 * 1024)
        partial.replace(archive)
    if digest(archive) != SHA256:
        raise RuntimeError('SHA-256 mismatch; the archive was not installed')
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='krkrz-prepare-', dir=cache) as temporary:
        work = Path(temporary)
        subprocess.run([str(seven_zip), 'x', '-bd', '-bsp0', '-o' + str(work / 'unpacked'), str(archive)], check=True)
        upstream = work / 'unpacked/krkrz_20171225'
        ready = work / 'ready'
        ready.mkdir()
        for name in EXPECTED:
            output = ready / name
            output.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(upstream / name, output)
        shutil.copy2(upstream / 'license.txt', ready / 'LICENSE.txt')
        shutil.copy2(archive, ready / 'official-source-package.7z')
        (ready / 'source.json').write_text(json.dumps({
            'source': RELEASE, 'download': URL, 'sha256': SHA256,
            'bytes': archive.stat().st_size, 'verified': True,
            'note': 'Official binary distribution archive, not a source-code archive.'
        }, indent=2) + '\n', encoding='utf-8')
        validate(ready)
        ready.rename(target)
    print('Pinned KiriKiri Z prepared: ' + str(target))
    print('No game files or launch settings were changed.')

if __name__ == '__main__':
    main()
