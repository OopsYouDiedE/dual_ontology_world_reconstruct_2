#!/usr/bin/env python3
"""Write and measure the four On the Same Night theme studies (MusicXML + MP3)."""
import argparse
import json
import math
from pathlib import Path
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from functools import lru_cache

from main_theme import child, direction, midi_pitch, pitch_parts

TEMPO, DIV, BAR, NBAR = 68, 12, 48, 16
TICK = 60 / (TEMPO * DIV)
LEAD_IN, TAIL = .024, 1.7
TARGET_I, MAX_TP = -20, -1.2
PARTS = {
    'Soprano': ('G', 2, 0, 53, 'S.'), 'Alto': ('G', 2, 0, 53, 'A.'),
    'Tenor': ('G', 2, -1, 53, 'T.'), 'Bass': ('F', 4, 0, 53, 'B.'),
    'Piano': ('G', 2, 0, 1, 'Pno.'), 'Violoncello': ('F', 4, 0, 43, 'Vc.'),
    'Bell': ('F', 4, 0, 15, 'Bell'),
}
VOICES = tuple(PARTS)[:4]
TYPES = {2: ('16th', 0), 3: ('16th', 0), 6: ('eighth', 0), 12: ('quarter', 0),
         18: ('quarter', 1), 24: ('half', 0), 36: ('half', 1), 48: ('whole', 0)}
NAMES = {'a': 'Chapel', 'b': 'Held Breath', 'c': 'Escapement', 'd': 'No Tomorrow'}
R = 'r:48'
# Shared topline: the G–Ab half-step is a local reference; the rest is project material.
PRAYER = ['G5:24 Ab5:24', 'G5:24 Eb5:12 D5:6 r:6']
SOP = PRAYER + [
    'r:6 F5:6 G5:12 Ab5:24', 'Bb5:12 Ab5:12 G5:18 r:6',
    'Eb5:12 G5:18 F5:18', 'Db5:24 Eb5:12 F5:6 r:6',
    'r:12 G5:24 F5:12', 'Eb5:24 D5:18 r:6', R, R,
] + PRAYER + [
    'G5:12 Ab5:12 G5:12 Eb5:12', 'F5:12 Ab5:12 Bb5:18 r:6',
    'Ab5:24 G5:18 r:6', 'D5:24 r:24',
]
BASE = {
    'Soprano': SOP,
    'Alto': ['r:36 C4:12', 'Eb4:24 C4:12 Bb3:12', 'r:12 D4:12 Eb4:24', 'F4:12 Eb4:12 D4:18 r:6',
             'C4:24 Eb4:12 D4:12', 'Bb3:24 C4:12 Db4:12', 'r:12 Eb4:24 D4:12', 'C4:24 Bb3:18 r:6', R, R,
             'Eb4:48', 'Eb4:24 C4:12 Bb3:12', 'Eb4:12 Eb4:12 Eb4:12 C4:12', 'D4:12 Eb4:12 F4:18 r:6',
             'Eb4:24 Eb4:18 r:6', 'Bb3:24 r:24'],
    'Tenor': [R, 'r:6 Bb3:18 G3:12 F3:12', 'r:18 Bb3:6 C4:24', 'D4:12 C4:12 Bb3:18 r:6',
              'G3:24 C4:12 A3:12', 'F3:24 G3:12 Ab3:12', 'G3:48', 'G3:24 F3:18 r:6', R, R,
              'Bb3:24 C4:24', 'Bb3:24 G3:12 F3:12', 'Bb3:12 C4:12 Bb3:12 G3:12', 'A3:12 C4:12 D4:18 r:6',
              'C4:24 Bb3:18 r:6', 'F3:24 r:24'],
    'Bass': [R, 'r:24 C3:12 Bb2:12', 'r:24 Ab2:24', 'Bb2:12 Ab2:12 G2:18 r:6', 'C3:36 D3:12',
             'Bb2:24 C3:12 Db3:12', 'C3:36 D3:12', 'Eb3:24 Bb2:18 r:6', R, R,
             'Eb3:24 Ab2:24', 'Eb3:24 C3:12 Bb2:12', 'Eb3:12 Ab2:12 Eb3:12 C3:12',
             'D3:12 Ab2:12 Bb2:18 r:6', 'Ab2:24 Eb3:18 r:6', 'Bb2:24 r:24'],
    'Piano': [R, R, R, R, 'r:24 G4:12 F4:12', 'F4:12 Db4:12 G4:12 Ab4:12',
              'G4:24 r:12 F4:12', 'Eb4:24 D4:12 r:12',
              'C4:6 Eb4:6 G4:6 Eb4:6 Bb3:6 D4:6 F4:6 D4:6',
              'Ab3:6 C4:6 Eb4:6 C4:6 Bb3:6 D4:6 F4:6 D4:6',
              'G4:24 Eb4:24', 'G4:24 Eb4:12 D4:6 r:6', 'G4:12 Eb4:12 G4:12 C4:12', 'F4:12 Eb4:12 F4:18 r:6',
              'Eb4:24 G4:18 r:6', 'D4:24 C4:24'],
    'Violoncello': ['r:36 Ab3:12', 'Eb3:24 C3:12 Bb2:12', 'r:12 Bb2:12 Ab2:24', 'Bb2:12 Ab2:12 G2:18 r:6',
                    'C3:36 D3:12', 'Bb2:24 C3:12 Db3:12', 'C3:36 D3:12', 'Eb3:24 Bb2:24', 'C3:24 Bb2:24', 'Ab2:24 Bb2:24',
                    'Eb3:24 Ab2:24', 'Eb3:24 C3:12 Bb2:12', 'Eb3:12 Ab2:12 Eb3:12 C3:12', 'D3:12 Ab2:12 Bb2:24',
                    'Ab2:24 Eb3:24', 'Bb2:24 C3:24'],
    'Bell': [R]*15 + ['C4:24 r:24'],
}


