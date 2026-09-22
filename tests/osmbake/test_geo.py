"""좌표 투영과 거리 계산 테스트."""
import unittest

from tools.osmbake.geo import Projector, haversine


class TestHaversine(unittest.TestCase):
    def test_같은_점은_거리_0(self):
        p = (37.5, 127.0)
        self.assertAlmostEqual(haversine(p, p), 0.0, places=6)

    def test_위도_0_001도는_약_111m(self):
        d = haversine((37.5, 127.0), (37.501, 127.0))
        self.assertAlmostEqual(d, 111.2, delta=1.0)


class TestProjector(unittest.TestCase):
    def setUp(self):
        self.proj = Projector(37.5, 127.0)

    def test_원점은_0_0(self):
        x, z = self.proj.to_xz(37.5, 127.0)
        self.assertAlmostEqual(x, 0.0, places=6)
        self.assertAlmostEqual(z, 0.0, places=6)

    def test_동쪽은_x_양수(self):
        x, z = self.proj.to_xz(37.5, 127.001)
        self.assertGreater(x, 0.0)
        self.assertAlmostEqual(z, 0.0, places=6)

    def test_북쪽은_z_음수(self):
        # Godot 의 -Z 가 북쪽을 향하므로 북쪽은 z 가 음수여야 한다.
        x, z = self.proj.to_xz(37.501, 127.0)
        self.assertAlmostEqual(x, 0.0, places=6)
        self.assertLess(z, 0.0)
        self.assertAlmostEqual(z, -111.3, delta=1.0)


if __name__ == "__main__":
    unittest.main()
