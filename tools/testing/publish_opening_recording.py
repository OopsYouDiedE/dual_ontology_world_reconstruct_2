"""Check complete production coverage and attach it through the project MCP."""
import argparse
import ast
import asyncio
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'mcp/review'))
from client import invoke
sys.path.insert(0,str(ROOT/'tools/testing'))
import mainline_recordings


def write(path,value):
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


async def append_capture(target,record):
    coverage=mainline_recordings.read(record['coverage'])
    counts=coverage['counts'][record['segment_id']]
    segment=record['segment_id']
    folder=target.parent
    # Preserve existing v1 request IDs while giving later recordings separate works.
    work=('complete-recording-'+segment+'-v1' if folder.name=='opening-complete-20261116-v1'
          else 'recording-'+folder.name+'-'+segment)
    response=(await invoke('progress_append',{'work_id':work,'segment_id':segment,'kind':'check','revision':record['revision'],
        'summary':'第一段完整录制与对白逐字核验' if segment=='wake' else '第二段完整录制与九句会合对白核验',
        'result':f"覆盖全部阶段，{counts['utterances']}条完整台词、{counts['subtitle_fragments']}个原速显示片段；连续视频与关键帧已保留。音轨无信号，音频验收待修。",
        'evidence':[target.relative_to(ROOT).as_posix(),record['coverage']]}))['result']
    if response.get('isError'): raise RuntimeError(response)
    print(json.dumps({'segment':segment,'event_id':response['structuredContent']['event']['event_id'],
                      'duplicate':response['structuredContent']['duplicate']},ensure_ascii=False),flush=True)


