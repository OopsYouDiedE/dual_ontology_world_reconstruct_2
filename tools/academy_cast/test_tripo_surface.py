"""Geometry regression tests for the source-local Tripo review pipeline."""
import unittest
import numpy as np
from tripo_surface import borders, adjacency, close, crossings, eye_mesh, masses, route_triangles, topology


class SurfaceTests(unittest.TestCase):
    def setUp(self):
        self.v=np.array([[0.,0,0],[1,0,0],[1,1,0],[0,1,0],[0,0,1],[1,0,1],[1,1,1],[0,1,1]])
        self.f=[[3,2,1,0],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]]

    def test_closed_volume_centroid(self):
        m=masses(self.v,self.f,True)
        self.assertAlmostEqual(m['signed_volume'],1.)
        np.testing.assert_allclose(m['volume_centroid'],[.5,.5,.5])
        m=masses(self.v+[2,-3,8],self.f,True)
        np.testing.assert_allclose(m['volume_centroid'],[2.5,-2.5,8.5])

    def test_boundary_fill(self):
        hole=self.f[1:]
        self.assertEqual([len(r) for r in borders(adjacency(hole))],[4])
        g, report=close(self.v,hole)
        self.assertEqual(len(report),1)
        self.assertEqual(topology(g)['boundary_edges'],0)
        self.assertEqual(topology(g)['winding_errors'],0)
        self.assertAlmostEqual(masses(self.v,g,True)['signed_volume'],1.)

    def test_route_triangle_pair(self):
        f = self.f[1:] + [[3,2,1],[3,1,0]]
        v, g, paths = route_triangles(self.v,f,set())
        self.assertEqual(paths,[1]);self.assertEqual(topology(g)['tris'],0)
        self.assertEqual(topology(g)['boundary_edges'],0)
        self.assertAlmostEqual(masses(v,g,True)['signed_volume'],1.)

    def test_eye_is_closed_all_quad(self):
        p=eye_mesh([0.,0.,0.],.015)
        t=topology(p['f']);self.assertEqual(t['boundary_edges']+t['winding_errors']+t['tris'],0)
        self.assertEqual(t['triangle_equivalent'],96)

    def test_crossing_detects_nonadjacent_faces(self):
        v=np.array([[0.,0,0],[1,0,0],[0,1,0],[.2,.2,-1],[.2,.2,1],[.8,.2,1]])
        self.assertEqual(crossings(v,[[0,1,2]],[[3,4,5]]),1)
        v[3:]+=3
        self.assertEqual(crossings(v,[[0,1,2]],[[3,4,5]]),0)


if __name__=='__main__':
    unittest.main()
