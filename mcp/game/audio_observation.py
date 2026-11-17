"""Bounded live audio excerpts from an owned session's captured Master mix."""
from __future__ import annotations

import array
import base64
import io
import json
import math
import sys
import wave
from pathlib import Path


def read_excerpt(directory: Path, cursor: int, max_seconds: float = 3.0):
    """Return the next available stereo PCM excerpt, with explicit gaps.

    The original float recording remains the source for loudness measurement;
    the WAV is a 16-bit listening preview. Reading never changes the recording.
    """
    try:
        state = json.loads((directory / 'audio.json').read_text(encoding='utf-8-sig'))
        if not isinstance(state, dict):
            raise ValueError('audio metadata is not an object')
        rate = state.get('sample_rate')
        if isinstance(rate, bool) or not isinstance(rate, int) or not 8000 <= rate <= 192000:
            raise ValueError('audio sample rate not yet available')
        pcm = directory / 'mix.f32le'
        size = pcm.stat().st_size
        end = size - size % 8
        cursor = min(max(cursor - cursor % 8, 0), end)
        limit = int(rate * max_seconds) * 8
        skipped = max(0, end - cursor - limit)
        skipped -= skipped % 8
        start = cursor + skipped
        with pcm.open('rb') as stream:
            stream.seek(start)
            raw = stream.read(end - start)
        raw = raw[:len(raw) - len(raw) % 8]
        if not raw:
            return {'available': False, 'reason': 'No new captured audio frames are available.', 'skipped_frames': skipped // 8}, cursor, None
        values = array.array('f')
        values.frombytes(raw)
        if sys.byteorder != 'little': values.byteswap()
        output = array.array('h', (round(max(-1.0, min(1.0, value)) * 32767) if math.isfinite(value) else 0 for value in values))
        if sys.byteorder != 'little': output.byteswap()
        buffer = io.BytesIO()
        with wave.open(buffer, 'wb') as wav:
            wav.setnchannels(2); wav.setsampwidth(2); wav.setframerate(rate); wav.writeframes(output.tobytes())
        next_cursor = start + len(raw)
        return {'available': True, 'sample_rate': rate, 'channels': 2, 'start_frame': start // 8,
                'end_frame': next_cursor // 8, 'skipped_frames': skipped // 8,
                'source': 'live Master mix; 16-bit listening preview'}, next_cursor, base64.b64encode(buffer.getvalue()).decode('ascii')
    except (OSError, ValueError, TypeError, json.JSONDecodeError) as error:
        return {'available': False, 'reason': str(error), 'skipped_frames': 0}, cursor, None
