"""No Morning Follows: original SATB score and a sample-free mockup."""
from pathlib import Path
from xml.etree import ElementTree as ET
import argparse
import math
import re
import subprocess
import tempfile
import wave

TITLE = "No Morning Follows"
TEMPO = 68
# Eighth-note units; r = rest, + = tie forward, / = simultaneous notes.
# Across the loop: organ E/B stays put, choir C recedes, and soprano E returns alone.
TRACKS = {
    "Soprano": """
r2 E4:4 G4:2 | F#4:3 C5:1 B4:4 | A4:3 G4:1 F#4:2 E4:2 | D#4:4 r4 |
r4 E4:2 G4:2 | F#4:3 C5:1 B4:4 | G4:2 A4:2 F4:4 | r2 F#4:2 G4:4 |
B4:4 A4:2 G4:2 | F#4:4 r4 | r2 E4:4 G4:2 | F#4:3 C5:1 B4:2 |
E5:4 D5:2 B4:2 | F#5:3 E5:1 C5:4 | B4:2 C5:2 D5:4 | C5:4 B4:4 |
A4:4 C5:2 B4:2 | G4:4 F#4:2 E4:2 | r2 E4:4 G4:2 | F#4:3 C5:1 B4:4 |
C5:6 B4:2 | A4:3 G4:1 F4:4 | E4:4 r4 | r6""",
    "Alto": """
r8 | r4 G4:4 | F#4:4 E4:4 | B3:6 r2 | r2 B3:2 C4:4 | D4:4 E4:4 | E4:4 C4:4 | r2 D#4:2 E4:4 |
D4:4 F4:4 | E4:4 C4:4 | r2 B3:4 C4:2 | D4:4 E4:2 |
B4:4 A4:2 F#4:2 | A4:4 G4:4 | F#4:4 A4:4 | G4:4 F#4:4 |
F4:4 E4:4 | D4:4 D#4:4 | r4 C4:4 | D4:4 E4:4 |
G4:4 E4:4 | C4:8+ | C4:8+ | C4:4 r2""",
    "Tenor": """
r6 B3:2 | A3:4+ A3:2 E3:2 | r2 E3:2 B3:4 | F#3:4 G3:4 |
E3:3 G3:1 A3:4 | D3:4 B3:4 | C4:4 A3:4 | B3:6 r2 |
G3:4 A3:4 | C4:6 r2 | E3:8+ | E3:6 |
G4:4 F#4:2 D4:2 | F#4:4 E4:4 | D4:8 | E4:4 D#4:4 |
A3:4 C4:4 | B3:4 G3:4 | r6 B3:2 | A3:4+ A3:2 E3:2 |
B3:4 A3:4 | F3:4 A3:4 | B3:8+ | B3:4 r2""",
    "Bass": """
r8 | r2 E3:6 | C3:4 A2:4 | B2:6 r2 | E3:8 | D3:8 | A2:8 | B2:4 E3:4 |
G2:4 F2:4 | E3:4 A2:4 | E3:8+ | E3:6 |
E3:4 G3:4 | D3:4 C3:4 | B2:4 G2:4 | A2:4 B2:4 |
F2:4 A2:4 | G2:4 B2:4 | r8 | r2 E3:6 | C3:4 E3:4 | F2:4 E3:4 | E3:8+ | E3:4 r2""",
    "Chamber Organ": """
E2/B2:8 | E2/A2:8 | E2/C3:8 | E2/B2:8 | E2/A2:8 | E2/B2:8 | E2/A2:8 | E2/B2:8 |
G2/D3:8 | A2/E3:8 | E2/B2:8+ | E2/B2:6+ | E2/B2:8 | D2/A2:8 | G2/D3:8 | A2/E3:8 |
F2/C3:8 | B1/F#2:8 | E2/B2:8 | E2/A2:8 | E2/C3:8 | E2/F2:8 | E2/B2:8+ | E2/B2:6""",
    "Piano": """
r8 | r6 B4:2 | r4 E4:2 F#4:2 | r6 B3:2 | r4 C4:2 E4:2 | A3:2 D4:2 B3:2 E4:2 |
A3:2 F4:2 C4:2 E4:2 | B3:2 F#4:2 E4:2 r2 | G3:2 B3:2 D4:2 F4:2 | E4:2 C4:2 E4:2 r2 |
B3:1 E4:1 G4:1 B4:1 E4:1 G4:1 D4:1 E4:1 | B3:1 F#4:1 C5:1 D4:1 E4:1 B4:1 |
E3:1 B3:1 G4:1 B4:1 E4:1 B4:1 G4:1 D5:1 | D3:1 A3:1 F#4:1 A4:1 C4:1 E4:1 G4:1 C5:1 |
G3:1 D4:1 B4:1 D5:1 G4:1 F#4:1 A4:1 D5:1 | A3:1 E4:1 C5:1 E5:1 B3:1 E4:1 F#4:1 B4:1 |
F3:1 C4:1 A4:1 C5:1 A3:1 E4:1 G4:1 B4:1 | G3:2 D4:2 B3:2 D#4:2 | r8 | r6 B4:2 |
r6 G4:2 | r4 C4:2 F4:2 | r6 E4:2 | r4 F4:2""",
    "Violoncello": """
r8 | r8 | r4 G3:4 | F#3:3 G3:1 B3:4 | r2 E3:4 A3:2 | G3:4 B3:4 | C4:4 B3:4 | B3:6 r2 |
D3:4 F3:4 | E3:4 A3:2 B3:2 | G3:6 D3:2 | E3:6 | E3:6 G3:2 | A3:4 G3:4 | B3:4 D4:4 |
C4:4 A3:4 | C4:4 E4:4 | D4:4 D#4:4 | r4 E3:4 | B3:4 A3:4 | G3:4 C4:4 | A3:4 F3:4 | F3:6 E3:2+ | E3:6""",
    "Bell": "|".join(["r8"]*11+["r6"]+["r8"]*4+["r4 E4:4"]+["r8"]*6+["r4 E4:2"]),
}
METER = (8,) * 11 + (6,) + (8,) * 11 + (6,)
PARTS = {
    "Soprano": ("G", 2, 53), "Alto": ("G", 2, 53), "Tenor": ("G", 2, 53), "Bass": ("F", 4, 53),
    "Chamber Organ": ("F", 4, 20), "Piano": ("G", 2, 1), "Violoncello": ("F", 4, 43), "Bell": ("G", 2, 15),
}
RANGES = {"Soprano": (62, 78), "Alto": (55, 71), "Tenor": (48, 67), "Bass": (40, 56)}
FORM = {0: ("I. Invocation", "Ooh, almost without vibrato", "pp"),
        4: ("II. The Answer", "Open gradually to Ah; breathe independently", "p"),
        12: ("III. Apparition", "Broaden the sound; keep the pulse", "mf"),
        18: ("IV. The Same Hour", "As at first; the organ holds", "pp"),
        22: ("", "Close to Ooh; repeat without pause", "ppp")}


