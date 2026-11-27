"""Summarize bounded DXMT shown-frame windows, not individual frame timings."""
import argparse
import json
import re

_SAMPLE = re.compile(r'\[gamebridge-present\] frames=(\d{1,10}) duration_ms=(\d{1,8}) mode=(\d) thermal=(\d)$')
_GAP = re.compile(r'\[gamebridge-present-gap\] duration_ms=(\d{1,12})$')
_THERMAL = ('nominal', 'fair', 'serious', 'critical')


def summarize(lines):
    count = frames = millis = zero = invalid = gaps = 0
    slowest = peak_thermal = None
    modes = set()
    for line in lines:
        line = line.rstrip('\r\n')
        if '[gamebridge-present-gap]' in line:
            if _GAP.search(line):
                gaps += 1
            else:
                invalid += 1
            continue
        if '[gamebridge-present]' not in line:
            continue
        m = _SAMPLE.search(line)
        if not m:
            invalid += 1
            continue
        f, ms, mode, thermal = map(int, m.groups())
        if not (5000 <= ms <= 10000 and 0 <= mode <= 4 and 0 <= thermal <= 3 and f <= ms):
            invalid += 1
            continue
        count += 1
        frames += f
        millis += ms
        zero += f == 0
        modes.add(mode)
        rate = f * 1000 / ms
        slowest = rate if slowest is None else min(slowest, rate)
        peak_thermal = thermal if peak_thermal is None else max(peak_thermal, thermal)
    return dict(sample_count=count, shown_frames=frames, observed_seconds=millis / 1000,
                shown_fps=round(frames * 1000 / millis, 4) if millis else None,
                slowest_window_fps=round(slowest, 4) if slowest is not None else None,
                zero_frame_windows=zero, gap_count=gaps, invalid_samples=invalid,
                pacing_modes=sorted(modes), single_pacing_mode=len(modes) == 1,
                peak_thermal_state=_THERMAL[peak_thermal] if peak_thermal is not None else None)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', help='One exported Madeira session log')
    args = parser.parse_args()
    with open(args.log, encoding='utf-8', errors='replace') as stream:
        print(json.dumps(summarize(stream), indent=2))
