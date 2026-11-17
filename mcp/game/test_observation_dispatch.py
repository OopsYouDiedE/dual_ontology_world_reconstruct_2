"""Validate the input MCP routes observation calls to the owned session."""
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import runtime
import server


class ObservationDispatchTests(unittest.TestCase):
    def test_observation_tools_are_discoverable(self):
        names = {tool.name for tool in server.TOOLS['input']}
        self.assertTrue({'event_script', 'character_script', 'charactor_script', 'review_visible_text'} <= names)

    def test_each_note_uses_the_existing_owned_session(self):
        endpoint = SimpleNamespace(lock=threading.Lock())
        with patch.dict(runtime.SESSIONS, {'owned': endpoint}), \
             patch('blind_observation.append_observation', return_value={'recorded': True}) as append:
            for name in ('event_script', 'character_script', 'charactor_script'):
                self.assertTrue(runtime.execute(name, {'session_id': 'owned', 'text': 'A door opens.'})['recorded'])
                append.assert_called_with(endpoint, 'owned', name, 'A door opens.', runtime.ROOT)

    def test_text_review_uses_the_existing_owned_session(self):
        endpoint = SimpleNamespace(lock=threading.Lock())
        arguments = {'session_id': 'owned', 'path': '/root/prompt', 'text': 'Open',
                     'category': 'prompt', 'english_verified': True}
        with patch.dict(runtime.SESSIONS, {'owned': endpoint}), \
             patch('text_observation.append_text_observation', return_value={'recorded': True}) as append:
            self.assertTrue(runtime.execute('review_visible_text', arguments)['recorded'])
            append.assert_called_once_with(endpoint, 'owned', '/root/prompt', 'Open', 'prompt', True, runtime.ROOT)

    def test_audio_preview_returns_session_bound_scheduling_cues(self):
        endpoint = SimpleNamespace(lock=threading.Lock(), backend="godot", mode="godot_manual",
                                   metrics_directory=runtime.ROOT, audio_observation_cursor=0, audio_cue_cursor=0,
                                   request=lambda operation, timeout: {"scene": "example"})
        with patch.dict(runtime.SESSIONS, {"owned": endpoint}), \
             patch("audio_observation.read_excerpt", return_value=({"available": True}, 8, "wav")), \
             patch("audio_cue_observation.read_cues", return_value=({"available": True, "events": []}, 12)):
            result = runtime.execute("observe", {"session_id": "owned", "capture_audio": True})
        self.assertEqual((endpoint.audio_observation_cursor, endpoint.audio_cue_cursor), (8, 12))
        self.assertEqual(result["audio_base64"], "wav")
        self.assertTrue(result["audio_cues"]["available"])

    def test_unknown_session_is_rejected(self):
        with patch.dict(runtime.SESSIONS, {}, clear=True), self.assertRaisesRegex(ValueError, 'Unknown session'):
            runtime.execute('event_script', {'session_id': 'missing', 'text': 'A door opens.'})


if __name__ == '__main__':
    unittest.main()
