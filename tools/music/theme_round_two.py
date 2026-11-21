#!/usr/bin/env python3
"""Round two: three different themes, then a common MuseScore playback test."""
import argparse
import json
from pathlib import Path

from theme_studies import (BAR, NBAR, R, TEMPO, TICK, VOICES, eighths, events, interval_stats,
                           midi_pitch, parse, updated, validate_common, write_score)

OUT = Path('Music/theme-studies/round-two')
E_HEAD = 'D5:18 G5:6 Ab5:12 G5:12'
F_HEAD = 'Eb5:12 D5:12 Eb5:12 C5:12'
G_HEAD = 'Ab5:18 G5:6 Eb5:12 F5:12'
# Three unchanged turns in 4/4. The octave leap sets the register of the chromatic descent.
GROUND = ['C2:36 C3:12', 'B2:36 Bb2:12', 'A2:36 Ab2:12',
          'G2:36 Eb2:12', 'F2:12 G2:12 G2:24']

# E: a single subject descends through the choir at the octave and twelfth.
E = {
    'Soprano': [E_HEAD, 'F5:12 Eb5:18 D5:12 r:6', 'r:6 Eb5:6 F5:12 G5:24', 'Ab5:18 G5:6 F5:12 Eb5:6 r:6',
                'G5:12 Bb5:12 Ab5:12 G5:12', 'F5:24 Eb5:12 D5:6 r:6', 'r:12 D5:18 G5:6 Ab5:12', 'G5:24 F5:18 r:6',
                R, 'r:24 D5:18 r:6', E_HEAD, 'F5:12 Eb5:18 D5:12 r:6',
                'Eb5:24 F5:12 G5:12', 'Bb5:18 Ab5:6 G5:18 r:6', 'F5:18 Eb5:6 D5:24', 'D5:24 r:24'],
    'Alto': [R, 'D4:18 G4:6 Ab4:12 G4:12', 'Bb4:12 A4:12 G4:24', 'Eb4:24 D4:12 C4:12',
             'Eb4:12 F4:12 Eb4:12 D4:12', 'D4:24 C4:12 Bb3:12', 'r:18 Bb3:18 C4:12', 'Eb4:24 D4:18 r:6',
             'Ab4:18 Eb4:6 F4:12 D4:12', 'D4:24 F4:12 Eb4:12', 'F4:18 G4:6 Ab4:12 G4:12', 'D4:12 C4:24 Bb3:12',
             'C4:24 D4:12 Eb4:12', 'F4:18 Eb4:6 D4:18 r:6', 'D4:18 C4:6 Bb3:24', 'Bb3:24 r:24'],
    'Tenor': [R, R, 'G3:18 C4:6 Db4:12 C4:12', 'Ab3:24 Bb3:12 G3:12',
              'C4:12 D4:12 C4:12 Bb3:12', 'Bb3:24 G3:12 F3:12', 'G3:24 F3:12 Ab3:12', 'C4:24 A3:18 r:6',
              'r:12 C4:24 Bb3:12', 'Bb3:24 r:12 C4:12', 'Bb3:18 C4:6 Eb4:12 D4:12', 'Bb3:12 G3:24 F3:12',
              'G3:24 Bb3:12 C4:12', 'D4:18 C4:6 Bb3:18 r:6', 'Bb3:18 G3:6 F3:24', 'G3:24 r:24'],
    'Bass': [R, R, R, 'D3:18 G3:6 Ab3:12 G3:12',
             'C3:12 Bb2:12 Ab2:12 G2:12', 'Bb2:24 C3:12 Bb2:12', 'G2:24 Bb2:12 Ab2:12', 'C3:24 D3:18 r:6',
             'F2:24 Ab2:24', 'Bb2:24 Ab2:24', 'Bb2:18 C3:6 Ab2:12 G2:12', 'Bb2:12 C3:24 Bb2:12',
             'C3:24 Bb2:12 C3:12', 'Bb2:18 Ab2:6 G2:18 r:6', 'Bb2:18 C3:6 Bb2:24', 'G2:24 r:24'],
    'Piano': [R,R,R,R, R,R,R,R,
              'r:12 D4:12 G4:12 Ab4:12', 'G4:24 F4:12 r:12', R, R,
              R, 'r:24 G4:12 D4:12', 'F4:18 Eb4:6 D4:24', 'r:24 D4:12 r:12'],
    'Violoncello': [R,R,R,R,
                    'C3:12 Bb2:12 Ab2:12 G2:12', 'Bb2:24 C3:12 Bb2:12', 'G2:24 Bb2:12 Ab2:12', 'C3:24 D3:24',
                    'F2:24 Ab2:24', 'Bb2:24 Ab2:24', 'Bb2:18 C3:6 Ab2:12 G2:12', 'Bb2:12 C3:24 Bb2:12',
                    'C3:24 Bb2:12 C3:12', 'Bb2:18 Ab2:6 G2:24', 'Bb2:18 C3:6 Bb2:24', 'G2:48'],
    'Bell': [R]*15+['r:24 C4:12 r:12'],
}