async def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',required=True)
    args=parser.parse_args()
    folder=mainline_recordings.provenance.project_path(args.output,ROOT)
    if all((folder/(segment+'.capture.json')).is_file() for segment in ('wake','corridor')):
        for segment in ('wake','corridor'):
            target=folder/(segment+'.capture.json')
            record=mainline_recordings.read(target)
            mainline_recordings.validate(record)
            await append_capture(target,record)
        print(json.dumps({'already_published':True,'validated_segments':['wake','corridor']}))
        return
    sequence=mainline_recordings.read(folder/'sequence.json')
    launch=mainline_recordings.read(folder/'launch.json')
    video=mainline_recordings.read(folder/'video-coverage.json')
    checks=[]
    def check(name,passed):
        checks.append({'check':name,'passed':bool(passed)})
        if not passed: raise ValueError('Coverage check failed: '+name)
    check('normal-speed original subtitles',sequence['skip_subtitles'] is False and sequence['engine_time_scale']==1)
    check('clean process exit and completed production flow',launch['exit_code']==0 and not sequence['failure'])
    mainline_recordings.provenance.validate_source(sequence['source_identity'],launch['project'],pid=launch['host_pid'])
    for relative,expected in launch['source_sha256'].items():
        original=(ROOT/relative).read_bytes()
        check('source fingerprint '+relative,hashlib.sha256(original).hexdigest()==expected)
        snapshot=folder/'sources'/relative
        snapshot=snapshot.with_suffix(snapshot.suffix+'.txt')
        snapshot.parent.mkdir(parents=True,exist_ok=True)
        if snapshot.exists(): check('immutable source copy '+relative,snapshot.read_bytes()==original)
        else: snapshot.write_bytes(original)
    required={'wake':['black','fade','lie','sit','look','talk','getup','free'],
              'corridor':['fadeout','exit','hear','approach','join','talk','card','free']}
    counts={}
    for segment,phases in required.items():
        observed=[e['state'].split(':',1)[1] for e in sequence['events'] if e.get('event')=='phase_enter' and e['state'].startswith(segment+':')]
        check(segment+' every phase in order',observed==phases)
        spoken=[u for u in sequence['utterances'] if u['segment_id']==segment]
        shown=[s for s in sequence['subtitles'] if s['segment_id']==segment]
        check(segment+' every dialogue character displayed in order',''.join(u['text'] for u in spoken)==''.join(s['text'] for s in shown))
        check(segment+' every subtitle retained for original duration',all(s['end_s']-s['start_s']>=2.35 for s in shown))
        counts[segment]={'utterances':len(spoken),'subtitle_fragments':len(shown),'phases':observed}
    completed=[e['kind'] for e in sequence['events'] if e.get('event')=='investigation_completed']
    check('all six bedroom investigations completed through production callbacks',completed==['bed','lamp','desk','window','wardrobe','wash'])
    check('door requested before natural corridor handoff',any(e.get('event')=='interaction_requested' and e.get('kind')=='door' for e in sequence['events']))
    script=(folder/'sources/scenes/dual_world/CorridorGathering.gd.txt').read_text(encoding='utf-8')
    expected=ast.literal_eval(re.search(r'const LINES := (\[.*?\n\])',script,re.S).group(1))
    actual=[u['text'] for u in sequence['utterances'] if u['segment_id']=='corridor']
    check('all nine meeting lines spoken in original order',actual[-len(expected):]==[line[1] for line in expected] and len(expected)==9)
    check('four-second free exploration ending retained',sequence['duration_s']-next(e['time_s'] for e in sequence['events'] if e.get('state')=='corridor:free')>=4)
    frames=sequence['video_frames']
    check('all continuous frame indices retained',[f['index'] for f in frames]==list(range(len(frames))))
    check('all background frame writes succeeded',all(f['write_error']==0 and Path(f['path']).is_file() for f in frames))
    for frame in sequence['frames']:
        mainline_recordings.provenance.verify_image(frame['path'],ROOT,allow_fixture=True)
    gap=[]
    for a,b in zip(frames,frames[1:]):
        if b['time_s']-a['time_s']>.25:
            gap.append({'start_s':a['time_s'],'end_s':b['time_s'],'phase_before':a['phase'],'phase_after':b['phase'],'note':'Actual render interval retained as a held frame in the continuous video.'})
    audio=mainline_recordings.read(folder/'monitor/audio.json')
    coverage={'schema_version':1,'complete':True,'dialogue_complete':True,'acceptance_eligible':False,
              'generated_at':datetime.now().astimezone().isoformat(),'host_pid':launch['host_pid'],
              'duration_s':sequence['duration_s'],'counts':counts,'completed_investigations':completed,
              'keyframe_count':len(sequence['frames']),'video_frame_count':len(frames),'render_intervals_over_250ms':gap,
              'audio_signal_present':audio.get('signal_present'),'checks':checks,
              'limitations':['Development fixture starts at the production wake entry; this is not title/new-game acceptance.',
                             '12 fps capture includes rendering readback overhead; held frames preserve actual scene-load stalls.',
                             'Captured audio has no signal in this run; no audio completeness or loudness pass is assigned.']}
    if (folder/'coverage.json').exists():
        existing=mainline_recordings.read(folder/'coverage.json')
        for key in ('complete','dialogue_complete','host_pid','duration_s','counts','completed_investigations'):
            check('preserved immutable coverage '+key,existing[key]==coverage[key])
    else: write(folder/'coverage.json',coverage)
    relative=lambda p:p.relative_to(ROOT).as_posix()
    for clip in video['clips']:
        record={'schema_version':1,'kind':'continuous-mainline-recording','id':folder.name+'-'+clip['segment_id'],
                'segment_id':clip['segment_id'],'revision':launch['revision'],'acceptance_eligible':False,
                'launch':relative(folder/'launch.json'),'sequence':relative(folder/'sequence.json'),
                'coverage':relative(folder/'coverage.json'),'video':clip['path'],
                'full_video':relative(folder/'complete.mp4'),'end_snapshot':relative(folder/'end.snapshot.json'),
                'start_s':clip['start_s'],'end_s':clip['end_s'],'evidence_sha256':[]}
        for path in [folder/'launch.json',folder/'sequence.json',folder/'coverage.json',folder/'complete.mp4',ROOT/clip['path'],folder/'end.snapshot.json']:
            record['evidence_sha256'].append({'path':relative(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
        mainline_recordings.validate(record)
        target=folder/(clip['segment_id']+'.capture.json')
        if target.exists(): check('immutable segment record '+clip['segment_id'],json.loads(target.read_text(encoding='utf-8'))==record)
        else: write(target,record)
        await append_capture(target,record)
    print(json.dumps({'coverage_complete':True,'checks':len(checks),'counts':counts},ensure_ascii=False))


if __name__=='__main__': asyncio.run(main())