def updated(s, parts):
    out = {p: bars.copy() for p, bars in s.items()}
    for part, bars in parts.items():
        for n, bar in bars.items():
            out[part][n-1] = bar
    return out


def eighths(bass):
    return ' '.join(f'{n}:6' for n in bass.split())


def six(notes):
    return ' '.join(f'{n}:2' for n in notes.split())


# B: expose a G (or C) pedal, letting altered notes rub against it; no digital clipping to mimic tension.
B = updated(BASE, {
    'Alto': {2:'D4:24 C4:12 Db4:6 r:6', 4:'F4:12 D4:12 Eb4:18 r:6', 6:'D4:36 C4:12',
             11:'D4:36 C4:12', 12:'D4:24 Db4:18 r:6', 13:'D4:48', 15:'Eb4:24 Eb4:18 r:6', 16:'B3:24 r:24'},
    'Tenor': {4:'D4:12 C4:12 B3:18 r:6', 6:'G3:48', 11:'B3:36 C4:12', 12:'B3:24 G3:24',
              13:'B3:24 C4:24', 15:'D4:24 Bb3:18 r:6', 16:'Ab3:24 r:24'},
    'Bass': {4:'G2:24 G2:18 r:6', 6:'G2:48', 11:'G2:48',
             12:'G2:48', 13:'G2:48', 15:'G2:48', 16:'G2:24 r:24'},
    'Violoncello': {4:'G2:48', 6:'G2:48', 9:'C3:48', 10:'G2:48', 11:'G2:48',
                    12:'G2:48', 13:'G2:48', 15:'G2:48', 16:'G2:48'},
    'Piano': {11:'G4:24 D4:24', 12:'D4:24 Db4:24', 16:'Ab4:24 D4:24'},
})
# C: six-per-beat figure relinquishes its pulse to the cello; the return falls inside that pulse.
P9 = six('G4 Eb4 C4 Eb4 D4 Eb4 G4 Eb4 C4 Eb4 D4 Eb4 F4 D4 Bb3 D4 C4 D4 F4 D4 Bb3 D4 C4 D4')
P10 = six('Eb4 C4 Ab3 C4 Bb3 C4 Eb4 C4 Ab3 C4 Bb3 C4') + ' r:24'
C = updated(BASE, {
    'Piano': {9:P9, 10:P10, 11:'r:36 Eb4:6 r:6', 12:'G4:6 r:18 Eb4:6 r:18',
              13:'r:6 Eb4:6 r:12 G4:6 r:18', 14:'r:12 Eb4:6 r:18 F4:6 r:6',
              15:'Eb4:6 r:18 G4:6 r:18', 16:'r:36 D4:6 r:6'},
    'Violoncello': {10:'Ab2:24 ' + eighths('G2 G2 G2 G2'), 11:eighths('G2 G2 G2 G2 C3 C3 C3 C3'),
                    12:eighths('C3 C3 C3 C3 C3 C3 Bb2 Bb2'), 13:eighths('C3 C3 Ab2 Ab2 Eb3 Eb3 C3 C3'),
                    14:eighths('D3 D3 Ab2 Ab2 Bb2 Bb2 Bb2 Bb2'), 15:eighths('Ab2 Ab2 Ab2 Ab2 G2 G2 G2 G2'),
                    16:eighths('G2 G2 G2 G2 G2 G2 G2 G2')},
    'Bass': {11:'r:24 C3:24', 15:'Ab2:24 G2:18 r:6', 16:'G2:24 r:24'},
    'Tenor': {11:'r:12 Bb3:12 C4:24'},
    'Alto': {11:'r:6 Eb4:18 Eb4:24'},
})
# D: put the dissonance at the moment the known line returns; aim the rest of the cadence away from resolution.
D = updated(C, {
    'Alto': {6:'Bb3:24 C4:12 Db4:12', 11:'r:12 D4:24 Eb4:12', 12:'Eb4:24 C4:12 Bb3:12',
             14:'r:6 D4:6 Eb4:12 F4:18 r:6', 15:'Eb4:24 Eb4:18 r:6', 16:'Bb3:24 r:24'},
    'Tenor': {11:'r:18 Bb3:18 C4:12', 14:'A3:12 r:6 C4:6 D4:18 r:6', 16:'F3:24 r:24'},
    'Bass': {11:'r:24 r:6 G2:6 C3:12', 12:'C3:36 Bb2:12'},
    'Violoncello': {11:eighths('G2 G2 G2 G2 G2 G2 C3 C3'),
                    12:eighths('C3 C3 C3 C3 C3 C3 Bb2 Bb2'),
                    16:eighths('G2 G2 G2 G2 G2 G2 G2 G2')},
    'Piano': {11:R, 12:'r:12 G4:6 r:6 Eb4:6 r:18', 16:'r:36 D4:6 r:6'},
    'Bell': {16:'C4:12 r:36'},
})
STUDIES = dict(a=BASE, b=B, c=C, d=D)


