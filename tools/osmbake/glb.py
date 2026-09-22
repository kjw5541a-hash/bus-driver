"""glTF 2.0 바이너리(.glb) writer.

POSITION, NORMAL, 인덱스만 필요해서 직접 쓴다. 서드파티 glTF 라이브러리를
들이는 것보다 싸고, 형식이 틀리면 Godot 임포트 검증에서 걸린다.
"""
import json
import struct
from pathlib import Path

from .mesh import MeshBuilder

GLB_MAGIC = 0x46546C67
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942
FLOAT = 5126
UNSIGNED_INT = 5125
ARRAY_BUFFER = 34962
ELEMENT_ARRAY_BUFFER = 34963


def _pad4(buffer: bytearray, filler: bytes = b"\x00") -> None:
    while len(buffer) % 4:
        buffer += filler


def write_glb(path: Path, chunks: dict[str, dict[str, MeshBuilder]]) -> None:
    binary = bytearray()
    buffer_views: list[dict] = []
    accessors: list[dict] = []
    meshes: list[dict] = []
    nodes: list[dict] = []

    def add_view(data: bytes, target: int) -> int:
        _pad4(binary)
        offset = len(binary)
        binary.extend(data)
        buffer_views.append({"buffer": 0, "byteOffset": offset,
                             "byteLength": len(data), "target": target})
        return len(buffer_views) - 1

    def add_vec3(values) -> int:
        data = b"".join(struct.pack("<fff", *v) for v in values)
        view = add_view(data, ARRAY_BUFFER)
        xs = [v[0] for v in values]
        ys = [v[1] for v in values]
        zs = [v[2] for v in values]
        accessors.append({
            "bufferView": view, "componentType": FLOAT, "count": len(values),
            "type": "VEC3",
            "min": [min(xs), min(ys), min(zs)],
            "max": [max(xs), max(ys), max(zs)],
        })
        return len(accessors) - 1

    def add_indices(values) -> int:
        data = struct.pack(f"<{len(values)}I", *values)
        view = add_view(data, ELEMENT_ARRAY_BUFFER)
        accessors.append({"bufferView": view, "componentType": UNSIGNED_INT,
                          "count": len(values), "type": "SCALAR"})
        return len(accessors) - 1

    for chunk_name in sorted(chunks):
        primitives = []
        for surface_name, builder in sorted(chunks[chunk_name].items()):
            if not builder.indices:
                continue
            primitives.append({
                "attributes": {
                    "POSITION": add_vec3(builder.positions),
                    "NORMAL": add_vec3(builder.normals),
                },
                "indices": add_indices(builder.indices),
                "material": 0 if surface_name == "road" else 1,
            })
        if not primitives:
            continue
        meshes.append({"name": chunk_name, "primitives": primitives})
        nodes.append({"name": chunk_name, "mesh": len(meshes) - 1})

    _pad4(binary)
    gltf = {
        "asset": {"version": "2.0", "generator": "bus-driver osmbake"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": meshes,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(binary)}],
        "materials": [
            {"name": "road",
             "pbrMetallicRoughness": {"baseColorFactor": [0.22, 0.22, 0.24, 1.0],
                                      "metallicFactor": 0.0,
                                      "roughnessFactor": 0.95}},
            {"name": "building",
             "pbrMetallicRoughness": {"baseColorFactor": [0.72, 0.68, 0.62, 1.0],
                                      "metallicFactor": 0.0,
                                      "roughnessFactor": 0.85}},
        ],
    }

    json_bytes = bytearray(json.dumps(gltf, ensure_ascii=False).encode("utf-8"))
    _pad4(json_bytes, b" ")

    total = 12 + 8 + len(json_bytes) + 8 + len(binary)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        handle.write(struct.pack("<III", GLB_MAGIC, 2, total))
        handle.write(struct.pack("<II", len(json_bytes), JSON_CHUNK))
        handle.write(json_bytes)
        handle.write(struct.pack("<II", len(binary), BIN_CHUNK))
        handle.write(binary)
