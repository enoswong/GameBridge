import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location('audit', pathlib.Path(__file__).with_name('audit-mobile-session.py'))
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class SessionAuditTests(unittest.TestCase):
    def test_empty_log_unknown_not_success(self):
        r = audit.analyze([], 'game.exe')
        self.assertIsNone(r['peak_footprint_mb'])
        self.assertIsNone(r['gpu_requested'])
        self.assertFalse(r['expected_game_spawn_observed'])
        self.assertEqual(r['assessment'], 'insufficient_evidence')

    def test_steam_and_memory_signals_not_game_launch(self):
        r = audit.analyze([
            '[phase] spawn:L"C:\\\\Steam\\\\steam.exe" t+ 3.110s rev=ml526',
            '[phase] spawn:L"C:\\\\Steam\\\\steamwebhelper.exe" t+ 5.465s rev=ml526',
            '[footprint] rev=x phys=1323 MB (peak 3731) internal=100 MB compressed=99 MB',
            '[footprint] rev=x fast phys=3506 MB compressed=1053 MB',
            '[fonts] ml2330 font_init pid 0020: 7 families, 8 faces from the font directories',
            'E 174 Failed to mprotect last page of code buffer.',
            'E 254 [JITPOOL_RIP #1] GuestRIP=0x123 (HOST PC LEAKED INTO STATE.RIP)',
            '[proc-gate] V8 JITLESS (interpreted) (MADEIRA_JITLESS=unset)',
            '[gamebridge-steam] CEF GPU acceleration requested=0',
            'madeira.cfg absent: legacy madeira-*.txt files apply',
        ], 'game.exe')
        self.assertEqual(r['peak_footprint_mb'], 3731)
        self.assertEqual(r['peak_compressed_mb'], 1053)
        self.assertEqual(r['font_families_max'], 7)
        self.assertEqual(r['guard_page_failures'], 1)
        self.assertEqual(r['host_pc_leak_reports'], 1)
        self.assertEqual(r['steam_spawn_seconds'], 3.110)
        self.assertEqual(r['webhelper_spawn_count'], 1)
        self.assertFalse(r['gpu_requested'])
        self.assertFalse(r['v8_jit_requested'])
        self.assertFalse(r['config_present'])
        self.assertEqual(r['assessment'], 'steam_spawn_only')

    def test_game_spawn_is_not_playability_and_no_paths_exported(self):
        r = audit.analyze([
            '[phase] spawn:L"C:\\\\PrivatePerson\\\\GAME.EXE" t+ 4.2s rev=ml526',
            '[gamebridge-fonts] installed NotoSansCJKsc-Regular.otf',
            '[gamebridge-steam] CEF GPU acceleration requested=1',
            'token=do-not-export',
        ], 'game.exe')
        self.assertTrue(r['expected_game_spawn_observed'])
        self.assertEqual(r['assessment'], 'game_spawn_only')
        self.assertTrue(r['gpu_requested'])
        self.assertEqual(r['cjk_install_events'], 1)
        self.assertNotIn('PrivatePerson', str(r))
        self.assertNotIn('do-not-export', str(r))

    def test_present_config_detected_without_leaking_values(self):
        r = audit.analyze(['[INFO] madeira.cfg: env.TEST=private-value',
                           '[phase] wine-start t+ 0.848s rev=ml526'])
        self.assertTrue(r['config_present'])
        self.assertNotIn('private-value', str(r))

    def test_two_wine_starts_are_not_one_comparable_session(self):
        r = audit.analyze(['[INFO] madeira.cfg: (empty)',
                           '[phase] wine-start t+ 0.848s rev=ml526',
                           '[INFO] madeira.cfg: (empty)',
                           '[phase] wine-start t+ 1.822s rev=ml526'])
        self.assertEqual(r['assessment'], 'multiple_session_markers')

    def test_config_and_wine_start_are_not_double_counted(self):
        r = audit.analyze(['[INFO] madeira.cfg absent: legacy madeira-*.txt files apply',
                           '[phase] wine-start t+ 0.848s rev=ml526',
                           '[phase] spawn:L"steam.exe" t+ 1.923s rev=ml526'])
        self.assertEqual(r['assessment'], 'steam_spawn_only')

    def test_mixed_sessions_rejected_for_comparison(self):
        r = audit.analyze(['madeira.cfg absent: legacy madeira-*.txt files apply',
                           'madeira.cfg absent: legacy madeira-*.txt files apply'], None)
        self.assertEqual(r['assessment'], 'multiple_session_markers')


if __name__ == '__main__':
    unittest.main()
