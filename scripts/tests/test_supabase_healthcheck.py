import contextlib
import http.client
import io
import os
from pathlib import Path
import socket
import sys
import unittest
from unittest.mock import MagicMock, patch
import urllib.error

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import supabase_healthcheck as health


class HealthTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {
            "SUPABASE_URL": "https://example.supabase.co/",
            "SUPABASE_ANON_KEY": "sb_publishable_test",
        }, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)
        self.sleep = patch.object(health.time, "sleep").start()
        self.addCleanup(patch.stopall)
        self.output = io.StringIO()
        self.capture = contextlib.redirect_stdout(self.output)
        self.capture.__enter__()
        self.addCleanup(self.capture.__exit__, None, None, None)

    def test_empty_and_populated_tables(self):
        for body in (b"[]", b'[{"idx":1}]', b'[{"id":"a"}]'):
            with self.subTest(body=body), patch.object(health, "fetch", return_value=(200, body)) as fetch:
                health.check_database()
                url, headers = fetch.call_args.args
                self.assertEqual(url, "https://example.supabase.co/rest/v1/quotes?select=*&limit=1")
                self.assertNotIn("Authorization", headers)
                self.assertEqual(headers["apikey"], "sb_publishable_test")

    def test_legacy_key_fallback_and_priority(self):
        os.environ.pop("SUPABASE_ANON_KEY")
        os.environ["SUPABASE_KEY"] = "eyJ.legacy.jwt"
        with patch.object(health, "fetch", return_value=(200, b"[]")) as fetch:
            health.check_database()
            self.assertEqual(fetch.call_args.args[1]["Authorization"], "Bearer eyJ.legacy.jwt")
            os.environ["SUPABASE_ANON_KEY"] = "sb_publishable_new"
            health.check_database()
            self.assertEqual(fetch.call_args.args[1]["apikey"], "sb_publishable_new")

    def test_invalid_config_never_sends_request(self):
        for url, key in (("", "test"), ("http://example.supabase.co", "test"),
                         ("https://example.supabase.co.evil.com", "test"),
                         ("https://example.supabase.co", ""),
                         ("https://example.supabase.co", "key\nInjected: bad"),
                         ("https://example.supabase.co", "잘못된키")):
            with self.subTest(url=url), patch.dict(os.environ, SUPABASE_URL=url, SUPABASE_ANON_KEY=key), patch.object(health, "fetch") as fetch:
                with self.assertRaises(health.ProbeError):
                    health.check_database()
                fetch.assert_not_called()

    def test_http_success_is_not_enough(self):
        for status, body in ((204, b""), (200, b"<html>Paused</html>"),
                             (200, b'{}'), (200, b'[1]'), (200, b'[{},{}]')):
            with self.subTest(status=status, body=body), patch.object(health, "fetch", return_value=(status, body)):
                with self.assertRaises(health.ProbeError):
                    health.check_database()

    def test_transient_error_recovers(self):
        with patch.object(health, "fetch", side_effect=[health.ProbeError("temporary", True), (200, b"[]")]) as fetch:
            health.check_database()
            self.assertEqual(fetch.call_count, 2)
            self.sleep.assert_called_once_with(10)

    def test_retries_are_bounded(self):
        with patch.object(health, "fetch", side_effect=health.ProbeError("down", True)) as fetch:
            with self.assertRaises(health.ProbeError):
                health.check_database()
            self.assertEqual(fetch.call_count, 4)
            self.assertEqual(self.sleep.call_count, 3)

    def test_permanent_failure_is_not_retried(self):
        with patch.object(health, "fetch", side_effect=health.ProbeError("bad key")) as fetch:
            with self.assertRaises(health.ProbeError):
                health.check_database()
            fetch.assert_called_once()
            self.sleep.assert_not_called()

    def test_http_errors_are_classified_without_body_or_url(self):
        for status in (301, 400, 401, 403, 404, 429, 500, 503):
            error = urllib.error.HTTPError("https://secret.example", status, "secret-key", {}, io.BytesIO(b"private data"))
            opener = MagicMock()
            opener.open.side_effect = error
            with self.subTest(status=status), patch.object(health.urllib.request, "build_opener", return_value=opener):
                with self.assertRaises(health.ProbeError) as raised:
                    health.fetch("https://example.supabase.co", {})
                self.assertEqual(raised.exception.retryable, status == 429 or status >= 500)
                self.assertNotIn("secret", str(raised.exception))
                self.assertNotIn("private data", str(raised.exception))

    def test_dns_error_has_resume_instructions(self):
        opener = MagicMock()
        opener.open.side_effect = urllib.error.URLError(socket.gaierror("secret hostname"))
        with patch.object(health.urllib.request, "build_opener", return_value=opener):
            with self.assertRaises(health.ProbeError) as raised:
                health.fetch("https://example.supabase.co", {})
            self.assertTrue(raised.exception.retryable)
            self.assertIn("Resume", str(raised.exception))
            self.assertNotIn("secret hostname", str(raised.exception))

    def test_redirects_are_refused(self):
        self.assertIsNone(health.NoRedirect().redirect_request(None, None, 302, "", {}, "https://elsewhere.example"))

    def test_broken_response_and_timeout_are_retryable(self):
        for error in (http.client.IncompleteRead(b"private data"), TimeoutError()):
            opener = MagicMock()
            opener.open.side_effect = error
            with self.subTest(error=type(error).__name__), patch.object(health.urllib.request, "build_opener", return_value=opener):
                with self.assertRaises(health.ProbeError) as raised:
                    health.fetch("https://example.supabase.co", {})
                self.assertTrue(raised.exception.retryable)
                self.assertNotIn("private data", str(raised.exception))

    def test_response_size_limit(self):
        opener = MagicMock()
        opener.open.return_value.__enter__.return_value.read.return_value = b"12345"
        with patch.object(health.urllib.request, "build_opener", return_value=opener):
            with self.assertRaisesRegex(health.ProbeError, "size limit"):
                health.fetch("https://example.supabase.co", {}, limit=4)

    def enable_monitor(self):
        url = "https://hc-ping.com/00000000-0000-0000-0000-000000000000"
        os.environ["KEEPALIVE_HEARTBEAT_URL"] = url
        return url

    def test_monitor_only_receives_status_without_credentials(self):
        url = self.enable_monitor()
        with patch.object(health, "fetch", return_value=(200, b"OK")) as fetch:
            health.report_heartbeat(True)
            fetch.assert_called_with(url, {}, limit=1024)
            health.report_heartbeat(False)
            fetch.assert_called_with(url + "/fail", {}, limit=1024)

    def test_monitor_rejects_200_error_body(self):
        self.enable_monitor()
        with patch.object(health, "fetch", return_value=(200, b"OK (not found)")):
            with self.assertRaises(health.ProbeError):
                health.report_heartbeat(True)

    def test_missing_monitor_is_visible(self):
        with patch.object(health, "fetch") as fetch:
            health.report_heartbeat(True)
            fetch.assert_not_called()
            self.assertIn("::warning::", self.output.getvalue())
            self.assertIn("NOT configured", self.output.getvalue())

    def test_invalid_monitor_never_sends_request(self):
        os.environ["KEEPALIVE_HEARTBEAT_URL"] = "https://hc-ping.com/invalid"
        with patch.object(health, "fetch") as fetch:
            with self.assertRaises(health.ProbeError):
                health.report_heartbeat(True)
            fetch.assert_not_called()

    def test_report_requires_known_result(self):
        with patch.object(sys, "argv", ["probe", "report"]), patch.object(health, "report_heartbeat") as report:
            self.assertEqual(health.main(), 1)
            report.assert_not_called()

    def test_report_never_marks_failed_or_cancelled_runs_healthy(self):
        for result in ("success", "failure", "cancelled", "skipped"):
            os.environ["KEEPALIVE_RESULT"] = result
            with self.subTest(result=result), patch.object(sys, "argv", ["probe", "report"]), patch.object(health, "report_heartbeat") as report:
                self.assertEqual(health.main(), 0)
                report.assert_called_once_with(result == "success")

    def test_standalone_failure_stays_failed_after_reporting(self):
        with patch.object(sys, "argv", ["probe", "run"]), patch.object(health, "check_database", side_effect=health.ProbeError("down")), patch.object(health, "report_heartbeat") as report:
            self.assertEqual(health.main(), 1)
            report.assert_called_once_with(False)

    def test_monitor_outage_fails_standalone_run(self):
        with patch.object(sys, "argv", ["probe", "run"]), patch.object(health, "check_database", return_value="DB healthy"), patch.object(health, "report_heartbeat", side_effect=health.ProbeError("monitor down")):
            self.assertEqual(health.main(), 1)


if __name__ == "__main__":
    unittest.main()
