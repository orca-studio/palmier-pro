#!/usr/bin/env python3
"""Build a local Palmier LUT package from the reviewed Jianying HD monochrome capture."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
from convert_vf import convert

RESOURCE_ID = '7429744855724641545'
VOLUME_SHA = '284c1307f9d75d4935c09fbef0508a10ddb217a4cb06df7c7fa7df2d992569cb'


def package(source, destination):
    source, destination = Path(source), Path(destination)
    roots = [source] if (source/'config.json').is_file() else [p.parent for p in source.glob('*/config.json')]
    if len(roots) != 1:
        raise ValueError('Expected exactly one effect revision; select its directory explicitly')
    root = roots[0]
    volume = root/'AmazingFeature/texture/filter.cube.vf'
    if hashlib.sha256(volume.read_bytes()).hexdigest() != VOLUME_SHA:
        raise ValueError('Unreviewed LUT content; this adapter accepts only the captured HD monochrome resource')
    if destination.exists():
        raise FileExistsError(destination)
    inventory = []
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            raise ValueError('Symlinked resources are unsupported')
        if path.is_file():
            data = path.read_bytes()
            inventory.append({'path': str(path.relative_to(root)), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    stage = Path(tempfile.mkdtemp(prefix='.effect-stage-', dir=destination.parent))
    try:
        convert(volume, stage/'look.cube')
        manifest = {'schema': 'palmier.effect-package/v1', 'id': 'local.jianying.'+RESOURCE_ID,
                    'name': '高清黑白', 'renderer': 'color.lut',
                    'resource': {'path': 'look.cube', 'sha256': hashlib.sha256((stage/'look.cube').read_bytes()).hexdigest()},
                    'source': {'resourceId': RESOURCE_ID, 'files': inventory},
                    'limitations': ['Tetrahedral interpolation; native pixel parity unverified', 'No native Lua or scene execution']}
        (stage/'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
        stage.rename(destination)
    except BaseException:
        shutil.rmtree(stage)
        raise
    return manifest


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('source', type=Path)
    p.add_argument('destination', type=Path)
    a = p.parse_args()
    m = package(a.source, a.destination)
    print(json.dumps({'id': m['id'], 'package': str(a.destination), 'sourceFiles': len(m['source']['files'])}))
