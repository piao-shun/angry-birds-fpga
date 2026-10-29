const W = 12;
const wrap = v => ((v % (1 << W)) + (1 << W)) % (1 << W);
let x = [1600, 1600, 1600, 1600, 700];
let h = [0, 0, 0, 0, 100];
let cnt = 1;
const overlap = x => x - 56 < 160 && x > 128;
let framesWithOverlap = 0, mismatch = [], multi = [], seen = new Set();
for (let f = 0; f < 4000; f++) {
  if (x[4] >= 512) { for (let i = 0; i < 5; i++) x[i] = wrap(x[i] - 1); }
  else {
    cnt = (cnt + 1) & 0xF;
    const nh = 100 + (((cnt & 8) ? 7 - cnt : cnt) << 4);
    const ox = x.slice(), oh = h.slice();
    x[4] = 640; h[4] = wrap(nh);
    x[3] = ox[4]; h[3] = oh[4];
    x[2] = ox[3]; h[2] = oh[3];
    x[1] = ox[2]; h[1] = oh[2];
    x[0] = ox[1]; h[0] = oh[1];
  }
  const hits = [0,1,2,3,4].filter(i => overlap(x[i]));
  if (hits.length) { framesWithOverlap++; seen.add(hits.join(',')); }
  if (hits.length > 1 && multi.length < 5) multi.push(`frame ${f}: ${hits.map(i=>'tube'+i+'@'+x[i]).join(' ')}`);
  if (hits.length === 1 && hits[0] !== 1 && mismatch.length < 8)
    mismatch.push(`frame ${f}: on-screen tube${hits[0]}_x=${x[hits[0]]} h=${h[hits[0]]}, but code checks tube1_x=${x[1]} h=${h[1]}`);
}
console.log('frames with a tube at the bird:', framesWithOverlap, 'of 4000');
console.log('which tube index occupies the bird window:', [...seen]);
console.log('mismatch (checked tube != drawn tube):', mismatch.length);
mismatch.forEach(m => console.log('  ' + m));
console.log('multiple tubes overlapping bird:'); multi.forEach(m => console.log('  ' + m));
