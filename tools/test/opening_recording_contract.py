"""Protect coverage, provenance and the report's complete-recording presentation."""
from copy import deepcopy
from datetime import datetime
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/testing'))
import mainline_recordings as recordings
import export_review_site as site

checks=[]
def check(label,value):
    if not value: raise AssertionError(label)
    checks.append(dict(check=label,passed=True))

def rejected(record,label):
    try: recordings.validate(record)
    except (ValueError,FileNotFoundError): check(label,True)
    else: raise AssertionError(label)

folder=ROOT/'artifacts/acceptance/opening-complete-20261116-v1'
for segment in ('wake','corridor'):
    record=recordings.read(folder/(segment+'.capture.json'))
    loaded=recordings.validate(record)
    check(segment+' original subtitles retained',len(loaded['subtitles'])==(15 if segment=='wake' else 10))
    check(segment+' every phase present',len(loaded['phases'])==8)
    check(segment+' full keyframe coverage',len(loaded['images'])==(59 if segment=='wake' else 24))
    changed=deepcopy(record);changed['evidence_sha256'][0]['sha256']='0'*64
    rejected(changed,segment+' evidence tampering rejected')
    changed=deepcopy(record);changed['video']='project.godot'
    rejected(changed,segment+' unrelated media path rejected')
    changed=deepcopy(record);changed['acceptance_eligible']=True
    rejected(changed,segment+' development recording never becomes acceptance')
    html=site.recording_details(loaded,site.OUT/'index.html')
    check(segment+' playable video has clear original frame poster','<video controls' in html and 'poster=' in html)
    check(segment+' timestamp links and coverage visible','#t=' in html and '覆盖检查' in html)
    check(segment+' silent audio is disclosed','音轨无信号' in html)

events=[{'kind':'check','segment_id':'corridor','evidence':[(folder/'wake.capture.json').relative_to(ROOT).as_posix()]}]
try: recordings.load(events)
except ValueError: check('cross-segment recording rejected',True)
else: raise AssertionError('cross-segment recording rejected')
result=dict(passed=True,checks=checks,at=datetime.now().astimezone().isoformat())
path=ROOT/'.runtime/review-tests/opening-recording-result.json'
path.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(dict(passed=True,checks=len(checks),report=str(path))))
