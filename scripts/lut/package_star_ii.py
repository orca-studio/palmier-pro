#!/usr/bin/env python3
"""Package the reviewed local Star II sequence for Palmier's video compositor."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

PINS = {'seq/a.seq': '53b80072d6461f4e596b68d9905b71537bbb02153e36889eaf2fc2a834b72d91', 'material/entity.material': '2a19100344a20d9a079dcad15c2df4e720c9141c090d3940a32ce92d1d7610ab', 'lua/SeekModeScript.lua': '03437cfcd38f53b3ea445b93d399b5e30a0538161136773465b02c14b624080d'}


def package(source, destination):
    source, destination = Path(source), Path(destination)
    root = source / 'amazingfeature'
    for relative, digest in PINS.items():
        if hashlib.sha256((root/relative).read_bytes()).hexdigest() != digest:
            raise ValueError('Unreviewed sequence timing or material: ' + relative)
    frames = [root/'image'/f'a{i}.png' for i in range(151)]
    if not all(p.is_file() and not p.is_symlink() for p in frames):
        raise ValueError('Missing or symlinked sequence frames')
    if destination.exists():
        raise FileExistsError(destination)
    stage = Path(tempfile.mkdtemp(prefix='.star-stage-', dir=destination.parent))
    try:
        subprocess.run(['ffmpeg', '-v', 'error', '-framerate', '25', '-start_number', '0',
                        '-i', str(root/'image/a%d.png'), '-frames:v', '151', '-c:v', 'prores_ks',
                        '-profile:v', '4', '-pix_fmt', 'yuv444p10le', '-n', str(stage/'overlay.mov')], check=True)
        probe = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-count_frames',
            '-show_entries', 'stream=width,height,nb_read_frames', '-of', 'json', str(stage/'overlay.mov')]))['streams'][0]
        if probe != {'width': 500, 'height': 281, 'nb_read_frames': '151'}:
            raise ValueError('Unexpected sequence geometry or frame count')
        manifest = {'schema': 'palmier.effect-package/v1', 'id': 'local.jianying.7399492057267539234',
            'name': '星光 II', 'renderer': 'overlay.sequence',
            'resource': {'path': 'overlay.mov', 'sha256': hashlib.sha256((stage/'overlay.mov').read_bytes()).hexdigest()},
            'sequence': {'sourceFrames': 151, 'sourceFPS': 25, 'width': 500, 'height': 281, 'blendMode': 'screen'},
            'source': {'metadataHashes': PINS, 'frames': [hashlib.sha256(p.read_bytes()).hexdigest() for p in frames]},
            'limitations': ['single cycle; portrait rotation unverified', 'ProRes intermediate; native pixel parity unverified']}
        (stage/'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
        stage.rename(destination)
    except BaseException:
        shutil.rmtree(stage)
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    package(args.source, args.destination)