# F: the chapel is built around a ground that does not wait for the singer.
F = {
    'Soprano': [F_HEAD, 'Eb5:18 G5:6 F5:12 Eb5:12', 'D5:24 Eb5:12 F5:6 r:6', 'Eb5:12 C5:12 Eb5:24',
                'D5:24 G5:18 r:6', 'G5:24 F5:12 D5:12', 'Eb5:36 G5:12', 'F5:18 Eb5:6 D5:18 r:6',
                'Eb5:24 F5:12 Eb5:12', 'D5:24 C5:12 Eb5:12', 'F5:24 G5:12 r:12', F_HEAD,
                'D5:24 F5:12 G5:12', 'G5:18 F5:6 Eb5:24', 'D5:24 Eb5:18 r:6', 'C5:12 D5:12 r:24'],
    'Alto': [R, 'r:6 G4:18 C4:24', 'F4:18 D4:6 G4:12 D4:12', 'C4:24 Eb4:24',
             'D4:24 Eb4:18 r:6', 'Eb4:24 D4:12 Bb3:12', 'Eb4:36 G4:12', 'D4:18 G4:6 F4:18 r:6',
             'C4:24 D4:12 C4:12', 'Bb3:24 C4:24', 'C4:24 D4:12 r:12', 'Eb4:24 D4:12 C4:12',
             'F4:24 D4:12 F4:12', 'Eb4:18 D4:6 C4:24', 'D4:24 Eb4:18 r:6', 'C4:12 D4:12 r:24'],
    'Tenor': [R, 'r:18 G3:18 A3:12', 'B3:24 D4:12 Bb3:12', 'A3:24 C4:24',
              'Bb3:24 G3:18 r:6', 'C4:24 A3:12 G3:12', 'G3:36 C4:12', 'B3:18 D4:6 C4:18 r:6',
              'A3:24 C4:12 Ab3:12', 'G3:24 Bb3:24', 'A3:24 G3:12 r:12', 'G3:24 Bb3:12 G3:12',
              'B3:24 B3:12 D4:12', 'C4:24 A3:12 Ab3:12', 'Bb3:24 G3:18 r:6', 'A3:12 G3:12 r:24'],
    'Bass': [R,R,R,R,
             'G2:24 Eb3:18 r:6', 'F2:12 G2:12 Bb2:24', 'C3:36 C3:12', 'B2:36 Bb2:12',
             'A2:36 Ab2:12', 'G2:36 Eb3:12', 'F2:12 G2:12 G2:24', 'r:12 C3:24 C3:12',
             'B2:36 Bb2:12', 'A2:36 Ab2:12', 'G2:36 Eb3:12', 'F2:12 G2:12 r:24'],
    'Piano': [R,R,R,R, 'r:24 G4:12 r:12', 'r:24 C4:12 D4:12', 'r:36 Eb4:12', 'r:36 F4:12',
              'r:24 C4:12 Eb4:12', 'r:24 Bb3:12 G4:12', 'F4:24 r:24', R,
              'r:36 Ab4:12', 'r:24 C4:12 Eb4:12', 'r:24 D4:12 r:12', 'r:36 G4:12'],
    'Violoncello': [R] + GROUND*3,
    'Bell': [R]*15+['r:24 C4:12 r:12'],
}