@lru_cache(None)
def parse(bar):
    tokens = tuple((p, int(d)) for p, d in (s.split(':') for s in bar.split()))
    assert sum(d for _, d in tokens) == BAR, bar
    trip, pos = 0, 0
    for p, d in tokens:
        assert d in TYPES
        if p != 'r':
            assert 36 <= midi_pitch(p) <= 82, p
        if d == 2:
            assert p != 'r' and pos % DIV == trip*2
            trip = (trip + 1) % 6
        else:
            assert not trip
        pos += d
    assert not trip
    return tokens


def events(score, part):
    result = []
    for m, bar in enumerate(score[part]):
        pos = m*BAR
        for p, dur in parse(bar):
            if p != 'r':
                result.append((pos, dur, p))
            pos += dur
    return result


def validate_common(score):
    assert tuple(score) == tuple(PARTS)
    for p, bars in score.items():
        assert len(bars) == NBAR
        for bar in bars:
            parse(bar)
        if p != 'Soprano':
            assert events(score, p)[0][0] >= 36
    grid = [{t:midi_pitch(pitch) for pos,d,pitch in events(score, p) for t in range(pos,pos+d)}
            for p in VOICES]
    for upper, lower in zip(grid, grid[1:]):
        for t in upper.keys() & lower.keys():
            assert upper[t] >= lower[t], f'SATB voices cross at measure {t//BAR+1}, tick {t%BAR}'


