"""Guarded local cage relaxation for inherited folds; Blender Python only."""
from collections import defaultdict
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from tripo_surface_blender import pairs


def repair_body(ob, max_iter=17):
    """Retain faces, facial features and scale. Accept only fewer static collisions."""
    mesh=ob.data
    original=np.array([list(v.co) for v in mesh.vertices],dtype=float)
    start, ids=pairs(ob)
    total=sum(start.values()); best=total
    if not total:
        return total,best
    heights=np.ptp(original[:,2])
    edges=np.array([list(e.vertices) for e in mesh.edges],dtype=int)
    src,dst=np.concatenate([edges,edges[:,::-1]],axis=0).T
    lens=np.linalg.norm(original[src]-original[dst],axis=1)
    near=1/np.maximum(lens,heights*.0025)**.50
    den=np.bincount(src,weights=near,minlength=len(original))
    nd=np.bincount(src,minlength=len(original))
    current=original.copy()
    clean=set(np.flatnonzero((original[:,2]>heights*.82)|(original[:,2]<heights*.001)))
    adj=defaultdict(set)
    for a,b in edges:
        adj[a].add(b);adj[b].add(a)
    def write(coords):
        mesh.vertices.foreach_set('co',coords.astype('f').ravel())
        mesh.update()
    for _ in range(max_iter):
        active=set(ids)-clean
        if not active:break
        ring=set().union(*(adj[i] for i in active))-active-clean
        extra=set().union(*(adj[i] for i in ring))-ring-active-clean if ring else set()
        w=np.zeros((len(original),1));w[list(active)]=1.;w[list(ring)]=.52;w[list(extra)]=.18
        bump=False; best_trial=None
        for count,relax,weighted in [(1,.35,True),(2,.49,True),(4,.45,False),(7,.53,False),(12,.61,False)]:
            q=current.copy()
            for _ in range(count):
                if weighted:
                    sm=np.array([np.bincount(src,weights=q[dst,j]*near,minlength=len(q))/np.maximum(den,1e-12) for j in range(3)]).T
                else:
                    sm=np.array([np.bincount(src,weights=q[dst,j],minlength=len(q))/np.maximum(nd,1) for j in range(3)]).T
                q+=relax*w*(sm-q)
            offset=q-original
            limits=heights*np.where(original[:,2]<heights*.07,.017,.023)
            q=original+offset*np.minimum(1,limits/np.maximum(np.linalg.norm(offset,axis=1),1e-12))[:,None]
            write(q)
            cs,new_ids=pairs(ob); score=sum(cs.values())
            if score<best and (best_trial is None or score<best_trial[0]):
                best_trial=(score,new_ids,q);bump=True
            if score==0:break
        if not bump:
            write(current)
            norm=np.array([list(m.normal) for m in mesh.vertices])
            for pull in [ .00035,.00075,.0015,.0025,-.00055,-.0012 ]:
                q=current+heights*pull*w*norm
                q[:,2]=np.maximum(0,q[:,2])
                if np.any(np.linalg.norm(q-original,axis=1)>heights*.026):
                    continue
                write(q)
                cs,new_ids=pairs(ob); score=sum(cs.values())
                if score<best and (best_trial is None or score<best_trial[0]):
                    best_trial=(score,new_ids,q);bump=True
                if score==0:break
            if not bump:
                write(current)
                break
        best,ids,current=best_trial
        write(current)
        if not best:break
    return total,best


def carry_cloth(original, current, cloth):
    """Apply the local surface displacement to an already fitted garment."""
    f=[list(p.vertices) for p in current.data.polygons]
    bv=BVHTree.FromPolygons([Vector(x) for x in original],f)
    new=np.array([list(v.co) for v in current.data.vertices]); delta=new-original
    if np.max(np.abs(delta))<1e-8:return
    for ob in cloth:
        for v in ob.data.vertices:
            hit,_,i,dist=bv.find_nearest(v.co)
            if i is None or dist>.013:continue
            ids=f[i]; pos=np.array(hit)
            w=1/np.maximum(np.linalg.norm(original[ids]-pos,axis=1),1e-5)**2
            v.co+=Vector(w@delta[ids]/w.sum())
        ob.data.update()


