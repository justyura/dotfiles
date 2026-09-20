import tempfile
import unittest
from pathlib import Path
from activity_history import classify, record, report, segments
from standup_auto import advance


class HistoryTests(unittest.TestCase):
    def test_repeated_shortcut_keeps_original_break(self):
        s, _, _ = advance({}, 1000, 0, False, {}, 2700, 300, 180, action='start-break')
        s, _, _ = advance(s, 1010, 0, False, {}, 2700, 300, 180, action='start-break')
        self.assertEqual(s['break_started'], 1000)
        self.assertEqual(s['phase'], 'manual_break')

    def test_explicit_break_and_early_resume(self):
        s, gain, chime = advance({'tick': 999, 'worked': 120}, 1000, 0, False,
                                 {}, 2700, 300, 180, action='toggle-break')
        self.assertEqual((s['phase'], gain, chime), ('manual_break', 0, False))
        s, gain, _ = advance(s, 1010, 0, False, {'at': 1010, 'status': 'present'}, 2700, 300, 180)
        self.assertEqual((s['phase'], gain), ('manual_break', 0))
        s, gain, _ = advance(s, 1020, 0, False, {}, 2700, 300, 180, action='toggle-break')
        self.assertEqual((s['phase'], s['worked'], gain), ('work', 120, 0))

    def test_early_resume_immediately_reports_work_with_stale_idle_sample(self):
        s = {'tick': 1010, 'worked': 120, 'break_started': 1000, 'phase': 'manual_break'}
        s, gain, _ = advance(s, 1020, 500, False, {}, 2700, 300, 180,
                             action='toggle-break')
        self.assertEqual((s['phase'], s['worked'], gain), ('work', 120, 0))
        self.assertEqual(s['last_seen'], 1020)

    def test_completed_break_then_passive_detection(self):
        s = {'tick': 1295, 'worked': 2600, 'alerted': True, 'break_started': 1000}
        s, gain, chime = advance(s, 1300, 400, False, {}, 2700, 300, 180)
        self.assertEqual((s['phase'], s['worked'], gain, chime), ('away', 0, 0, False))
        self.assertNotIn('break_started', s)
        s, _, _ = advance(s, 1305, 0, False, {}, 2700, 300, 180)
        self.assertEqual(s['phase'], 'work')
        self.assertEqual(classify({'manual_break': True}, {}, 1000, 180, 75), 'manual_break')

    def test_old_manual_pause_cannot_override_activity(self):
        state = {'tick': 990, 'worked': 120, 'manual_until': 1300, 'away_since': 980}
        result, _, _ = advance(state, 1000, 0.1, False, {}, 2700, 300, 180)
        self.assertEqual(result['phase'], 'work')
        self.assertNotIn('manual_until', result)
        self.assertNotIn('away_since', result)

    def test_click_cannot_pause_activity(self):
        result, _, _ = advance({}, 1000, 0, False, {}, 2700, 300, 180, click=True)
        self.assertEqual(result['phase'], 'work')

    def test_evidence(self):
        a = {'idle': 200, 'locked': False}
        self.assertEqual(classify(a, {}, 1000, 180, 75), 'unknown')
        self.assertEqual(classify(a, {'at': 990, 'status': 'present'}, 1000, 180, 75), 'present')
        self.assertEqual(classify(a, {'at': 990, 'status': 'absent'}, 1000, 180, 75), 'away')
        self.assertEqual(classify(a, {'at': 800, 'status': 'present'}, 1000, 180, 75), 'unknown')
        self.assertEqual(classify({'idle': 2}, {}, 1000, 180, 75), 'active')
        self.assertEqual(classify({'idle': 40}, {}, 1000, 180, 75), 'idle')
        self.assertEqual(classify({'locked': True}, {}, 1000, 180, 75), 'locked')
        self.assertEqual(classify({'unavailable': True}, {}, 1000, 180, 75), 'unknown')

    def test_gaps_and_merge(self):
        rows = [{'at': 10, 'state': 'active'}, {'at': 20, 'state': 'active'},
                {'at': 100, 'state': 'locked'}]
        self.assertEqual(segments(rows, 0, 140), [(0, 10, 'unknown'), (10, 50, 'active'),
                                                 (50, 100, 'unknown'), (100, 130, 'locked'),
                                                 (130, 140, 'unknown')])

    def test_daily_report_partial_line(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            record(1750000000, {'idle': 1, 'locked': False}, {}, 180, 75, root)
            path = next(root.glob('*.jsonl'))
            with path.open('a') as f:
                f.write('{')
            output = report(root)
            self.assertIn('查看时间段', output.read_text())
            self.assertIn(path.stem, output.read_text())


if __name__ == '__main__':
    unittest.main()
