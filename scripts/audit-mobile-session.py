#!/usr/bin/env python3
"""Summarize one Madeira session offline; never emit raw paths or credentials."""
import argparse
import json
import re


def analyze(lines, expected_game=None):
    r = dict(peak_footprint_mb=None, peak_compressed_mb=None, font_families_max=None,
             guard_page_failures=0, host_pc_leak_reports=0, steam_spawn_seconds=None,
             webhelper_spawn_count=0, gpu_requested=None, v8_jit_requested=None,
             config_present=None, cjk_install_events=0, expected_game_spawn_observed=False,
             assessment='insufficient_evidence')
    config_markers = 0
    wine_start_markers = 0

    def maximum(key, value):
        r[key] = value if r[key] is None else max(r[key], value)

    for line in lines:
        if '[footprint]' in line:
            for key, pattern in [('peak_footprint_mb', r'\bphys=(\d+) MB'),
                                 ('peak_footprint_mb', r'\(peak (\d+)\)'),
                                 ('peak_compressed_mb', r'\bcompressed=(\d+) MB')]:
                if m := re.search(pattern, line):
                    maximum(key, int(m[1]))
        if '[fonts]' in line and (m := re.search(r'(\d+) families, \d+ faces', line)):
            maximum('font_families_max', int(m[1]))
        if m := re.search(r'\[phase\] spawn:L"([^"\n]+)" t\+\s*([\d.]+)s', line):
            exe = re.split(r'[\\/]', m[1])[-1].casefold()
            if exe == 'steam.exe' and r['steam_spawn_seconds'] is None:
                r['steam_spawn_seconds'] = float(m[2])
            if exe == 'steamwebhelper.exe':
                r['webhelper_spawn_count'] += 1
            if expected_game and exe == expected_game.casefold():
                r['expected_game_spawn_observed'] = True
        r['guard_page_failures'] += 'Failed to mprotect last page of code buffer.' in line
        r['host_pc_leak_reports'] += 'HOST PC LEAKED INTO STATE.RIP' in line
        r['cjk_install_events'] += '[gamebridge-fonts] installed NotoSansCJK' in line
        if m := re.search(r'\[gamebridge-steam\] CEF GPU acceleration requested=([01])', line):
            r['gpu_requested'] = m[1] == '1'
        elif '-cef-disable-gpu' in line and 'steam.exe' in line.lower():
            r['gpu_requested'] = False
        if '[proc-gate] V8 JITLESS' in line:
            r['v8_jit_requested'] = False
        elif '[proc-gate] V8 JIT' in line:
            r['v8_jit_requested'] = True
        if 'madeira.cfg absent: legacy' in line:
            r['config_present'] = False
            config_markers += 1
        elif re.search(r'^(?:\[[^\]]+\]\s*)*madeira\.cfg:', line):
            r['config_present'] = True
            config_markers += 1
        if re.search(r'\[phase\] wine-start\s+t\+', line):
            wine_start_markers += 1
    if max(config_markers, wine_start_markers) > 1:
        r['assessment'] = 'multiple_session_markers'
    elif r['expected_game_spawn_observed']:
        r['assessment'] = 'game_spawn_only'
    elif r['steam_spawn_seconds'] is not None:
        r['assessment'] = 'steam_spawn_only'
    return r


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log')
    parser.add_argument('--game', help='Expected executable basename, not a path')
    args = parser.parse_args()
    if args.game and not re.fullmatch(r'[^/\\]+\.exe', args.game, re.I):
        parser.error('--game must be an executable basename')
    with open(args.log, encoding='utf-8', errors='replace') as stream:
        print(json.dumps(analyze(stream, args.game), indent=2))


if __name__ == '__main__':
    main()
