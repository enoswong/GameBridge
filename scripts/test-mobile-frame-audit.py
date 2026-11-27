import unittest
from frame_audit import summarize

class FrameAuditTests(unittest.TestCase):
    def test_weighted_actual_shown_rate(self):
        result = summarize([
            '[gamebridge-present] frames=150 duration_ms=5000 mode=1 thermal=0',
            '[gamebridge-present] frames=300 duration_ms=6000 mode=1 thermal=2',
        ])
        self.assertEqual(result['sample_count'], 2)
        self.assertEqual(result['shown_frames'], 450)
        self.assertEqual(result['observed_seconds'], 11.0)
        self.assertAlmostEqual(result['shown_fps'], 450/11, places=3)
        self.assertEqual(result['slowest_window_fps'], 30.0)
        self.assertEqual(result['peak_thermal_state'], 'serious')
    def test_no_evidence_is_unknown(self):
        r=summarize(['[promote] link ran 600 ticks in 10.0 s = 60.0 Hz'])
        self.assertIsNone(r['shown_fps'])
        self.assertIsNone(r['peak_thermal_state'])
    def test_zero_frames_is_not_missing(self):
        r=summarize(['[gamebridge-present] frames=0 duration_ms=5000 mode=1 thermal=1'])
        self.assertEqual(r['shown_fps'], 0.0)
        self.assertEqual(r['zero_frame_windows'], 1)
    def test_invalid_samples_not_counted(self):
        r=summarize(['[gamebridge-present] frames=5 duration_ms=0 mode=1 thermal=0',
                     '[gamebridge-present] frames=5 duration_ms=5000 mode=9 thermal=0',
                     '[gamebridge-present] frames=5 duration_ms=5000 mode=1 thermal=99',
                     '[gamebridge-present] frames=5 duration_ms=999999 mode=1 thermal=0'])
        self.assertEqual(r['sample_count'],0)
        self.assertEqual(r['invalid_samples'],4)
    def test_mode_changes_are_detected(self):
        r=summarize(['[gamebridge-present] frames=120 duration_ms=5000 mode=1 thermal=0',
                     '[gamebridge-present] frames=180 duration_ms=5000 mode=3 thermal=1'])
        self.assertEqual(r['pacing_modes'],[1,3])
        self.assertFalse(r['single_pacing_mode'])
    def test_gap_not_a_zero_frame_window(self):
        r=summarize(['[gamebridge-present-gap] duration_ms=21000',
                     '[gamebridge-present] frames=200 duration_ms=5000 mode=1 thermal=3'])
        self.assertEqual(r['gap_count'],1)
        self.assertEqual(r['zero_frame_windows'],0)
        self.assertEqual(r['peak_thermal_state'],'critical')
    def test_private_text_not_exported(self):
        r=summarize(['[gamebridge-present] frames=5 duration_ms=5000 mode=1 thermal=0 private-token=secret',
                     'C:\\Private\\user.exe'])
        self.assertNotIn('secret',str(r))
        self.assertEqual(r['invalid_samples'],1)
    def test_timestamped_log_line(self):
        r=summarize(['[22:12:07.705] [INFO] [gamebridge-present] frames=150 duration_ms=5000 mode=1 thermal=0'])
        self.assertEqual(r['shown_fps'],30)

if __name__=='__main__': unittest.main()
