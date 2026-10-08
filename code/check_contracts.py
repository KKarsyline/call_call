"""Run with Python 3.9+: python3 code/check_contracts.py"""
import json
import unittest

from silence_contract import validate_wait_response, voice_silence_event_input, _call_wait_event


class Contracts(unittest.TestCase):
    def payload(self, **values):
        return dict(spoken_text="", delivery_plan=[], call_action="wait", **values)

    def test_wait_default_and_bounds(self):
        self.assertEqual(validate_wait_response(self.payload(), supports_silence_wait=True)["recheck_after_seconds"], 20)
        for seconds in (10, 20, 300):
            with self.subTest(seconds=seconds):
                self.assertEqual(validate_wait_response(self.payload(recheck_after_seconds=seconds), supports_silence_wait=True)["recheck_after_seconds"], seconds)

    def test_reject_invalid_wait_seconds(self):
        for seconds in (True, False, 9, 301, -1, 20.0, "20", None, float("nan")):
            with self.subTest(seconds=seconds), self.assertRaises(ValueError):
                validate_wait_response(self.payload(recheck_after_seconds=seconds), supports_silence_wait=True)

    def test_wait_capability_and_empty_speech(self):
        with self.assertRaises(ValueError):
            validate_wait_response(self.payload(), supports_silence_wait=False)
        for field, value in (("spoken_text", "嗯"), ("spoken_text", " "), ("delivery_plan", [{"text":"嗯"}])):
            payload = self.payload()
            payload[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                validate_wait_response(payload, supports_silence_wait=True)

    def test_observation_uses_actual_seconds_and_start_mode(self):
        first = voice_silence_event_input(seconds=17, after_playback=False)
        later = voice_silence_event_input(seconds=55, after_playback=True)
        self.assertIn("通话接通后，已连续 17 秒", first)
        self.assertNotIn("上一段语音", first)
        self.assertIn("上一段语音播放完毕后，已连续 55 秒", later)
        self.assertIn("也可以主动开口", later)

    def test_wait_sse_preserves_identity(self):
        payload = _call_wait_event("call-example", {"id":"turn-example", "turn_epoch":4, "playback_epoch":3, "server_seq":9, "metrics":{"recheck_after_seconds":60}}).decode()
        event, data = payload.strip().split("\n")
        self.assertEqual(event, "event: call.wait")
        obj = json.loads(data.removeprefix("data: "))
        self.assertEqual((obj["generation_id"], obj["turn_epoch"], obj["playback_epoch"]), ("turn-example",4,3))
        self.assertEqual(obj["recheck_after_seconds"],60)
        self.assertNotIn("spoken_text",obj)


if __name__ == "__main__":
    unittest.main(verbosity=2)
