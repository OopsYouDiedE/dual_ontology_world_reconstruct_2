"""Build a seven-character anatomical revision from the previous audited bodies."""
from argparse import ArgumentParser
import json
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.spatial import cKDTree
from anatomy_geometry import CAST,FACE,PROFILES,body_measurement
from anatomy_auricle import candidates
from anatomy_structural import build_body
from tripo_surface import crossings, reduce_strips
from tripo_surface_preview import CLOTH,clothes
from anatomy_projection import iou,mesh_mask,reference_mask


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def save(path,data):
    path.write_text(json.dumps(data,separators=(',',':')),encoding='utf-8')


def clean_patch(v, f, profile, index, side, dense, excluded):
    for verts,faces,keep,stat,ear in candidates(v,f,profile,FACE[index],index,side,dense,excluded):
        patch=faces[len(keep):]
        root=sorted({k for g in patch for k in g if k<len(v)})
        aabb=verts[ear+root]
        lo=aabb.min(0)-1e-7; hi=aabb.max(0)+1e-7
        rivals=[g for g in faces[:len(keep)] if (verts[g].max(0)>=lo).all() and (verts[g].min(0)<=hi).all()]
        if crossings(verts,rivals,patch)==0 and crossings(verts,patch,patch)==0:
            return verts,faces,keep,stat,ear,root
    raise RuntimeError(f'No closed, noncrossing auricle patch: {CAST[index]} side={side} dense={dense}')


def triangles(ff):return sum(len(g)-2 for g in ff)


def one(base,out,slug,profile,index,image,strength):
    source_lo=read(base/f'{slug}-low.json'); face_rings=read(base/f'{slug}-loops.json')
    lookup0=np.array(source_lo[0]['v']); prev=read(base/'fitted'/f'{slug}-low.json')
    vprev=np.array(prev[0]['v']); kdt=cKDTree(vprev)
    old_ids={u for m in face_rings.values() for g in m.values() for u in g}
    distance,ix=kdt.query(lookup0[sorted(old_ids)])
    if distance.max()>1e-6:raise ValueError((slug,'face IDs moved unexpectedly',distance.max()))
    new_idx=dict(zip(sorted(old_ids),ix.tolist()))
    face_rings={k:{name:[new_idx[u] for u in g] for name,g in m.items()} for k,m in face_rings.items()}
    locked=set(new_idx.values())
    eye_brow=triangles([f for p in prev if p['name'].startswith(('Eye ','Brow ')) for f in p['f']])
    ref=reference_mask(image,profile)
    status={}; marks={}; geom={}
    for version in ('low','sculpt'):
        high=version=='sculpt'
        d=read(base/'fitted'/f'{slug}-{version}.json'); body=d[0]; f=body['f']; colors=np.array(body['color'])
        v=np.array(body['v']); u,metrics=build_body(v,f,profile,index,strength)
        ear=[]; stat=[]
        # Protect every named eyelid/lip loop and reserve their adjacency unchanged.
        forbidden=set() if high else locked.copy()
        if high:
            # Old high cage is already spaced away from the eyes. Exclude all
            # vertices in front of that plane from ear-base patch selection.
            forbidden=set(np.flatnonzero((v[:,1]<-.033)&(v[:,2]>.85)))
        for side in (-1,1):
            u,f,keep,ss,ids,root=clean_patch(u,f,profile,index,side,high,forbidden)
            col=np.tile(colors[0],(len(f)-len(keep),1));colors=np.vstack([colors[keep],col])
            stat.append(ss);ear.append(ids);forbidden.update(ids);forbidden.update(root)
        ear_pre=triangles(f); strip_info=[]
        if not high and ear_pre+eye_brow>5000:
            u,f,strip_info,_=reduce_strips(u,f,5000-eye_brow,forbidden)
            if triangles(f)+eye_brow>5000:raise ValueError((slug,triangles(f)+eye_brow))
            inner=set(face_rings['2']['inside']); tone=colors[0]; inside=[79,51,45]
            colors=np.asarray([inside if len(inner.intersection(g))>=2 else tone for g in f])
        live=np.unique(np.concatenate(f)); renumber=np.full(len(u),-1);renumber[live]=np.arange(len(live))
        u=u[live]; f=[renumber[g].tolist() for g in f]
        assert all(renumber[b]>=0 for r in ear for b in r)
        marks[version]={label:renumber[ids].tolist() for label,ids in zip(('Right auricle','Left auricle'),ear)}
        if not high:
            face_rings={k:{label:renumber[ds].tolist() for label,ds in ring.items()} for k,ring in face_rings.items()}
            assert all(i>=0 for a in face_rings.values() for ids in a.values() for i in ids)
            save(out/f'{slug}-loops.json',face_rings)
        body.update(v=u.tolist(),f=f,color=colors.tolist()); f2=[o for o in d if o['name'] not in ('Underwear','Sports top')]
        wpx,hpx=[(261,312),(251,303),(252,311),(764,821),(747,806),(771,824),(747,802)][index]
        for name,(pos,faces) in clothes(u,f,index,waist_and_hem=(profile.z(wpx),profile.z(hpx))).items():
            f2.append(dict(name=name,v=pos.tolist(),f=faces,color=np.tile(CLOTH[index],(len(faces),1)).tolist()))
        save(out/f'{slug}-{version}.json',f2)
        solid=mesh_mask(u,f)
        geometry=body_measurement(u,f); geom[version]=geometry
        status[version]={**metrics,'ears':stat,'strip_quads_removed':int(sum(strip_info)),
                         'body_quads':sum(len(g)==4 for g in f),'other_faces':sum(len(g)!=4 for g in f),
                         'triangles':triangles(f),'front_iou':iou(solid,ref)}
    save(out/f'{slug}-ear-vertices.json',marks)
    before=body_measurement(vprev,prev[0]['f']); after=geom['low']; diff={}
    for name,key in [('surface','surface_centroid'),('volume','volume_centroid')]:
        diff[f'{name}_centroid_shift_pct_h']=float(100*np.linalg.norm(np.subtract(after[key],before[key]))) if key in after and key in before else None
    q=status['low']['triangles']+eye_brow
    print(slug,'ear loops',[e['root_loop'] for e in status['sculpt']['ears']],'budget',q,'body %H',round(status['sculpt']['peak_pct_h'],2),flush=True)
    return dict(character=slug,low_body_eye_brow_triangles=q,
        front_silhouette_iou={k:s['front_iou'] for k,s in status.items()},
        structure=status,centroids_before_after={'previous':before,'low':after},**diff)


if __name__=='__main__':
    a=ArgumentParser(description=__doc__)
    a.add_argument('base',type=Path);a.add_argument('reference',type=Path);a.add_argument('out',type=Path)
    a.add_argument('--cast',nargs='+',choices=CAST,default=CAST);a.add_argument('--strength',type=float,default=1.)
    args=a.parse_args();args.out.mkdir(exist_ok=True,parents=True);im=Image.open(args.reference).convert('RGB')
    rows=[one(args.base,args.out,s,PROFILES[CAST.index(s)],CAST.index(s),im,args.strength) for s in args.cast]
    save(args.out/'anatomy-metrics.json',rows)
