// 生成したGLBをそのまま読み、スマホ向けの上限と描画側が参照する名前を点検する。
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

function inspect(name, maxBytes, maxTris) {
  const file = readFileSync(new URL(`../assets/models/${name}.glb`, import.meta.url));
  assert.equal(file.toString('ascii', 0, 4), 'glTF');
  assert.equal(file.readUInt32LE(8), file.length);
  const gltf = JSON.parse(file.toString('utf8', 20, 20 + file.readUInt32LE(12)));
  const tris = gltf.meshes.flatMap(mesh => mesh.primitives).reduce((sum, p) => {
    assert.equal(p.mode ?? 4, 4);
    return sum + gltf.accessors[p.indices].count / 3;
  }, 0);
  assert.ok(file.length <= maxBytes && tris <= maxTris, name + ' exceeds budget');
  assert.equal(gltf.images?.length ?? 0, 0);
  console.log(`${name}: ${tris} triangles, ${file.length} bytes`);
  return gltf;
}

const boat = inspect('boat', 1_200_000, 25_000);
const venue = inspect('venue', 6_000_000, 350_000);
for (const name of ['Wheel', 'Motor', 'RacerUpper', 'Flag']) {
  assert.equal(boat.nodes.filter(n => n.name === name).length, 1, name);
}
for (const name of ['BoatColor', 'Suit', 'Helmet', 'HelmetStripe', 'Rubber', 'Visor', 'NumberPlate', 'Flag']) {
  assert.ok(boat.materials.some(m => m.name === name), name);
}
for (const model of [boat, venue]) {
  for (const mesh of model.meshes) {
    for (const p of mesh.primitives) {
      const material = model.materials[p.material].name;
      if ((model === venue && ['Glass', 'Lamp'].includes(material)) ||
          (model === boat && ['NumberPlate', 'Flag'].includes(material))) {
        assert.ok('TEXCOORD_0' in p.attributes, mesh.name + ' needs UVs');
      }
      if (model === venue || !['Glass', 'Flag'].includes(mesh.name)) {
        assert.ok('COLOR_0' in p.attributes, mesh.name + ' needs baked shading');
      }
    }
  }
}
for (const name of ['Glass', 'Lamp']) assert.ok(venue.materials.some(m => m.name === name), name);
const hull = boat.meshes.find(m => m.name === 'Hull');
const bounds = hull.primitives.map(p => boat.accessors[p.attributes.POSITION]);
const size = axis => Math.max(...bounds.map(a => a.max[axis])) - Math.min(...bounds.map(a => a.min[axis]));
assert.ok(Math.abs(size(0) - 2.90) < 0.02 && Math.abs(size(2) - 1.34) < 0.02, 'hull dimensions');