def validate(score, version):
    validate_common(score)
    assert score['Soprano'] == SOP and SOP[:2] == SOP[10:12]
    if version in 'cd':
        assert sum(d == 2 for _, d in parse(score['Piano'][8])) == 24
        assert all(d == 6 for _, d in parse(score['Violoncello'][9])[1:])
        assert all(d == 6 for _, d in parse(score['Violoncello'][-1]))
    if version == 'd':
        assert score['Alto'][10] == 'r:12 D4:24 Eb4:12'
        assert score['Bass'][10] == 'r:24 r:6 G2:6 C3:12'
        assert score['Piano'][10] == R
        assert score['Bell'][-1] == 'C4:12 r:36'


def export_score(score, version, path):
    slurs = {(1,0):'start', (2,36):'stop', (3,6):'start', (4,24):'stop',
             (5,0):'start', (6,36):'stop', (7,12):'start', (8,24):'stop',
             (11,0):'start', (12,36):'stop', (13,0):'start', (14,24):'stop',
             (15,0):'start', (15,24):'stop'}
    return write_score(score, path, name=f'{version.upper()}. {NAMES[version]}', slurs=slurs,
                       breaks=(5, 9, 11, 13) if version in 'cd' else (5, 9, 13),
                       form={5:('A', 'Gather'), 9:('B', 'Clockwork'), 11:('A2', 'Same vow'), 15:('C', 'Before dawn')},
                       dynamics={(4,0):'mp', (11,0):'p', (14,0):'mf', (16,0):'p'},
                       directions={('Violoncello',10,24):'Poco marcato'} if version in 'cd' else None)


