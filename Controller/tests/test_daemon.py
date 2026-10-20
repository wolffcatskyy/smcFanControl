# SPDX-License-Identifier: GPL-2.0-or-later
import concurrent.futures
import json
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ControllerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix='ce-build-', dir='/tmp')
        cls.binary = Path(cls.build.name) / 'daemon'
        subprocess.run(['cc', '-std=c11', '-D_GNU_SOURCE', '-DCE_TESTING', '-Wall', '-Wextra', '-Werror', '-O2',
                        *[str(ROOT / f) for f in ('daemon.c', 'backend_fake.c', 'policy.c', 'decode.c')], '-lm', '-o', str(cls.binary)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ce-', dir='/tmp')
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.socket = self.path / 's'
        self.config = self.path / 'config'
        self.lock = self.path / 'lock'
        self.process = None
        self.start()
        self.addCleanup(self.stop)

    def start(self):
        self.process = subprocess.Popen([str(self.binary), str(self.socket), str(self.config), str(self.lock)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        for _ in range(100):
            try:
                if self.status()['sequence'] > 0:
                    return
            except (OSError, json.JSONDecodeError):
                pass
            if self.process.poll() is not None:
                self.fail(self.process.stderr.read().decode())
            time.sleep(.01)
        self.fail('daemon failed to become ready')

    def stop(self):
        if self.process:
            if self.process.poll() is None:
                self.process.terminate()
                self.process.wait(timeout=3)
            self.process.stderr.close()
            self.process = None

    def request(self, command):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(2)
            s.connect(str(self.socket))
            s.sendall(command.encode())
            s.shutdown(socket.SHUT_WR)
            data = bytearray()
            while True:
                block = s.recv(8192)
                if not block:
                    break
                data.extend(block)
            return data.decode()

    def status(self):
        return json.loads(self.request('STATUS'))

    def test_initial_start_does_not_take_over_fans(self):
        self.assertEqual([f['mode'] for f in self.status()['fans']], ['unmanaged', 'unmanaged'])

    def test_policy_applied_and_persisted_across_restart(self):
        self.assertTrue(self.request('SET 0 manual 3000').startswith('OK'))
        self.stop()
        self.start()
        self.assertEqual(self.status()['fans'][0]['target'], 3000)
        self.assertEqual(self.status()['fans'][0]['mode'], 'manual')

    def test_multi_client_reads_do_not_change_policy(self):
        self.request('SET 0 maximum')
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            snapshots = list(pool.map(lambda _: self.status(), range(32)))
        self.assertTrue(all(s['fans'][0]['mode'] == 'maximum' for s in snapshots))

    def test_invalid_requests_leave_policy_unchanged(self):
        self.request('SET 0 manual 3000')
        for command in ('SET 99 auto', 'SET 0 manual 0', 'SET 0 manual 7000', 'SET 0 curve TC0P nan 80', 'SET 0 curve NOPE 50 80', 'WRITE FS! 0000', 'SET 0 auto\nSET 1 auto'):
            with self.subTest(command=command):
                self.assertTrue(self.request(command).startswith('ERR'))
                self.assertEqual(self.status()['fans'][0]['mode'], 'manual')

    def test_second_daemon_cannot_replace_socket(self):
        result = subprocess.run([str(self.binary), str(self.socket), str(self.config), str(self.lock)], capture_output=True, timeout=2)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.status()['fans']), 2)

    def test_global_force_bits_preserve_other_fans(self):
        self.request('SET 0 maximum')
        self.request('SET 1 maximum')
        self.assertTrue(self.request('READ 46532120').rstrip().endswith('0003'))
        self.request('SET 0 auto')
        self.assertTrue(self.request('READ 46532120').rstrip().endswith('0002'))

    def test_minimum_baseline_survives_restart(self):
        self.request('SET 0 minimum 2000')
        self.stop()
        self.start()
        self.assertEqual(self.status()['fans'][0]['min'], 1000)
        self.request('SET 0 auto')
        self.assertTrue(self.request('READ 46304d6e').rstrip().endswith('0fa0'))

    def test_curve_interpolation(self):
        self.assertTrue(self.request('SET 0 curve TC0P 50 80').startswith('OK'))
        self.assertEqual(self.status()['fans'][0]['target'], 3500)

    def test_sensor_read_and_signed_type_protocol(self):
        self.assertEqual(self.request('READ 54433050'), 'OK sp78 2 4100\n')
        self.assertIn('TC0P 65.00', self.request('SENSORS'))

    def test_nonprivate_config_refused(self):
        self.stop()
        self.config.chmod(0o666)
        result = subprocess.run([str(self.binary), str(self.socket), str(self.config), str(self.lock)], capture_output=True, timeout=2)
        self.assertNotEqual(result.returncode, 0)

    def test_config_symlink_refused(self):
        self.stop()
        self.config.rename(self.path / 'real')
        self.config.symlink_to(self.path / 'real')
        result = subprocess.run([str(self.binary), str(self.socket), str(self.config), str(self.lock)], capture_output=True, timeout=2)
        self.assertNotEqual(result.returncode, 0)

    def test_incomplete_client_cannot_stall_control_loop(self):
        before = self.status()['sequence']
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.connect(str(self.socket))
            s.sendall(b'SET')
            time.sleep(2.2)
        self.assertGreater(self.status()['sequence'], before)
