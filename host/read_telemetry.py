"""Vivado ILA CSV -> typed snapshot. Import read_snapshot in the existing GUI.

No GUI or third-party dependencies. Values remain codes until analogue calibration.
"""
from __future__ import annotations
import argparse
import csv
import json
import re
import time
from pathlib import Path

# Name, ILA probe number, width, signed. Must match top_aux_pzt_lock.v.
FIELDS = (
    ("fv_code", 1, 16, False, "telemetry_fv"),
    ("error_code", 2, 18, True, "telemetry_error"),
    ("pzt_code", 3, 16, False, "telemetry_pzt"),
    ("state", 4, 3, False, "telemetry_state"),
    ("locked", 5, 1, False, "telemetry_locked"),
    ("fault", 6, 3, False, "telemetry_fault"),
    ("saturated", 7, 1, False, "telemetry_saturated"),
    ("i_q16", 12, 64, True, "telemetry_i"),
    ("ii_q16", 13, 64, True, "telemetry_ii"),
    ("d_q16", 14, 64, True, "telemetry_d"),
    ("target_code", 15, 16, False, "telemetry_target"),
    ("sequence", 16, 32, False, "telemetry_sequence"),
    ("fpga_ticks", 17, 64, False, "telemetry_ticks"),
    ("flags", 18, 8, False, "telemetry_flags"),
)

def _number(value: str, radix: str, width: int, signed: bool) -> int:
    value = value.strip().replace("_", "")
    if not value or re.search(r"[xXzZ?]", re.sub(r"^0[xX]", "", value)):
        raise ValueError("ILA field contains an unknown or empty value")
    # Accept standard Vivado radix row and Verilog-style prefixes.
    match = re.fullmatch(r"(?:\d+)?'([hHbBdD])([+-]?[0-9a-fA-F]+)", value)
    base = 16 if "HEX" in radix.upper() else 2 if "BIN" in radix.upper() else 10
    if match:
        base = {"h": 16, "b": 2, "d": 10}[match[1].lower()]
        value = match[2]
    elif value.lower().startswith("0x"):
        base = 16
    result = int(value, base)
    if result < 0:
        if not signed or result < -(1 << (width - 1)):
            raise ValueError("signed field out of range")
        return result
    if result >= 1 << width:
        raise ValueError("ILA field exceeds declared width")
    return result - (1 << width) if signed and result & (1 << (width - 1)) else result

def read_snapshot(csv_path: str | Path) -> dict[str, int]:
    """Read the last complete ILA sample. Raises on a wrong/partial capture.

    The bridge publishes files by rename, so an existing GUI can poll this
    function without coordinating a file lock with Vivado.
    """
    with Path(csv_path).open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.reader(stream))
    header_index = next((i for i, r in enumerate(rows)
                         if any("Sample in Buffer" in c for c in r)), None)
    if header_index is None:
        raise ValueError("not a Vivado ILA CSV (sample header missing)")
    header = rows[header_index]
    radix_row = next((r for r in rows[header_index + 1:]
                      if r and r[0].strip().lower().startswith("radix")), None)
    if radix_row is None:
        raise ValueError("Vivado radix row is required; do not guess hex/decimal")
    samples = [r for r in rows[header_index + 1:]
               if len(r) == len(header) and r[0].strip().isdigit()]
    if not samples:
        raise ValueError("capture has no complete sample")
    last = samples[-1]
    result = {"protocol": 1}
    for name, probe, width, signed, signal in FIELDS:
        exact_signal = re.compile(r"(?:^|[/.:])" + re.escape(signal) + r"(?:\[|$)")
        hits = [i for i, col in enumerate(header) if exact_signal.search(col)]
        if not hits:
            hits = [i for i, col in enumerate(header)
                    if re.search(r"(?:^|[/.:])probe" + str(probe) + r"(?:\[|$)", col)]
        if len(hits) != 1:
            raise ValueError(f"missing/ambiguous {signal}; use the matching .bit and .ltx")
        index = hits[0]
        result[name] = _number(last[index], radix_row[index], width, signed)
    result["fpga_time_us"] = result["fpga_ticks"] // 50  # 50 MHz capture domain
    return result

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", nargs="?", default=str(Path(__file__).with_name("live") / "latest.csv"))
    parser.add_argument("--period", type=float, default=1.0)
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()
    previous = None
    while True:
        try:
            snapshot = read_snapshot(args.csv)
            snapshot["stale"] = previous == snapshot["sequence"]
            previous = snapshot["sequence"]
            print(json.dumps(snapshot), flush=True)
        except (OSError, ValueError) as exc:
            print(json.dumps({"error": str(exc)}), flush=True)
            if args.once:
                raise SystemExit(1)
        if args.once:
            return
        time.sleep(max(args.period, 0.1))

if __name__ == "__main__":
    main()
