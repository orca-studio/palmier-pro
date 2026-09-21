import math
from pathlib import Path
import struct
import tempfile
import unittest
from convert_vf import convert


class VolumeConversionTests(unittest.TestCase):
    def test_preserves_float_values_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as folder:
            source, target = Path(folder)/'input.vf', Path(folder)/'output.cube'
            values = [i / 23 for i in range(24)]
            packed = struct.pack('<24f', *values)
            source.write_bytes(b'VF_V'+struct.pack('<3H', 2, 2, 2)+packed)
            self.assertEqual(convert(source, target)['entries'], 8)
            decoded = [float(v) for line in target.read_text().splitlines()[4:] for v in line.split()]
            self.assertEqual(struct.pack('<24f', *decoded), packed)
            with self.assertRaises(FileExistsError):
                convert(source, target)

    def test_rejects_incomplete_nonfinite_and_unsupported_volumes(self):
        good = b'VF_V'+struct.pack('<3H', 2, 2, 2)+struct.pack('<24f', *([0.5]*24))
        for blob in (good[:-1], good+b'x', b'XXXX'+good[4:],
                     b'VF_V'+struct.pack('<3H', 2, 3, 2)+good[10:],
                     good[:10]+struct.pack('<f', math.nan)+good[14:]):
            with self.subTest(blob=blob[:10]), tempfile.TemporaryDirectory() as folder:
                source, target = Path(folder)/'input', Path(folder)/'output'
                source.write_bytes(blob)
                with self.assertRaises(ValueError):
                    convert(source, target)
                self.assertFalse(target.exists())


if __name__ == '__main__':
    unittest.main()
