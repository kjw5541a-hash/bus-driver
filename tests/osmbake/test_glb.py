"""glTF 2.0 바이너리(.glb) writer."""
import json
import struct
import tempfile
import unittest
from pathlib import Path

from tools.osmbake.glb import write_glb
from tools.osmbake.mesh import MeshBuilder


def square(y=0.0):
    builder = MeshBuilder()
    builder.add_polygon([(0, y, 0), (1, y, 0), (1, y, 1), (0, y, 1)], (0, 1, 0))
    return builder


def read_glb(path):
    data = path.read_bytes()
    magic, version, total = struct.unpack_from("<III", data, 0)
    json_len, json_type = struct.unpack_from("<II", data, 12)
    gltf = json.loads(data[20:20 + json_len])
    return magic, version, total, len(data), json_type, gltf


class TestWriteGlb(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "out.glb"

    def tearDown(self):
        self.tmp.cleanup()

    def test_헤더가_glTF_규격(self):
        write_glb(self.path, {"chunk_0_0": {"road": square()}})
        magic, version, total, size, json_type, _gltf = read_glb(self.path)
        self.assertEqual(magic, 0x46546C67)  # 'glTF'
        self.assertEqual(version, 2)
        self.assertEqual(total, size)
        self.assertEqual(json_type, 0x4E4F534A)  # 'JSON'

    def test_청크마다_노드와_메쉬(self):
        write_glb(self.path, {
            "chunk_0_0": {"road": square()},
            "chunk_1_0": {"road": square()},
        })
        *_rest, gltf = read_glb(self.path)
        self.assertEqual(len(gltf["nodes"]), 2)
        self.assertEqual(len(gltf["meshes"]), 2)
        self.assertEqual(sorted(n["name"] for n in gltf["nodes"]),
                         ["chunk_0_0", "chunk_1_0"])

    def test_도로와_건물은_별도_프리미티브(self):
        write_glb(self.path, {"chunk_0_0": {"road": square(),
                                            "building": square(3.0)}})
        *_rest, gltf = read_glb(self.path)
        self.assertEqual(len(gltf["meshes"][0]["primitives"]), 2)

    def test_빈_서피스는_넣지_않는다(self):
        write_glb(self.path, {"chunk_0_0": {"road": square(),
                                            "building": MeshBuilder()}})
        *_rest, gltf = read_glb(self.path)
        self.assertEqual(len(gltf["meshes"][0]["primitives"]), 1)

    def test_접근자_개수가_정점수와_맞는다(self):
        write_glb(self.path, {"chunk_0_0": {"road": square()}})
        *_rest, gltf = read_glb(self.path)
        primitive = gltf["meshes"][0]["primitives"][0]
        position = gltf["accessors"][primitive["attributes"]["POSITION"]]
        indices = gltf["accessors"][primitive["indices"]]
        self.assertEqual(position["count"], 4)
        self.assertEqual(position["type"], "VEC3")
        self.assertEqual(indices["count"], 6)

    def test_바운딩박스가_들어간다(self):
        write_glb(self.path, {"chunk_0_0": {"road": square()}})
        *_rest, gltf = read_glb(self.path)
        position = gltf["accessors"][
            gltf["meshes"][0]["primitives"][0]["attributes"]["POSITION"]]
        self.assertEqual(position["min"], [0.0, 0.0, 0.0])
        self.assertEqual(position["max"], [1.0, 0.0, 1.0])


if __name__ == "__main__":
    unittest.main()
