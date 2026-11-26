import struct
import unittest
import numpy as np
import cv2
from app import HEADER, STATS, Temporal, composite, demo_frame

class Tests(unittest.TestCase):
    def test_protocol(self):
        self.assertEqual(HEADER.size,48)
        self.assertEqual(STATS.size,16)
        self.assertEqual(len(HEADER.pack(160,90,1,1,1,.7,16/9,3.5,.65,0,.35,0)),48)
    def test_synthetic(self):
        rgb,z=demo_frame(320,180)
        self.assertEqual(rgb.shape,(180,320,3)); self.assertEqual(z.shape,(180,320))
        self.assertTrue(np.all(np.isfinite(z)&(z>0)))
        self.assertGreater(np.unique(z).size,2)
    def test_history(self):
        rgb,z=demo_frame(32,18); t=Temporal(); a=np.full((18,32,4),.1,np.float32)
        x=t.apply(rgb,z,a,.8,True); np.testing.assert_allclose(x,a,atol=1e-6)
        b=np.full_like(a,.2); y=t.apply(rgb,z,b,.8,False)
        np.testing.assert_allclose(y,.12,atol=1e-6)
        y=t.apply(255-rgb,z,b,.8,False); np.testing.assert_allclose(y,b,atol=1e-6)
    def test_composite(self):
        rgb,z=demo_frame(32,18); fx=np.zeros((9,16,4),np.float32)
        np.testing.assert_array_equal(composite(rgb,fx),rgb)
        fx[:,:,:3]=.1; out=composite(rgb,fx)
        self.assertTrue(np.all(out>=rgb));self.assertGreater(np.sum(out.astype(int)-rgb),0)

if __name__=='__main__':unittest.main()
