"""Validate the input MCP routes observation calls to the owned session."""
import asyncio
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

    def test_assessed_gameplay_response_hides_internal_story_state(self):
        endpoint = SimpleNamespace(assessment_plan={"test_id": "blind"})
        result = {"session_id": "owned", "image_base64": "pixels", "audio_base64": "audio",
                  "source_identity": {"process_id": 7}, "server_identity": {"server_pid": 8},
                  "controls": [{"text": "hidden text"}], "phase": "secret", "navigation": {"position": [1, 2]},
                  "room": "secret room", "controller_phase": "free"}
        with patch.dict(runtime.SESSIONS, {"owned": endpoint}):
            visible = server.observer_result("input", "observe", result)
        self.assertEqual(set(visible), {"session_id", "image_base64", "audio_base64", "source_identity", "server_identity"})
        self.assertEqual(visible["image_base64"], "pixels")
        with patch.dict(runtime.SESSIONS, {"owned": SimpleNamespace(assessment_plan=None)}):
            self.assertIs(server.observer_result("input", "observe", result), result)

    def test_unknown_session_is_rejected(self):
        with patch.dict(runtime.SESSIONS, {}, clear=True), self.assertRaisesRegex(ValueError, 'Unknown session'):
            runtime.execute('event_script', {'session_id': 'missing', 'text': 'A door opens.'})


class CancelledLaunchTests(unittest.IsolatedAsyncioTestCase):
    async def test_cancelled_launch_closes_session_once_launch_returns(self):
        started, release, closed = threading.Event(), threading.Event(), threading.Event()
        def launch(service, name, arguments):
            started.set()
            release.wait(5)
            return {"session_id": "owned"}
        def close(name, arguments):
            self.assertEqual((name, arguments), ("close", {"session_id": "owned"}))
            closed.set()
        with patch.object(server, "execute", side_effect=launch), patch.object(runtime, "execute", side_effect=close):
            task = asyncio.create_task(server.execute_owned("input", "on", {}))
            self.assertTrue(await asyncio.to_thread(started.wait, 2))
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await task
            release.set()
            self.assertTrue(await asyncio.to_thread(closed.wait, 3))


if __name__ == '__main__':
    unittest.main()
