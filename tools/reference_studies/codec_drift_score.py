"""Original score for Codec Drift: all voices are synthesized, no input samples."""

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

RATE = 48000
STEP = 1 / 6  # 180 bpm, eighth notes
TAU = 2 * np.pi


def synthesize(path, duration, seed):
    rng = np.random.default_rng(seed)
    total = round(duration * RATE)
    mix = np.zeros((total, 2))
    space = np.zeros_like(mix)

    def clock(length):
        return np.arange(round(length * RATE)) / RATE

    def insert(start, wave, level, pan=0, send=0):
        index = round(RATE * start)
        count = min(len(wave), total - index)
        if count <= 0:
            return
        panned = level * wave[:count, None] * np.sqrt([(1 - pan) / 2, (1 + pan) / 2])
        mix[index:index + count] += panned
        if send:
            space[index:index + count] += send * panned

    def noise(t, low, high):
        return sosfilt(butter(2, (low, high), fs=RATE, btype='bandpass', output='sos'),
                       rng.standard_normal(len(t)))

    def kick(start, level):
        t = clock(.32)
        phase = TAU * (48 * t + 94 * .029 * (1 - np.exp(-t / .029)))
        body = np.sin(phase) * np.exp(-t / .088) + .11 * noise(t, 1400, 4300) * np.exp(-t / .007)
        insert(start, body * np.minimum(1, t * 1000), level)

    def bass(start, length, frequency, level, sweep=0):
        t = clock(length)
        phase = TAU * (frequency * t + sweep * t ** 2 / (2 * length) + .72 * np.sin(t * 7))
        voice = np.tanh(1.55 * np.sin(phase) + .25 * np.sin(2 * phase + .4))
        env = np.clip(t / .014, 0, 1) * np.clip((length - t) / .055, 0, 1)
        insert(start, voice * env, level)

    def pulse(start, length, hz, level, pan):
        t = clock(length)
        phase = TAU * hz * t
        drift = .5 * np.sin(TAU * (3.5 * t + .09 * np.sin(9 * t)))
        sound = np.sin(phase + drift + 1.6 * np.exp(-t * 7) * np.sin(phase * 1.502))
        sound += .35 * np.sin(phase * 2.012 - drift) + .18 * np.sin(phase * 4.06)
        env = np.minimum(1, t * 90) * np.exp(-t * 6) * np.clip((length - t) * 32, 0, 1)
        insert(start, sound * env, level, pan, .55)

    # Two dense sections. The middle drops the kick/bass and exposes the pitched tail.
    sequence = (73.42, 82.41, 65.41, 69.30, 73.42, 87.31, 65.41, 77.78)
    for origin, end in ((.97, 21.29), (29.46, 38.75)):
        for bar, start in enumerate(np.arange(origin, end, 8 * STEP)):
            base = sequence[bar % len(sequence)]
            for hit in (0, 2, 3.5, 5, 6.5):
                when = start + hit * STEP
                if when < end - .04:
                    kick(when, .59 if hit == 0 else .35)
            for pos, pitch, count in ((0, base, 2), (2.5, base, 1.65), (4.5, 65.41, 1.4),
                                      (6, base, 1.8)):
                when = start + pos * STEP
                if when < end - .05:
                    bass(when, min(end - when, count * STEP), pitch, .43, -3)
            for pos in range(8):
                when = start + pos * STEP + (.011 if pos % 2 else 0)
                if when >= end:
                    break
                t = clock(.072 if pos % 2 else .041)
                hat = noise(t, 3900, 11900) * np.exp(-t * 57)
                insert(when, hat, .155 if pos % 2 else .085, .33 * (-1) ** pos, .12)
                if pos in (2, 6):
                    t = clock(.16)
                    snare = noise(t, 790, 6900) * np.exp(-t * 28)
                    snare += .46 * np.sin(TAU * (170 * t + 5 * (1 - np.exp(-18 * t)))) * np.exp(-t * 44)
                    insert(when + .011, snare, .29, -.12, .19)
                if pos in (0, 1, 3, 4, 7):
                    notes = (293.66, 220, 349.23, 261.63, 196, 277.18, 233.08, 155.56)
                    pulse(when, min(.38, end - when + .02), notes[(bar + pos * 3) % 8],
                          .097, .39 * np.sin(bar + pos * 1.6))

    bass(0, .94, 78, .23, -24)
    pulse(0, .88, 369.99, .20, .12)
    for i in range(15):
        hz = (155.56, 311.13, 392, 261.63, 466.16, 349.23, 523.25)[i % 7]
        pulse(21.29 + i * .497, 1.35, hz, .23 if i < 5 else .16, .60 * np.sin(i * 2.1))
    t = clock(8.17)
    pad = sum(.29 * np.sin(TAU * (h * t + .33 * np.sin(2 * t + j)))
              for j, h in enumerate((116.54, 155.56, 233.08, 311.13)))
    insert(21.28, pad * np.clip(t * 2.1, 0, 1) * np.clip((8.17 - t) * 1.6, 0, 1), .12, .05, .76)

    for start, length, level in ((.08, .45, .15), (8.14, .31, .20), (13.31, .35, .25),
                                 (20.44, .82, .36), (28.91, .57, .24), (35.28, .8, .29),
                                 (38.72, 1.35, .27), (45.07, .25, .26)):
        t = clock(length)
        grit = noise(t, 140, 6700) * (.34 + .66 * (np.sin(t * (150 - 68 * t)) > .25))
        insert(start, grit * np.sin(np.pi * t / length) ** .7, level, -.22, .16)

    for i, when in enumerate((39.62, 41.11, 42.27, 43.53, 44.55)):
        bass(when, .64, 61 + i * 8, .48, -16 - i * 3)
        pulse(when, .31, 475 + i * 3, .17, .18)
        kick(when, .40)
    bass(44.90, .43, 48, .43, -22)

    # Filtered ping-pong taps; original dry signals stay centered enough for phone speakers.
    for j, delay in enumerate((.091, .157, .247, .337, .519, .727)):
        n = int(delay * RATE)
        echo = space[:-n, ::-1] if j % 2 == 0 else space[:-n]
        mix[n:] += .47 * .75 ** j * echo
    mix = np.tanh(1.36 * mix)
    mix *= min(.94 / max(.01, float(np.max(np.abs(mix)))), 1.45)
    mix *= .83
    mix[-int(.24 * RATE):] *= np.linspace(1, 0, int(.24 * RATE))[:, None]
    wavfile.write(path, RATE, (mix * 32767).astype(np.int16))
