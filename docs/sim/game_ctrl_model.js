// Reproduce game_ctrl.sv tube/collision logic to verify assumptions
const W = 12;
const wrap = v => ((v % (1 << W)) + (1 << W)) % (1 << W);

let x = [1600, 1600, 1600, 1600, 700];
let h = [0, 0, 0, 0, 100];
let cnt = 1;
let tubeHs = [];

const inWindow = x => x > 128 && x < 216;   // tube body overlaps bird [128,160)
let overlap = x => x - 56 < 160 && x > 128;

for (let f = 0; f < 2000; f++) {
  if (x[4] >= 512) {
    for (let i = 0; i < 5; i++) x[i] = wrap(x[i] - 1);
  } else {
    cnt = (cnt + 1) & 0xF;
    const nh = 100 + (((cnt & 8) ? 7 - cnt : cnt) << 4);   // 32-bit then truncate to 12 bits
    tubeHs.push({ cnt, raw: nh, h12: wrap(nh) });
    const ox = x.slice(), oh = h.slice();
    x[4] = 640; h[4] = wrap(nh);
    x[3] = ox[4]; h[3] = oh[4];
    x[2] = ox[3]; h[2] = oh[3];
    x[1] = ox[2]; h[1] = oh[2];
    x[0] = ox[1]; h[0] = oh[1];
  }
  const hits = [];
  for (let i = 0; i < 5; i++) if (overlap(x[i])) hits.push(i);
  if (hits.length > 1) console.log(`frame ${f}: MULTIPLE tubes overlap: ${hits}`);
  if (hits.length === 1 && hits[0] !== 1) {
    console.log(`frame ${f}: tube${hits[0]}_x=${x[hits[0]]} overlaps bird but check watches tube1_x=${x[1]} (h${hits[0]}=${h[hits[0]]} vs h1=${h[1]})`);
  }
}

console.log('\n--- tube height generated per cnt ---');
for (const t of tubeHs.slice(0, 16)) console.log(`cnt=${t.cnt.toString().padStart(2)} raw=${String(t.raw).padStart(5)} -> 12bit=${t.h12}`);

console.log('\n--- bird_loc_y underflow (jump = -20) ---');
for (let y of [240, 30, 21, 20, 11, 5]) console.log(`y=${y} -> jump -> ${wrap(y - 20)}`);