def parse(track):
    bars = []
    for row in track.split("|"):
        es = []
        for word in row.split():
            if word.startswith("r"):
                es.append(((), int(word[1:]), False))
            else:
                pitch, units = word.rstrip("+").split(":")
                es.append((tuple(pitch.split("/")), int(units), word.endswith("+")))
        bars.append(es)
    return bars


SCORE = {part: parse(track) for part, track in TRACKS.items()}


def pitch_parts(pitch):
    step, accidental, octave = re.fullmatch(r"([A-G])([#b]?)([0-8])", pitch).groups()
    return step, {"": 0, "#": 1, "b": -1}[accidental], int(octave)


def midi_pitch(pitch):
    step, alter, octave = pitch_parts(pitch)
    return 12 * (octave + 1) + {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}[step] + alter


def validate():
    assert SCORE["Soprano"][:2] == SCORE["Soprano"][18:20]
    assert SCORE["Chamber Organ"][0][0][0] == SCORE["Chamber Organ"][-1][0][0]
    for part, bars in SCORE.items():
        assert len(bars) == len(METER), part
        prev_tie = ()
        for bar, (units, es) in enumerate(zip(METER, bars), 1):
            assert sum(d for _, d, _ in es) == units, (part, bar, es)
            for pitches, _, outgoing in es:
                assert not prev_tie or pitches == prev_tie, (part, bar, prev_tie, pitches)
                if part in RANGES:
                    lo, hi = RANGES[part]
                    assert all(lo <= midi_pitch(p) <= hi for p in pitches), (part, bar, pitches)
                prev_tie = pitches if outgoing else ()
        assert not prev_tie


def child(parent, tag, value=None, **attrib):
    el = ET.SubElement(parent, tag, attrib)
    if value is not None:
        el.text = str(value)
    return el


def direction(measure, tag, value=None, placement="above", **attrib):
    wrapper = child(measure, "direction", placement=placement)
    return wrapper, child(child(wrapper, "direction-type"), tag, value, **attrib)