def write_score(score, path, *, name, form, slurs, dynamics, breaks=(5,9,13), directions=None, accents=()):
    root = ET.Element('score-partwise', version='4.0')
    directions = directions or {}
    child(child(root, 'work'), 'work-title', 'On the Same Night')
    child(root, 'movement-title', name)
    child(child(root, 'identification'), 'creator', 'The Sleeping Academy - theme studies', type='composer')
    defaults = child(root, 'defaults')
    scaling = child(defaults, 'scaling')
    child(scaling, 'millimeters', 6.05)
    child(scaling, 'tenths', 40)
    listing = child(root, 'part-list')
    for i, (part, (_, _, _, program, abbr)) in enumerate(PARTS.items(), 1):
        tag = child(listing, 'score-part', id=f'P{i}')
        child(tag, 'part-name', 'Tubular Bell' if part == 'Bell' else part)
        child(tag, 'part-abbreviation', abbr)
        child(child(tag, 'score-instrument', id=f'P{i}-I1'), 'instrument-name', part)
        midi = child(tag, 'midi-instrument', id=f'P{i}-I1')
        child(midi, 'midi-channel', i)
        child(midi, 'midi-program', program)
    for i, (part, (sign, line, octave, _, _)) in enumerate(PARTS.items(), 1):
        track = child(root, 'part', id=f'P{i}')
        first = events(score, part)[0][0]
        for n, bar in enumerate(score[part], 1):
            m = child(track, 'measure', number=str(n))
            if n in breaks:
                child(m, 'print', **{'new-system': 'yes'})
            if n == 1:
                attr = child(m, 'attributes')
                child(attr, 'divisions', DIV)
                key = child(attr, 'key')
                child(key, 'fifths', -3)
                child(key, 'mode', 'minor')
                time = child(attr, 'time')
                child(time, 'beats', 4)
                child(time, 'beat-type', 4)
                clef = child(attr, 'clef')
                child(clef, 'sign', sign)
                child(clef, 'line', line)
                if octave:
                    child(clef, 'clef-octave-change', octave)
                if i == 1:
                    wrapper, metro = direction(m, 'metronome')
                    child(metro, 'beat-unit', 'quarter')
                    child(metro, 'per-minute', TEMPO)
                    child(wrapper, 'sound', tempo=str(TEMPO))
            if i == 1 and n in form:
                mark, text = form[n]
                direction(m, 'rehearsal', mark)
                direction(m, 'words', text)
            pos = 0
            tokens = parse(bar)
            for j, (pitch, d) in enumerate(tokens):
                if first == (n-1)*BAR + pos:
                    text, dyn = {'Soprano':('Solo, ah; legato','p'), 'Alto':('Oo; enter separately','pp'),
                                 'Tenor':('Oo','pp'), 'Bass':('Oo','pp'), 'Piano':('Una corda','p'),
                                 'Violoncello':('Arco, sul tasto','pp'), 'Bell':('One stroke', 'p')}[part]
                    direction(m, 'words', text)
                    child(direction(m, 'dynamics', placement='below')[1], dyn)
                if (part, n, pos) in directions:
                    direction(m, 'words', directions[part, n, pos])
                if part == 'Soprano' and (n, pos) in dynamics:
                    child(direction(m, 'dynamics', placement='below')[1], dynamics[n, pos])
                item = child(m, 'note')
                if pitch == 'r':
                    child(item, 'rest', **({'measure': 'yes'} if d == BAR else {}))
                else:
                    step, alter, octv = pitch_parts(pitch)
                    el = child(item, 'pitch')
                    child(el, 'step', step)
                    if alter:
                        child(el, 'alter', alter)
                    child(el, 'octave', octv)
                child(item, 'duration', d)
                if not (pitch == 'r' and d == BAR):
                    typ, dots = TYPES[d]
                    child(item, 'type', typ)
                    if dots:
                        child(item, 'dot')
                if d == 2:
                    tm = child(item, 'time-modification')
                    child(tm, 'actual-notes', 6)
                    child(tm, 'normal-notes', 4)
                    child(tm, 'normal-type', '16th')
                    beam = 'begin' if pos % DIV == 0 else 'end' if pos % DIV == 10 else 'continue'
                    for beam_n in ('1','2'):
                        child(item, 'beam', beam, number=beam_n)
                    if beam != 'continue':
                        child(child(item, 'notations'), 'tuplet', type='start' if beam == 'begin' else 'stop', bracket='no')
                if d == 6 and pitch != 'r' and part in ('Piano','Violoncello'):
                    # Pair adjacent eighths within a beat; leave isolated pickups unjoined.
                    def eighth(k):
                        return 0 <= k < len(tokens) and tokens[k][0] != 'r' and tokens[k][1] == 6
                    if pos % DIV == 0 and eighth(j+1):
                        child(item, 'beam', 'begin', number='1')
                    elif pos % DIV == 6 and eighth(j-1):
                        child(item, 'beam', 'end', number='1')
                if part == 'Soprano' and (n, pos) in slurs:
                    assert pitch != 'r'
                    child(child(item, 'notations'), 'slur', type=slurs[n, pos], number='1')
                if (part, n, pos) in accents:
                    assert pitch != 'r' and d != 2
                    child(child(child(item, 'notations'), 'articulations'), 'accent')
                pos += d
            if n == NBAR:
                child(child(m, 'barline', location='right'), 'bar-style', 'light-heavy')
    ET.indent(root)
    path.write_bytes(ET.tostring(root, encoding='utf-8', xml_declaration=True) + b'\n')


# Compare the score, never the sound of the synthesizer, on a common 12-tick-per-beat grid.
STABLE = {0, 3, 4, 7, 8, 9}
CONTEXT = {5}
TENSE = {1, 2, 6, 10, 11}