def patch_small_terminal_fold(ob):
    """Replace a folded toe/finger disk with an oriented quad fan, if audited better.

    Entirely opt-in after local relaxation stalls. The surrounding cage, nail
    boundaries, face feature IDs and joint loops stay fixed.
    """
    import bpy
    from collections import Counter
    mesh=ob.data
    coords=np.array([list(v.co) for v in mesh.vertices]); height=np.ptp(coords[:,2])
    faces=[tuple(g.vertices) for g in mesh.polygons]; mat=[g.material_index for g in mesh.polygons]
    mat_slots=list(mesh.materials)
    score0, marks=pairs(ob); best=sum(score0.values()); before=best
    lut=np.arange(len(coords))
    if not before:
        return before,best,lut
    for _ in range(5):
        # Limit automatic patching to terminal digits, well away from face/hips.
        seeds=[j for j in marks if coords[j,2]<.049*height or
               (.40*height<coords[j,2]<.585*height and abs(coords[j,0])>.22*height)]
        if not seeds:break
        first=min(seeds,key=lambda j:coords[j,2]); distance=np.linalg.norm(coords-coords[first],axis=1)
        active={j for j in seeds if distance[j]<.016*height}
        winner=None
        for _ring in range(6):
            pick={k for k,g in enumerate(faces) if active.intersection(g)}
            window={j for k in pick for j in faces[k]}
            if len(pick)<4 or len(pick)>190 or max(distance[list(window)])>.042*height:
                break
            directed={}; multiplicity=Counter()
            for k in pick:
                g=faces[k]
                for a,b in zip(g,g[1:]+g[:1]):
                    edge=tuple(sorted((a,b))); directed[edge]=(a,b);multiplicity[edge]+=1
            successor={directed[e][0]:directed[e][1] for e,n in multiplicity.items() if n==1}
            start=min(successor) if successor else -1
            rim=[];seen=set();j=start
            while j in successor and j not in seen:
                rim.append(j);seen.add(j);j=successor[j]
            valid=(j==start and len(rim)==sum(n==1 for n in multiplicity.values()) and
                   4<=len(rim)<=40 and len(rim)%2==0)
            active=window
            if not valid:continue
            unchanged=[g for k,g in enumerate(faces) if k not in pick]
            mm=[a for k,a in enumerate(mat) if k not in pick]
            hitmat=Counter(mat[k] for k in pick).most_common(1)[0][0]
            p=coords[rim]; center=p.mean(0); relative=p-center
            vec=np.cross(relative,np.roll(relative,-1,axis=0)).sum(0)
            normal=vec/max(np.linalg.norm(vec),1e-12)
            for variant in (0,1):
                ring=rim[variant:]+rim[:variant]; ctr=len(coords); n=len(ring)
                patch=[(ctr,ring[i],ring[(i+1)%n],ring[(i+2)%n]) for i in range(0,n,2)]
                if any(len(set(g))!=4 for g in patch):continue
                for offset in (0,.0007,-.0007,.0015,-.0015,.0025,-.0025):
                    xyz=np.vstack([coords,center+height*offset*normal]);xyz[-1,2]=max(0,xyz[-1,2])
                    ff=unchanged+patch; material=mm+[hitmat]*len(patch)
                    if len(ff)>len(faces):continue
                    live=np.unique(np.concatenate(ff)); rmap=np.full(len(xyz),-1);rmap[live]=np.arange(len(live))
                    q=xyz[live];gg=[tuple(rmap[list(g)]) for g in ff]
                    tmp=bpy.data.meshes.new('candidate quad fan'); tmp.from_pydata(q.tolist(),[],gg)
                    if tmp.validate():bpy.data.meshes.remove(tmp);continue
                    tmp.update()
                    ob.data=tmp;counts,ids=pairs(ob);num=sum(counts.values());ob.data=mesh
                    if num<best and (winner is None or num<winner[0]):
                        winner=(num,ids,q,gg,material,rmap)
                    bpy.data.meshes.remove(tmp)
                    if num==0:break
                if winner and winner[0]==0:break
            if winner and winner[0]==0:break
        if winner is None:break
        best,marks,coords,faces,mat,rmap=winner
        lut=np.array([rmap[i] if i>=0 else -1 for i in lut]); old=mesh
        mesh=bpy.data.meshes.new(old.name+' — terminal patch');mesh.from_pydata(coords.tolist(),[],faces);mesh.update()
        for slot in mat_slots:mesh.materials.append(slot)
        for p,i in zip(mesh.polygons,mat):p.material_index=i;p.use_smooth=True
        ob.data=mesh;bpy.data.meshes.remove(old)
        if not best:break
    return before,best,lut
