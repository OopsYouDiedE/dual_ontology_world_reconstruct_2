import unittest
from plan import choose, make, measure

class Budget(unittest.TestCase):
    def test_total_cap_and_physics_rejection(self):
        from verify_rooms import verify
        self.assertEqual(choose(31,28,9,0)['metrics']['global_decision_bits'],0)
        # Incomplete physical evidence cannot approve the topology.
        self.assertFalse(verify(31,20,6,lambda req:dict(ok=True,rooms=[]))['accepted'])
        with self.assertRaises(ValueError):verify(31,9,0,None,density=2)

    def test_seed_and_feasibility(self):
        a=choose(31,20,3); self.assertEqual(a,choose(31,20,3));self.assertLessEqual(a['metrics']['decision_bits'],3); self.assertLessEqual(a['metrics']['map_units'],20)
        with self.assertRaises(ValueError): choose(31,8,3)
    def test_minimum(self):
        a=choose(31,9,0);self.assertEqual((a['metrics']['rooms'],a['metrics']['links'],a['metrics']['decision_bits']),(9,8,0))
    def test_conditional_choices(self):
        e=make(1<<2,[0]*6); m=measure(e); self.assertEqual(m['decision_bits'],2);self.assertIn(('shaft',4,2),m['decision_states']);self.assertNotIn(('shaft',0,2),m['decision_states'])
        with self.assertRaisesRegex(ValueError,'unreachable'):measure(make(1<<4,[0]*6))
    def test_corridor_is_not_a_choice(self):
        a=measure(make(1,[0]*6));b=measure(make(1,[1,0,0,0,0,0]));self.assertEqual(b['map_units']-a['map_units'],1);self.assertEqual(b['decision_bits'],a['decision_bits'])
if __name__=='__main__':unittest.main()
