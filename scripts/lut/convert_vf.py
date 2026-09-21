#!/usr/bin/env python3
"""Convert an explicitly supplied local VF_V RGB float volume to a .cube LUT."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct


def convert(source: Path, destination: Path):
    blob = source.read_bytes()
    if len(blob) < 10 or blob[:4] != b'VF_V':
        raise ValueError('Expected VF_V header')
    x, y, z = struct.unpack_from('<3H', blob, 4)
    if not (2 <= x <= 128 and x == y == z):
        raise ValueError('Expected cubic dimensions in 2...128')
    if len(blob) != 10 + x * y * z * 12:
        raise ValueError('Truncated volume or unsupported trailing data')
    values = struct.unpack_from(f'<{x*y*z*3}f', blob, 10)
    if not all(math.isfinite(v) and 0 <= v <= 1 for v in values):
        raise ValueError('Non-finite or non-normalized LUT values')
    lines = ['TITLE "Local VF LUT"', f'LUT_3D_SIZE {x}', 'DOMAIN_MIN 0 0 0', 'DOMAIN_MAX 1 1 1']
    lines += [' '.join(format(v, '.9g') for v in values[i:i+3]) for i in range(0, len(values), 3)]
    with destination.open('x') as output:
        output.write('\n'.join(lines) + '\n')
    return {'source_sha256': hashlib.sha256(blob).hexdigest(), 'dimension': x,
            'entries': x*y*z, 'payload_bytes': len(blob)-10, 'output': str(destination),
            'sampling': 'x-fastest RGB; Palmier uses tetrahedral interpolation; native texture sampling parity unverified'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    print(json.dumps(convert(args.source, args.destination), indent=2))
