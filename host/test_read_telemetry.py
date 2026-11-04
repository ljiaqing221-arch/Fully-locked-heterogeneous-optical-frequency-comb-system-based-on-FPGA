"""Software-only parser checks; generated examples are never laboratory results."""
import csv
from pathlib import Path
import tempfile
import unittest
from read_telemetry import FIELDS, read_snapshot

class ParserTest(unittest.TestCase):
    def fixture(self, folder, fallback=False):
        file = Path(folder) / 'fixture.csv'
        header = ['Sample in Buffer', 'Sample in Window', 'TRIGGER']
        header += [(f'probe{p}' if fallback else f'top/telemetry_{signal.removeprefix("telemetry_")}')
                   + (f'[{width-1}:0]' if width > 1 else '')
                   for _, p, width, _, signal in FIELDS]
        values = {'error_code': -53, 'i_q16': -123456789, 'ii_q16': 7654321, 'd_q16': -987654,
                  'fv_code': 32700, 'target_code': 32768, 'pzt_code': 32800, 'fpga_ticks': 50000000,
                  'sequence': 42, 'flags': 255, 'locked': 1, 'saturated': 0, 'state': 3, 'fault': 0}
        row = ['0', '0', '0'] + [format(values[name] & ((1 << width)-1), 'x')
                                  for name, _, width, _, _ in FIELDS]
        with file.open('w', newline='', encoding='utf-8-sig') as f:
            w = csv.writer(f); w.writerow(header); w.writerow(['Radix - UNSIGNED', 'UNSIGNED', 'HEX'] + ['HEX']*len(FIELDS));w.writerow(row)
        return file, values

    def test_roundtrip_and_probe_fallback(self):
        with tempfile.TemporaryDirectory() as d:
            for fallback in (False, True):
                file, values = self.fixture(d, fallback)
                result = read_snapshot(file)
                for key, value in values.items():self.assertEqual(value, result[key], key)
                self.assertEqual(result['fpga_time_us'], 1000000)

    def test_reject_partial_or_wrong_project(self):
        with tempfile.TemporaryDirectory() as d:
            file, _ = self.fixture(d)
            original = file.read_text('utf-8-sig')
            file.write_text(original.replace('telemetry_sequence', 'other_sequence'), 'utf-8')
            with self.assertRaises(ValueError):read_snapshot(file)
            file.write_text('Sample in Buffer,probe1\n0,ffff\n','utf-8')
            with self.assertRaises(ValueError):read_snapshot(file)

if __name__ == '__main__':unittest.main()