def interval_stats(score, return_bar=11):
    def midi_grid(part):
        result = [None]*(BAR*NBAR)
        for t, d, p in events(score, part):
            result[t:t+d] = [midi_pitch(p)]*d
        return result

    names = ('stable', 'fourth', 'tense')
    views = {k:dict.fromkeys(names, 0) for k in ('all', 'bass', 'return_bass')}
    details = []
    grids = [midi_grid(p) for p in PARTS if p != 'Bell']
    for t, (top, *others) in enumerate(zip(*grids)):
        lower = [p for p in others if p is not None]
        if top is None or not lower:
            continue
        for i, p in enumerate(sorted(lower)):
            pc = (top-p)%12
            assert pc in STABLE | CONTEXT | TENSE
            bin_name = names[0] if pc in STABLE else names[1] if pc in CONTEXT else names[2]
            views['all'][bin_name] += 1
            if i == 0:
                views['bass'][bin_name] += 1
                if (return_bar-1)*BAR <= t < (return_bar+1)*BAR:
                    views['return_bass'][bin_name] += 1
    start = (return_bar-1)*BAR
    for t in [start,start+24,start+36,start+BAR,15*BAR]:
        top, *others = [g[t] for g in grids]
        low = min((p for p in others if p is not None), default=None)
        details.append({'measure':t//BAR+1,'beat':1+t%BAR//DIV,'lead':top,'bass':low,
                        'interval_semitones':None if top is None or low is None else (top-low)%12})
    return {**{k:{n:round(100*v/sum(counts.values()),1) for n,v in counts.items()}
               for k, counts in views.items()}, 'selected_sonorities':details}