def score(path):
    root = ET.Element("score-partwise", version="4.0")
    child(child(root, "work"), "work-title", TITLE)
    child(root, "movement-title", TITLE)
    child(child(root, "identification"), "creator", "The Sleeping Academy", type="composer")
    listing = child(root, "part-list")
    for idx, (part, (_, _, program)) in enumerate(PARTS.items(), 1):
        pid = f"P{idx}"
        sp = child(listing, "score-part", id=pid)
        child(sp, "part-name", part)
        child(child(sp, "score-instrument", id=f"{pid}-I1"), "instrument-name", part)
        instrument = child(sp, "midi-instrument", id=f"{pid}-I1")
        child(instrument, "midi-channel", idx)
        child(instrument, "midi-program", program)
    for idx, (part, (clef, line, _)) in enumerate(PARTS.items(), 1):
        track = child(root, "part", id=f"P{idx}")
        incoming = False
        for bar, length in enumerate(METER):
            m = child(track, "measure", number=str(bar+1))
            if bar == 18:
                child(m, "print", **{"new-page": "yes"})
            if bar == 0 or length != METER[bar-1]:
                a = child(m, "attributes")
                if bar == 0:
                    child(a, "divisions", 2)
                    child(child(a, "key"), "fifths", 1)
                meter = child(a, "time")
                child(meter, "beats", length // 2)
                child(meter, "beat-type", 4)
                if bar == 0:
                    c = child(a, "clef")
                    child(c, "sign", clef)
                    child(c, "line", line)
                    if part == "Tenor":
                        child(c, "clef-octave-change", -1)
            if bar == 0:
                child(child(m, "barline", location="left"), "repeat", direction="forward")
                if idx == 1:
                    wrapper, metro = direction(m, "metronome")
                    child(metro, "beat-unit", "quarter")
                    child(metro, "per-minute", TEMPO)
                    child(wrapper, "sound", tempo=str(TEMPO))
            if bar in FORM:
                label, performance, level = FORM[bar]
                if idx == 1:
                    if label:
                        direction(m, "rehearsal", label)
                    direction(m, "words", performance, **{"font-style": "italic"})
                if part in RANGES:
                    _, d = direction(m, "dynamics", placement="below")
                    child(d, level)
            for notes, units, outgoing in SCORE[part][bar]:
                for j, pitch in enumerate(notes or (None,)):
                    n = child(m, "note")
                    if j:
                        child(n, "chord")
                    if pitch:
                        pname, alter, octave = pitch_parts(pitch)
                        pitch_el = child(n, "pitch")
                        child(pitch_el, "step", pname)
                        if alter:
                            child(pitch_el, "alter", alter)
                        child(pitch_el, "octave", octave)
                    else:
                        child(n, "rest", **({"measure": "yes"} if units == length else {}))
                    child(n, "duration", units)
                    ties = tuple(k for k, active in (("stop", incoming), ("start", outgoing)) if active)
                    for tie in ties:
                        child(n, "tie", type=tie)
                    if pitch or units != length:
                        child(n, "type", {1:"eighth", 2:"quarter", 3:"quarter", 4:"half", 6:"half", 8:"whole"}[units])
                        if units in (3, 6):
                            child(n, "dot")
                    if ties:
                        marks = child(n, "notations")
                        for tie in ties:
                            child(marks, "tied", type=tie)
                incoming = outgoing
            if bar == len(METER) - 1:
                child(child(m, "barline", location="right"), "repeat", direction="backward")
    ET.indent(root)
    path.write_text('<?xml version="1.0" encoding="UTF-8"?>\n'
                    '<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" '
                    '"http://www.musicxml.org/dtds/partwise.dtd">\n'
                    + ET.tostring(root, encoding="unicode") + "\n", encoding="utf-8")


def timeline(part):
    """Flatten notated ties while retaining section and note-level nuance."""
    result, unit, tied = [], 0, False
    for bar, es in enumerate(SCORE[part]):
        for pitches, duration, outgoing in es:
            if pitches:
                if tied:
                    result[-1][2] += duration
                else:
                    result.append([pitches, unit, duration, bar])
            unit += duration
            tied = outgoing
    return result


def render(path, work):
    import numpy as np
    from scipy import signal

    rate = 44100
    eighth = 30.0 / TEMPO
    period = round(sum(METER) * eighth * rate)
    stereo = np.zeros((period, 2), np.float32)
    rng = np.random.default_rng(411)
    tau = math.tau

    def ease(v):
        v = np.clip(v, 0, 1)
        return v * v * (3 - 2 * v)

    def envelope(t, duration, attack, release):
        return ease(t / attack) * ease((duration + release - t) / release)

    def mix(y, i, pan, gain):
        i %= period
        g = np.array([math.sqrt(1-pan), math.sqrt(1+pan)], dtype=np.float32) * gain
        pcm = y[:, None] * g
        first = min(len(pcm), period-i)
        stereo[i:i+first] += pcm[:first]
        stereo[:len(pcm)-first] += pcm[first:]

    choir_pan = {"Soprano": -.13, "Alto": .35, "Tenor": -.43, "Bass": .13}

    def singer(f, t, dur, vowel, part, cents, phase):
        # Source-filter synthesis: blended OO/AH formants, a delayed pitch bloom and moving breath pressure.
        female = part in ("Soprano", "Alto")
        formants = ((350, 770, 2220), (805, 1320, 2820)) if female else ((305, 685, 2120), (680, 1140, 2450))
        vibrato = ease((t-.14)/.58) * (.20 + .80*vowel)
        p = tau*f*2**(cents/1200)*t + phase + .38*vibrato*np.sin(tau*(4.63+cents*.024)*t + phase)
        p += .21 * (1-np.exp(-t/.07)) * np.sin(tau*1.53*t+phase)
        y = np.zeros_like(t)
        for h in range(1, min(30, math.ceil(6500/f))):
            def resonances(form):
                return sum(g*math.exp(-.5*((h*f-center)/width)**2)
                           for center, width, g in zip(form, (185, 275, 390), (.95, .51, .25)))
            oo, ah = [resonances(form) for form in formants]
            y += np.sin(h*p + .07*h*h) * ((1-vowel)*oo + vowel*ah + .14) / h**.91
        breath = (.92 + .08*np.sin(2.05*t+phase)) * (.77 + .23*ease(t / (.45 + dur*.28)))
        noise = signal.sosfilt(signal.butter(2, [700, 4400], fs=rate, btype="bandpass", output="sos"),
                              rng.normal(0, 1, len(t)))
        return (y+.015*noise) * breath * envelope(t, dur, min(.24, .13+dur*.08), .28)

    # Bass pedal is blended across consecutive bars, including the actual wrap, rather than re-struck.
    organ = {note for pitches, _, _, _ in timeline("Chamber Organ") for note in pitches}
    for note in sorted(organ):
        gate = np.zeros(period, np.float32)
        for notes, u, d, _ in timeline("Chamber Organ"):
            if note in notes:
                gate[round(u*eighth*rate):round((u+d)*eighth*rate)] = 1
        w = np.hanning(round(.31*rate))
        pad = len(w)//2
        gate = signal.fftconvolve(np.pad(gate, pad, mode="wrap"), w/w.sum(), mode="same")[pad:pad+period]
        # Integer cycles keep the oscillator continuous across phase zero.
        f = 440 * 2**((midi_pitch(note)-69)/12)
        phase = tau * round(f*period/rate) * np.arange(period)/period
        core = np.sin(phase) + .23*np.sin(2*phase+.4) + .13*np.sin(3*phase+.1) + .075*np.sin(4*phase+.8)
        gain = .069 if midi_pitch(note) < 43 else .038
        mix(core * gate, 0, -.11, gain)

    for part in SCORE:
        if part == "Chamber Organ":
            continue
        for notes, unit, step_duration, bar in timeline(part):
            dur = step_duration * eighth
            arc = np.interp(bar, [0, 3, 4, 8, 10, 12, 14, 17, 18, 20, 22, 23],
                            [.69, .54, .72, .88, 1, 1.22, 1.23, .91, .61, .73, .52, .37])
            for note in notes:
                f = 440 * 2**((midi_pitch(note)-69)/12)
                if part in choir_pan:
                    t = np.arange(round(rate*(dur+.28)))/rate
                    v = {"Soprano":.78, "Alto":.32, "Tenor":.34, "Bass":.25}[part]
                    v = min(1, v * (1.3 if 12 <= bar < 18 else .55 if bar in (0, 18, 22, 23) else .84))
                    vowel = v * np.maximum(.25, ease(t / (.24+dur*.25)))
                    solo = part == "Soprano" and unit in (2, sum(METER[:18])+2)
                    voices = [(0, 0, 1.0)] if solo else [(-3.2, 3, .56), (4.1, 29, .36), (0, 9, .31)]
                    for j, (cents, ms, weight) in enumerate(voices):
                        i = round((unit*eighth + ms/1000)*rate)
                        y = singer(f, t, dur, vowel, part, cents, rng.uniform(-math.pi,math.pi))
                        mix(y, i, choir_pan[part]+(j-1)*.10 if not solo else -.04,
                            arc*weight*(.125 if part == "Soprano" else .095))
                elif part == "Piano":
                    t = np.arange(round(rate*(dur+1.05)))/rate
                    y = sum(np.sin(tau*(f*h*math.sqrt(1+.00019*h*h))*t+.45*h) * np.exp(-t*(.9+.9*h)) / h**1.38
                            for h in range(1, 11))
                    y *= envelope(t, dur, .011, 1.05)
                    mix(y, round(rate*(unit*eighth+.008)), .25, .081*arc*(1 if unit%4 else 1.09))
                elif part == "Violoncello":
                    t = np.arange(round(rate*(dur+.25)))/rate
                    ph = tau*f*t + .38*ease(t/.60)*np.sin(tau*4.35*t)
                    y = sum(np.sin(h*ph+.09*h*h)*(.30 + math.exp(-.5*((h*f-460)/240)**2))/h**1.1
                            for h in range(1, 15))
                    y *= envelope(t, dur, .22, .25)
                    mix(y, round(rate*(unit*eighth+.033)), -.29, .074*arc)
                elif part == "Bell":
                    t = np.arange(6*rate)/rate
                    y = sum(w*np.sin(tau*f*h*t)*np.exp(-t*k) for h,w,k in
                            ((.50,.76,.87),(1,.65,1.35),(1.194,.16,2.5),(1.51,.12,3.6),(2.11,.10,5.1)))
                    y *= ease(t/.007) * ease((6-t)/.6)
                    mix(y, round(rate*unit*eighth), .09, .079 if bar == 23 else .126)

    # Circular convolution carries the room and the final bell into the next opening.
    reflections = ((.037,.25),(.059,.18),(.094,.14),(.141,.12),(.203,.09),(.281,.08))
    dry = stereo.copy()
    t = np.arange(round(3.5*rate))/rate
    for ch in range(2):
        ir = rng.normal(0,1,len(t)) * np.exp(-t*2.9) * ease((t-.027)/.08)
        ir = signal.sosfilt(signal.butter(2, [160,4800], fs=rate, btype="bandpass", output="sos"),ir)
        ir *= .083 / np.sqrt(np.sum(ir**2))
        for delay, gain in reflections:
            ir[round((delay+ch*.007)*rate)] += gain
        src = .68*dry[:, ch] + .32*dry[:, 1-ch]
        wet = signal.fftconvolve(src, ir).astype(np.float32)
        wet[:len(ir)-1] += wet[period:]
        stereo[:,ch] += .63*wet[:period]
    stereo = np.tanh(stereo*1.21)
    stereo *= .78 / np.max(np.abs(stereo))
    delta = np.abs(stereo[0]-stereo[-1]).max()
    assert delta < .04, f"discontinuity at loop seam: {delta:.5f}"
    work.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=work) as tmp:
        src = Path(tmp) / "preview.wav"
        # Cold start, full exact repeat, and nine seconds of the third opening.
        tail = stereo[:9*rate].copy()
        tail[-3*rate:] *= ease(np.linspace(1,0,3*rate))[:,None]
        head = stereo.copy()
        head[:rate] *= ease(np.linspace(0,1,rate))[:,None]
        pcm = np.concatenate((head, stereo, tail))
        with wave.open(str(src), "wb") as out:
            out.setparams((2, 2, rate, 0, "NONE", "not compressed"))
            out.writeframes((pcm*32767).astype("<i2").tobytes())
        subprocess.run(["ffmpeg","-hide_banner","-loglevel","error","-y","-i",str(src),
                        "-c:a","libmp3lame","-b:a","192k","-metadata",f"title={TITLE}",
                        "-metadata","artist=The Sleeping Academy",str(path)],check=True)
    print(f"{period/rate:.3f}s per loop; seam delta {delta:.6f}; preview {len(pcm)/rate:.3f}s")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--render", action="store_true", help="write stereo MP3 (NumPy, SciPy and FFmpeg)")
    parser.add_argument("--out", type=Path, default=Path("Music"))
    args = parser.parse_args()
    validate()
    args.out.mkdir(parents=True, exist_ok=True)
    score(args.out / "no-morning-follows.musicxml")
    if args.render:
        render(args.out / "no-morning-follows.mp3", Path(".runtime/main-theme"))


if __name__ == "__main__":
    main()
