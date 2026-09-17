"""Run without extra packages: python3 -m unittest discover -s tests -p test_performance_monitor.py."""
import importlib.util
import json
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'tools/performance_monitor.py'
SPEC = importlib.util.spec_from_file_location('performance_monitor', SCRIPT)
monitor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(monitor)


class MonitorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def event(self, kind, node='scene', **fields):
        return json.dumps(dict(event=kind, node_id=node, ts='2026-09-17T00:00:00Z', **fields)) + '\n'

    def test_incremental_partial_lines_and_truncation(self):
        path = self.root / 'events.jsonl'
        first = self.event('session_start')
        path.write_text(first + '{"event":')
        tail = monitor.TraceTail()
        self.assertEqual(tail.poll(path)['active_sessions'], 1)
        with path.open('a') as stream:
            stream.write('"session_start","node_id":"child"}\ninvalid\n')
        state = tail.poll(path)
        self.assertEqual(state['active_sessions'], 2)
        self.assertEqual(state['trace_peak_active'], 2)
        self.assertEqual(state['malformed_lines'], 1)
        self.assertEqual(tail.poll(path)['session_starts'], 2)
        path.write_text(first)
        self.assertEqual(tail.poll(path)['session_starts'], 1)

    def test_root_stop_and_resume(self):
        path = self.root / 'events.jsonl'
        path.write_text(self.event('session_start') + self.event('session_start', 'child')
                        + self.event('stop', parent_id='-', depth=0))
        tail = monitor.TraceTail()
        state = tail.poll(path)
        self.assertEqual(state['active_sessions'], 0)
        self.assertTrue(state['root_stopped'])
        with path.open('a') as stream:
            stream.write(self.event('session_start'))
        state = tail.poll(path)
        self.assertEqual(state['active_sessions'], 1)
        self.assertFalse(state['root_stopped'])

    def test_discovery_of_later_sequential_runs(self):
        for name in ('medieval-r1', 'city-r1'):
            path = self.root / name / 'runs' / name / 'trace/events.jsonl'
            path.parent.mkdir(parents=True)
            path.write_text('')
            self.assertIn(path, monitor.trace_paths(self.root))
            self.assertEqual(monitor.trace_paths(path.parent.parent), [path])
        self.assertEqual(len(monitor.trace_paths(self.root)), 2)

    def test_trace_read_is_bounded(self):
        path = self.root / 'events.jsonl'
        path.write_text(self.event('session_start') * 10)
        tail = monitor.TraceTail()
        with patch.object(monitor, 'READ_LIMIT', 100):
            state = tail.poll(path)
        self.assertEqual(tail.offset, 100)
        self.assertGreater(state['unread_bytes'], 0)

    def test_cpu_excludes_duplicate_guest_counters(self):
        busy, wait = monitor.cpu_delta([0] * 10, [20, 0, 10, 60, 10, 0, 0, 0, 20, 0])
        self.assertEqual(busy, 30)
        self.assertEqual(wait, 10)

    def test_process_tree_handles_spaces_in_names_and_exclusion(self):
        def process(pid, children):
            directory = self.root / str(pid)
            (directory / 'task' / str(pid)).mkdir(parents=True)
            fields = ['S'] + ['0'] * 21
            fields[11], fields[12], fields[19], fields[21] = '10', '20', '123', '5'
            (directory / 'stat').write_text(f'{pid} (name with ) spaces) ' + ' '.join(fields))
            (directory / 'task' / str(pid) / 'children').write_text(children)
        process(100, '101 102')
        process(101, '')
        tree = monitor.process_tree(100, self.root, exclude=101)
        self.assertEqual(list(tree), [(100, 123)])
        self.assertEqual(tree[(100, 123)]['ticks'], 30)

    def test_report_weights_intervals_and_tolerates_partial_last_line(self):
        log = self.root / 'performance.jsonl'
        rows = [dict(type='metadata', target=str(self.root), logical_cpus=4)]
        for elapsed, interval, busy in ((1, 1, 20), (4, 3, 60)):
            rows.append(dict(type='sample', elapsed_seconds=elapsed, interval_seconds=interval,
                             resources={'host_cpu_busy_pct': busy}, runs={}))
        log.write_text(''.join(json.dumps(row) + '\n' for row in rows) + '{"type":')
        report = monitor.render_report(log)
        self.assertIn('| host_cpu_busy_pct | 50.00 | 20.00 | 60.00 |', report)

    @unittest.skipUnless(Path('/proc/stat').exists(), 'Linux only')
    def test_live_duration_and_no_overwrite(self):
        log = self.root / 'performance.jsonl'
        args = [sys.executable, str(SCRIPT), 'watch', str(self.root), '--interval', '0.03',
                '--duration', '0.08', '--output', str(log)]
        result = subprocess.run(args, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = [json.loads(line) for line in log.read_text().splitlines()]
        self.assertGreaterEqual(sum(row['type'] == 'sample' for row in rows), 2)
        self.assertEqual(rows[-1]['reason'], 'duration reached')
        self.assertTrue(log.with_suffix('.md').exists())
        before = log.read_bytes()
        self.assertNotEqual(subprocess.run(args, capture_output=True, timeout=5).returncode, 0)
        self.assertEqual(log.read_bytes(), before)
        log.with_suffix('.md').unlink()
        self.assertNotEqual(subprocess.run(args, capture_output=True, timeout=5).returncode, 0)
        self.assertEqual(log.read_bytes(), before)

    @unittest.skipUnless(Path('/proc/stat').exists(), 'Linux only')
    def test_rejects_log_report_path_collision(self):
        path = self.root / 'performance.md'
        result = subprocess.run([sys.executable, str(SCRIPT), 'watch', str(self.root),
                                 '--duration', '0.01', '--output', str(path)],
                                capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(path.exists())

    @unittest.skipUnless(Path('/proc/stat').exists(), 'Linux only')
    def test_signal_writes_report_without_killing_watched_process(self):
        sleeper = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])
        log = self.root / 'signal.jsonl'
        process = subprocess.Popen([sys.executable, str(SCRIPT), 'watch', str(self.root),
                                    '--pid', str(sleeper.pid), '--output', str(log)],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 5
            while not log.exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(log.exists())
            process.send_signal(signal.SIGTERM)
            _, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 0, stderr)
            self.assertIsNone(sleeper.poll())
            self.assertTrue(log.with_suffix('.md').exists())
        finally:
            if process.poll() is None:
                process.kill()
            process.communicate()
            sleeper.terminate()
            sleeper.wait(timeout=5)

    @unittest.skipUnless(Path('/proc/stat').exists(), 'Linux only')
    def test_auto_stop_on_watched_process_exit(self):
        sleeper = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(0.4)'])
        try:
            result = subprocess.run([sys.executable, str(SCRIPT), 'watch', str(self.root),
                                     '--pid', str(sleeper.pid), '--interval', '0.03'],
                                    capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            log = next(self.root.glob('*.jsonl'))
            self.assertEqual(json.loads(log.read_text().splitlines()[-1])['reason'],
                             'watched process exited')
        finally:
            if sleeper.poll() is None:
                sleeper.terminate()
            sleeper.wait(timeout=5)


if __name__ == '__main__':
    unittest.main()
