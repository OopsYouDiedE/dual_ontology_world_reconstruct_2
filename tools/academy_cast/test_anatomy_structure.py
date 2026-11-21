import unittest

import numpy as np

from anatomy_auricle import ear_rings
from anatomy_structural import local_safety
from tripo_surface import adjacency


class AnatomyStructureTest(unittest.TestCase):
    def test_quad_ear_patch_closes_scalp_and_has_recess(self):
        n=16
        for side in (-1, 1):
            for high in (False, True):
                with self.subTest(side=side, high=high):
                    t=side*np.arange(n)*2*np.pi/n
                    v=np.c_[np.full(n,side*.064),.018*np.cos(t),.033*np.sin(t)]
                    v=np.vstack([v,[side*.067,0,0],[-side*.064,0,0]])
                    rim=list(range(n))
                    f=[[k,(k+1)%n,n] for k in range(n)]
                    f+= [[(k+1)%n,k,n+1] for k in range(n)]
                    record=(0.,np.arange(n),rim,t,set(range(n+1)),0.,0.)
                    u,q,keep,stat,ids=ear_rings(v,f,0,side,high,record)
                    self.assertTrue(np.array_equal(u[:len(v)],v))
                    self.assertTrue(all(len(face)==4 for face in q[len(keep):]))
                    self.assertEqual(len(ids),stat['rings']*n+1)
                    self.assertTrue(all(len(g)==2 and g[0][1]!=g[1][1] for g in adjacency(q).values()))
                    self.assertGreater((u[ids[:n],0]*side).max(), (u[ids[-1],0]*side)+.005)

    def test_local_fold_guard_keeps_oriented_area(self):
        v=np.array([[0.,0.,0.],[1.,0.,0.],[0.,1.,0.],[1.,1.,0.],[3.,3.,3.]])
        f=[[0,1,2],[1,3,2]]
        u=v.copy(); u[1,0]=-1000.; u[2,1]=-700.; u[4,2]+=1.
        q,limited=local_safety(v,u,f)
        self.assertGreater(limited,0)
        np.testing.assert_array_equal(q[4],u[4])
        a,b,c=q[np.array(f)].transpose(1,0,2)
        self.assertTrue((np.cross(b-a,c-a)[:,2]>=.33).all())


if __name__=='__main__':
    unittest.main()
