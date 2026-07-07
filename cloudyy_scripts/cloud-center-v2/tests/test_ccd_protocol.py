import json
import unittest

from lib.ccd import protocol


class TestHandleLine(unittest.TestCase):
    def test_ping_returns_pong_and_echoes_id(self):
        reply = protocol.handle_line('{"id": 7, "method": "ping"}')
        self.assertEqual(reply, {"id": 7, "ok": True, "result": "pong"})

    def test_blank_line_is_ignored(self):
        self.assertIsNone(protocol.handle_line("   \n"))

    def test_malformed_json_returns_error_with_null_id(self):
        reply = protocol.handle_line("{not json")
        self.assertFalse(reply["ok"])
        self.assertIsNone(reply["id"])

    def test_non_object_request_returns_error(self):
        reply = protocol.handle_line("[1, 2, 3]")
        self.assertFalse(reply["ok"])

    def test_unknown_method_names_the_method(self):
        reply = protocol.handle_line('{"id": 1, "method": "no_such_thing"}')
        self.assertFalse(reply["ok"])
        self.assertIn("no_such_thing", reply["error"])

    def test_raising_handler_becomes_error_response(self):
        def boom(params):
            raise RuntimeError("kaboom")

        protocol.register("boom", boom)
        try:
            reply = protocol.handle_line('{"id": 2, "method": "boom"}')
        finally:
            del protocol.METHODS["boom"]
        self.assertEqual(reply["id"], 2)
        self.assertFalse(reply["ok"])
        self.assertIn("kaboom", reply["error"])

    def test_params_are_passed_to_handler(self):
        seen = {}

        def echo(params):
            seen.update(params)
            return params

        protocol.register("echo", echo)
        try:
            reply = protocol.handle_line(
                '{"id": 3, "method": "echo", "params": {"a": 1}}'
            )
        finally:
            del protocol.METHODS["echo"]
        self.assertEqual(seen, {"a": 1})
        self.assertEqual(reply["result"], {"a": 1})


class TestEventOutput(unittest.TestCase):
    def test_send_event_writes_one_json_line(self):
        lines = []
        original = protocol.write_line
        protocol.write_line = lambda payload: lines.append(json.dumps(payload))
        try:
            protocol.send_event({"event": "state", "key": "hypr/wifi", "value": True})
        finally:
            protocol.write_line = original
        self.assertEqual(len(lines), 1)
        self.assertEqual(json.loads(lines[0])["event"], "state")


if __name__ == "__main__":
    unittest.main()
