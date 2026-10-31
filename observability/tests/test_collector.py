import importlib.util
from pathlib import Path
import socket
import struct
import threading
import unittest

path = Path(__file__).resolve().parents[1] / 'collector' / 'collector.py'
spec = importlib.util.spec_from_file_location('collector', path)
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)

class CollectorTests(unittest.TestCase):
    def test_long_poll_and_assets_do_not_enter_latency_slo(self):
        for uri in ['/json/events', '/api/v1/events', '/static/app.js', '/user_uploads/x']:
            self.assertIsNone(collector.route_for(uri))
        self.assertEqual(collector.route_for('/api/v1/server_settings'), 'api')
        self.assertEqual(collector.route_for('/login/'), 'web')

    def test_fragmented_memcached_response(self):
        left, right = socket.socketpair()
        body = b'bytes123'
        packet = struct.pack('>BBHBBHIIQ', 0x81, 0x10, 5, 0, 0, 0, len(body), 0, 0) + body
        def send():
            with right:
                for byte in packet:
                    right.sendall(bytes([byte]))
        worker = threading.Thread(target=send)
        worker.start()
        with left:
            self.assertEqual(collector.mem_response(left), (b'bytes', b'123'))
        worker.join()

    def test_memcached_authentication_error_is_not_success(self):
        left, right = socket.socketpair()
        with left, right:
            right.sendall(struct.pack('>BBHBBHIIQ', 0x81, 0x21, 0, 0, 0, 0x20, 0, 0, 0))
            with self.assertRaises(ConnectionError):
                collector.mem_response(left)

if __name__ == '__main__':
    unittest.main()
