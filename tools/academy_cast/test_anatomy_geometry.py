import unittest
import numpy as np
from anatomy_geometry import FACE, PROFILES, subdivide
from anatomy_projection import HALF, apply_warp, front_warp, iou, mesh_mask
from anatomy_relief import apply_relief
from anatomy_photo_compare import bilinear


class AnatomyTests(unittest.TestCase):
    def test_front_outline_fit_keeps_depth_height_and_midline(self):
        v=np.array([[-.11,0.,.25],[.10,0.,.25],[.10,.05,.75],[-.11,.05,.75],[0,.03,.5]])
        f=[[0,1,2,3]]
        goal=v.copy();goal[:,0]*=1.2
        original,target=mesh_mask(v,f),mesh_mask(goal,f)
        field=front_warp(original,target,.9)
        deformed=apply_warp(v,field)
        np.testing.assert_array_equal(v[:,1:],deformed[:,1:])
        self.assertEqual(float(deformed[-1,0]),0.)
        self.assertGreater(iou(mesh_mask(deformed,f),target),iou(original,target))
        for off in field:
            self.assertGreater(np.diff(np.arange(HALF+1)+off,axis=1).min(),0)

    def test_subdivision_preserves_old_ids_and_propagates_face_tags(self):
        v=np.array([[0.,0,0],[1.,0,0],[1.,0,1],[0.,0,1],[2.,0,0],[2.,0,1]])
        f=[[0,1,2,3],[1,4,5,2]]
        sub,fs,r,parents=subdivide(v,f,[[0,1,2,3]])
        np.testing.assert_array_equal(np.array([False,True])[parents],[False]*4+[True]*4)
        self.assertEqual(len(fs),8)
        self.assertTrue(all(len(g)==4 for g in fs))
        self.assertEqual(r[0][::2],[0,1,2,3])
        self.assertTrue(all(i>=len(v) for i in r[0][1::2]))
        self.assertTrue(np.isfinite(sub).all())

    def test_face_anchors_in_crown_chin_range(self):
        for p,(l,r,m,width,nose) in zip(PROFILES,FACE):
            self.assertTrue(p.crown<l[1]<=nose<m<p.chin)
            self.assertTrue(p.crown<r[1]<=nose)
            self.assertLess(l[0],r[0])
            self.assertGreater(width,0)
        p=PROFILES[0]
        self.assertLess(abs((p.foot-p.crown)/(p.chin-p.crown)-6.5),.03)

    def test_relief_moves_depth_only_and_respects_locks(self):
        n=10
        x,z=np.meshgrid(np.linspace(-.095,.095,n),np.linspace(.58,.79,n))
        v=np.c_[x.ravel(),np.full(n*n,-.055),z.ravel()]
        fs=[[i,i+1,i+n+1,i+n] for i in range(n*(n-1)) if i%n!=n-1]
        im=np.full((1082,1248,3),[166,122,93],dtype=np.uint8)
        im[194:206,143:183]=[205,153,114]
        info={};u=apply_relief(v,fs,im,PROFILES[0],0,2.15,locked=[0,11,21],report=info)
        np.testing.assert_array_equal(u[:,[0,2]],v[:,[0,2]])
        np.testing.assert_array_equal(u[[0,11,21]],v[[0,11,21]])
        self.assertGreater(info['moved'],0)
        self.assertGreaterEqual(info['min_projected_area_ratio'],.34999)

    def test_projection_gathers_fractional_pixels(self):
        im=np.array([[[0],[10]],[[20],[30]]])
        px=bilinear(im,np.array([.5,0]),np.array([.5,0]))
        np.testing.assert_allclose(px[:,0],[15,0])


if __name__=='__main__':
    unittest.main()