def synth(score, version):
    import numpy as np
    from scipy import signal

    rate = 44100
    index = lambda t: round(t * rate)
    size = index(LEAD_IN+NBAR*BAR*TICK+TAIL)
    ease = lambda x: (lambda q: q*q*(3-2*q))(np.clip(x,0,1))
    band = signal.butter(2, [1150, 4900], fs=rate, btype='bandpass', output='sos')
    pans = (0, .33, -.32, .10, .23, -.22, -.08)
    gains = (.24, .078, .079, .074, .096, .119, .10)
    dry = np.zeros((size, 2))
    for k, (part, pan, gain) in enumerate(zip(PARTS, pans, gains)):
        rng = np.random.default_rng(2131+k)
        seq = events(score, part)
        for j, (pos, d, pitch) in enumerate(seq):
            start = index(LEAD_IN+pos*TICK)
            dur = d*TICK
            freq = 440*2**((midi_pitch(pitch)-69)/12)
            m = pos//BAR+1
            weight = 1
            if part in VOICES:
                high = part == 'Soprano'
                entry = j == 0 or seq[j-1][0]+seq[j-1][1] != pos
                end = j == len(seq)-1 or pos+d != seq[j+1][0]
                release = .165 if end else .055
                t = np.arange(index(dur+release))/rate
                phase = rng.random()*math.tau
                cents = 1.7*np.sin(6.1*t+phase) - (12 if entry else 4)*np.exp(-t/.07)
                cents += (19 if high else 10)*ease((t-.13)/.61)*np.sin(2*np.pi*(5.06+.10*k)*t+.37*phase)
                angle = 2*np.pi*np.cumsum(freq*2**(cents/1200))/rate+.16*phase
                form = ((515,1050,2480),(710,1230,2800)) if high else ((325,695,2030),(415,910,2290))
                opened = ease(t/(.36+.12*dur))
                y = np.zeros(len(t))
                for h in range(1, 19):
                    oo, ah = [sum(g*np.exp(-.5*((h*freq-f)/w)**2) for f,g,w in
                                  zip(vowel,(1,.48,.23),(145,235,302))) for vowel in form]
                    y += np.sin(h*angle-.14*h*h)*(.21+oo+(ah-oo)*opened)/h**1.09
                air = signal.sosfilt(band, rng.normal(size=len(t)))
                y += air*(.014+.021*np.exp(-t/.077)*entry)
                y *= ease(t/(.090 if entry else .048))*ease((dur+release-t)/release)
                y *= (.89+.11*ease(t/.4))*(.95+.05*np.sin(2.8*t+phase))
                weight = 1.08 if m in (4,14) and high else .88 if m == 16 else 1
            elif part == 'Piano':
                rel = .18 if d == 2 else .27
                t = np.arange(index(dur+rel))/rate
                y = sum(np.sin(2*np.pi*freq*h*math.sqrt(1+.00016*h*h)*t+.42*h)
                        * np.exp(-t*(1.08+1.20*h))/h**1.37 for h in range(1, 13))
                y *= ease(t/.009)*ease((dur+rel-t)/rel)
                weight = (1,.64,.72,.79,.67,.74)[pos%DIV//2] * .83 if d == 2 else .83
            elif part == 'Violoncello':
                rel = .093 if d == 6 else .22
                t = np.arange(index(dur+rel))/rate
                phase = 2*np.pi*freq*t + .36*ease(t/.4)*np.sin(2*np.pi*4.24*t)
                y = sum(np.sin(h*phase+.09*h*h)*(.23+np.exp(-.5*((h*freq-400)/230)**2))/h**1.19
                        for h in range(1, 14))
                y *= ease(t/(.064 if d == 6 else .18))*ease((dur+rel-t)/rel)
                y *= .79+.21*np.sin(np.pi*t/(dur+rel))
                if d == 6:
                    weight = (1.15 if pos%DIV == 0 else .81) if m in (10,11,16) else (1 if pos%DIV == 0 else .8)
            else:
                rel = 1.14
                t = np.arange(index(dur+rel))/rate
                # Inharmonic, quickly decaying strike above a lower nominal C.
                y = sum(g*np.sin(2*np.pi*r*freq*t)*np.exp(-t/a) for r,g,a in
                        ((1,.79,.61),(2.02,.49,.45),(2.74,.35,.21),(4.16,.24,.16),(5.41,.10,.12)))
                y *= ease(t/.009)*ease((dur+rel-t)/rel)
                weight = .84 if version == 'd' else 1
            dry[start:start+len(y)] += (gain*weight*y)[:,None]*np.sqrt([1-pan,1+pan])
        if k == 0:
            solo = dry[:index(LEAD_IN+36*TICK)].copy()
    cut = index(LEAD_IN+36*TICK)
    assert np.array_equal(solo, dry[:cut])
    assert np.max(np.abs(dry[:index(LEAD_IN/2)])) == 0
    # Identical causal chamber for all studies. No pre-echo, compressor or limiter.
    mixed = dry.copy()
    rng = np.random.default_rng(941)
    t = np.arange(index(1.05))/rate
    for channel in range(2):
        ir = signal.sosfilt(band, rng.normal(size=len(t)))*np.exp(-5.3*t)*ease(t/.064)*ease((1.05-t)/.17)
        ir *= .075 / np.linalg.norm(ir)
        for delay, level in ((.041,.20),(.079,.13),(.132,.087),(.209,.065),(.329,.037)):
            ir[index(delay+channel*.006)] += level
        mixed[:,channel] += .71*signal.fftconvolve(.79*dry[:,channel]+.21*dry[:,1-channel],ir)[:size]
    return mixed, rate, solo


def meter_audio(path):
    args = ['ffmpeg','-hide_banner','-nostats','-i',str(path),'-af',
            'loudnorm=I=-20:TP=-1.2:LRA=20:print_format=json','-f','null','-']
    err = subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True).stderr
    raw = json.loads(re.findall(r'\{[^{}]+\}', err)[-1])
    return {key:float(raw[f'input_{ff}']) for key, ff in
            [('integrated_lufs','i'),('true_peak_dbtp','tp'),('loudness_range_lu','lra')]}