# G: the opening falls by the same half-step used as a rise in D. The piano
# and cello share one 3+3+2 pulse pattern, with the handoff at m10 beat 4.
G = {
    'Soprano': [G_HEAD, 'G5:18 Bb5:6 Ab5:12 G5:6 r:6', 'r:6 Eb5:6 G5:12 F5:24', 'Eb5:24 D5:18 r:6',
                'Eb5:12 F5:12 Ab5:18 G5:6', 'F5:24 Eb5:12 D5:12', 'C5:12 Eb5:12 G5:24', 'F5:18 Eb5:6 D5:18 r:6',
                R,R, G_HEAD, 'G5:18 Bb5:6 Ab5:12 G5:6 r:6',
                'Eb5:18 F5:6 G5:24', 'Ab5:12 Bb5:24 Ab5:6 r:6', 'Bb5:18 Ab5:6 G5:24', 'Ab5:12 G5:12 r:24'],
    'Alto': ['r:36 C4:12', 'Eb4:18 G4:6 F4:12 Eb4:12', 'r:12 Eb4:12 D4:24', 'C4:24 Bb3:24',
             'C4:12 D4:12 Eb4:18 Eb4:6', 'D4:24 C4:12 Bb3:12', 'C4:24 Eb4:24', 'D4:18 C4:6 Bb3:24',
             R,R, 'r:18 Eb4:18 D4:12', 'Eb4:18 F4:6 Eb4:12 D4:12',
             'C4:18 D4:6 Eb4:24', 'Eb4:12 F4:24 Eb4:12', 'D4:18 Eb4:6 Eb4:24', 'C4:12 D4:12 r:24'],
    'Tenor': [R, 'r:6 Bb3:18 C4:12 Bb3:12', 'r:18 C4:6 Bb3:24', 'G3:24 F3:24',
              'G3:12 Bb3:12 C4:18 Bb3:6', 'Bb3:24 G3:12 F3:12', 'G3:24 C4:24', 'Bb3:18 G3:6 F3:24',
              R,R, 'r:24 G3:12 Bb3:12', 'Bb3:18 D4:6 C4:12 Bb3:12',
              'G3:18 Bb3:6 C4:24', 'C4:12 D4:24 C4:12', 'Bb3:18 C4:6 Bb3:24', 'Ab3:12 Bb3:12 r:24'],
    'Bass': [R, 'r:24 Ab2:12 Eb3:12', 'r:24 Bb2:24', 'C3:24 Bb2:24',
             'C3:12 Bb2:12 Ab2:18 Eb3:6', 'Bb2:24 C3:12 Bb2:12', 'C3:24 Ab2:24', 'Bb2:18 C3:6 Bb2:24',
             R,R, 'r:36 Bb2:12', 'Eb3:18 Bb2:6 Ab2:12 G2:12',
             'C3:18 Bb2:6 C3:24', 'Ab2:12 Bb2:24 Ab2:12', 'Bb2:18 Ab2:6 Eb3:24', 'r:12 G2:12 r:24'],
    'Piano': [R,R,R,R, 'r:12 F4:12 Eb4:18 G4:6', 'F4:24 Eb4:12 D4:12', 'C4:12 Eb4:12 G4:24', 'F4:18 Eb4:6 D4:18 r:6',
              eighths('C4 G4 Eb4 Bb3 F4 D4 C4 Eb4'), 'Ab3:6 Eb4:6 C4:6 Bb3:6 F4:6 D4:6 r:12',
              R, 'r:18 D4:6 r:12 Ab4:6 r:6', 'r:18 Eb4:6 r:12 G4:6 r:6',
              'r:18 F4:6 r:12 Eb4:6 r:6', 'r:18 Eb4:6 r:12 D4:6 r:6', R],
    'Violoncello': ['r:36 F3:12', 'Eb3:18 Bb2:6 Ab2:12 Eb3:12', 'r:12 C3:12 Bb2:24', 'C3:24 Bb2:24',
                    'C3:12 Bb2:12 Ab2:18 Eb3:6', 'Bb2:24 C3:12 Bb2:12', 'C3:24 Ab2:24', 'Bb2:18 C3:6 Bb2:24',
                    'C3:18 Bb2:18 C3:12', 'Ab2:18 Bb2:18 G2:6 G2:6',
                    eighths('G2 G2 G2 G2 C3 C3 Bb2 Bb2'), eighths('Eb3 Eb3 Eb3 Bb2 Ab2 Ab2 G2 G2'),
                    eighths('C3 C3 C3 Bb2 C3 C3 C3 C3'), eighths('Ab2 Ab2 Bb2 Bb2 Bb2 Bb2 Ab2 Ab2'),
                    eighths('Bb2 Bb2 Bb2 Ab2 Eb3 Eb3 Eb3 Eb3'), eighths('G2 G2 G2 G2 G2 G2 G2 G2')],
    'Bell': [R]*15+['r:24 C4:12 r:12'],
}

STUDIES = {
    'e-echo-office': ('E. Echo Office', E, 11, {5:('I','Four answers'), 9:('II','Far echo'), 11:('III','Return')}),
    'f-night-ledger': ('F. Night Ledger', F, 12, {2:('I','Ground'), 7:('II','Ground returns'), 12:('III','Third turn')}),
    'g-broken-dawn': ('G. Broken Dawn', G, 11, {5:('I','Gather'), 9:('II','3+3+2'), 11:('III','Return')}),
}
PHRASES = {
    'e': [((1,0),(2,30)), ((3,6),(4,36)), ((5,0),(6,36)), ((7,12),(8,24)),
          ((11,0),(12,30)), ((13,0),(14,24)), ((15,0),(16,0))],
    'f': [((1,0),(3,36)), ((4,0),(5,24)), ((6,0),(8,24)), ((9,0),(11,24)),
          ((12,0),(15,24)), ((16,0),(16,12))],
    'g': [((1,0),(2,36)), ((3,6),(4,24)), ((5,0),(6,36)), ((7,0),(8,24)),
          ((11,0),(12,36)), ((13,0),(14,36)), ((15,0),(16,12))],
}


def validate():
    assert len({E_HEAD,F_HEAD,G_HEAD})==3
    for score in (E,F,G):
        validate_common(score)
        assert events(score,'Soprano')[0][0] == 0
    sig = lambda s: tuple((midi_pitch(p)-midi_pitch(parse(s)[0][0]), d) for p,d in parse(s))
    assert sig(E_HEAD)==sig(E['Alto'][1])==sig(E['Tenor'][2])==sig(E['Bass'][3])
    assert F['Violoncello'][1:] == GROUND*3
    assert parse(G['Piano'][9])[-1] == ('r',12)
    assert G['Violoncello'][9].endswith('G2:6 G2:6') and G['Piano'][10]==R
    for score,bar in ((E,11),(F,12),(G,11)):
        assert score['Soprano'][0]==score['Soprano'][bar-1]


def summary(score, return_bar):
    c = {p:events(score,p) for p in score}
    return {
        'return_measure':return_bar,
        'seconds_of_solo_opening':round(min(e[0][0] for p,e in c.items() if p!='Soprano')*TICK,3),
        'vocal_note_attacks':{p:len(c[p]) for p in VOICES},
        'return_starts_seconds':round((return_bar-1)*4*60/TEMPO,3),
        'measures':NBAR,
        'score_seconds':round(NBAR*4*60/TEMPO,3),
        'intervals':interval_stats(score, return_bar=return_bar),
    }


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=OUT)
    opts=parser.parse_args()
    validate()
    opts.out.mkdir(parents=True,exist_ok=True)
    results={}
    for stem,(name,score,ret,form) in STUDIES.items():
        tag=stem[0]
        slurs={pos:kind for a,b in PHRASES[tag] for pos,kind in ((a,'start'),(b,'stop'))}
        dynamics={(ret,0):'p',(14,0):'mf',(16,0):'p'}
        directions={('Violoncello',10,36):'Take over'} if tag=='g' else {}
        accents=tuple([('Piano',m,p) for m in (9,10) for p in (0,18,36) if not (m==10 and p==36)] +
                      [('Violoncello',10,36)] +
                      [('Violoncello',m,p) for m in range(11,17) for p in (0,18,36)]) if tag=='g' else ()
        write_score(score,opts.out/f'{stem}.musicxml',name=name,form=form,slurs=slurs,dynamics=dynamics,
                    directions=directions,accents=accents)
        results[stem]=summary(score,ret)
        if tag=='f':
            before = 'Eb5:12 D5:24 C5:12'
            old = updated(F, {'Soprano':{1:before, 12:before, 13:'D5:24 F5:12 Ab5:12'}})
            validate_common(old)
            initial = interval_stats(old, return_bar=ret)
            results[stem]['initial_pass'] = {key:initial[key] for key in ('all','return_bass')}
        print(stem, results[stem]['intervals']['all'],results[stem]['intervals']['return_bass'])
    (opts.out/'score-metrics.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':
    main()