def render(version, score, out, tmp):
    import numpy as np
    from scipy.io.wavfile import write

    mixed, rate, solo = synth(score, version)
    wav = tmp/'premaster.wav'
    write(wav, rate, mixed.astype('float32'))
    input_meter = meter_audio(wav)
    # Constant gain only. Re-measure the delivered MP3 instead of assuming encoded TP.
    gain = min(TARGET_I-input_meter['integrated_lufs'], MAX_TP-input_meter['true_peak_dbtp']-.3)
    final = out/f'{version}-{slug(version)}.mp3'
    for i in range(3):
        subprocess.run(['ffmpeg','-v','error','-y','-i',str(wav),'-af',f'volume={gain:.4f}dB',
                        '-c:a','libmp3lame','-b:a','192k','-metadata',f'title={NAMES[version]} | On the Same Night',
                        str(final)],check=True)
        output = meter_audio(final)
        if output['true_peak_dbtp'] <= MAX_TP:
            break
        gain -= output['true_peak_dbtp']-MAX_TP+.2
    assert output['true_peak_dbtp'] <= MAX_TP
    ret = {'input':input_meter, 'delivered_mp3':output, 'gain_db':round(gain,2),
           'first_other_voice_seconds':round(LEAD_IN+36*TICK,3),
           'return_seconds':round(LEAD_IN+10*BAR*TICK,3), 'duration_seconds':round(len(mixed)/rate,3)}
    if version == 'd':
        # A separate continuous splice preview. The cold opening in the full track is untouched.
        # Cello release and the chamber tail from the old turn sit underneath its successor.
        i = round((LEAD_IN+14*BAR*TICK)*rate)
        boundary = round(NBAR*BAR*TICK*rate)
        preview = mixed[:round((LEAD_IN+2*BAR*TICK)*rate)].copy()
        n = min(len(preview), len(mixed)-boundary)
        preview[:n] += mixed[boundary:boundary+n]
        end = round(.32*rate)
        preview[-end:] *= np.linspace(1,0,end)[:,None]
        clip = np.concatenate([mixed[i:boundary], preview])*10**(gain/20)
        fade = round(.075*rate)
        clip[:fade] *= np.linspace(0,1,fade)[:,None]
        write(wav, rate, clip.astype('float32'))
        subprocess.run(['ffmpeg','-v','error','-y','-i',str(wav),'-c:a','libmp3lame','-b:a','192k',
                        '-metadata','title=No Tomorrow | Bell to next turn',
                        str(out/'d-next-turn.mp3')],check=True)
        ret['loop_preview_mp3'] = meter_audio(out/'d-next-turn.mp3')
        assert ret['loop_preview_mp3']['true_peak_dbtp'] <= -1
    return ret, solo


def slug(version):
    return NAMES[version].lower().replace(' ', '-')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=Path('Music/theme-studies'))
    parser.add_argument('--render', action='store_true')
    parser.add_argument('--versions', default='abcd', choices=('abc','d','abcd'))
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    results, previous = {}, None
    scratch = Path('.runtime/main-theme')
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='theme-studies-',dir=scratch) as work:
        for version in args.versions:
            score = STUDIES[version]
            validate(score, version)
            export_score(score, version, args.out/f'{version}-{slug(version)}.musicxml')
            data = {'title':NAMES[version], 'intervals':interval_stats(score)}
            if args.render:
                import numpy as np
                data['loudness'], intro = render(version, score, args.out, Path(work))
                if previous is not None:
                    assert np.array_equal(previous,intro), 'Same dry soprano is required on every intro'
                previous = intro
            results[version] = data
            print(version, data['intervals']['all'], data['intervals']['return_bass'], data.get('loudness',{}).get('delivered_mp3'))
    name = 'metrics.json' if args.render else 'intervals.json'
    dest = args.out/name
    record = json.loads(dest.read_text(encoding='utf-8')) if dest.exists() else {}
    record.update(results)
    dest.write_text(json.dumps(record, indent=2)+'\n', encoding='utf-8')
    if args.render and args.versions == 'abcd':
        meters = [m['loudness']['delivered_mp3']['integrated_lufs'] for m in results.values()]
        assert max(meters)-min(meters) <= .3, 'Comparative files must be level matched'


if __name__ == '__main__':
    main()
