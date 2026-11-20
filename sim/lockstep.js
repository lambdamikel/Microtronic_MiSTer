// Lockstep test, browser-emulator side: the same checkpoints as tb_lockstep.cpp.
const m = new Microtronic(romFromBase64(MICROTRONIC_ROM_B64));
let steps = 0, h = 2166136261;
const fnv = (x, v) => Math.imul((x ^ (v & 255)) >>> 0, 16777619) >>> 0;
const hex = v => v.toString(16).padStart(8, '0');
const rval = () => { let v = 0; for (let i = 0; i < 16; i++) v |= m.R[i] << i; return v; };
function step() {
  m.step(); steps++;
  const r = rval();
  for (const v of [m.pc, m.pa, m.pb, m.ca, m.cb, m.x, m.y, m.a, m.s, m.sl, m.o, r & 255, r >> 8]) h = fnv(h, v);
}
function check() {
  let hr = 2166136261, hs = 2166136261;
  for (let i = 0; i < 128; i++) hr = fnv(hr, m.ram[i]);
  for (let i = 0; i < 1024; i++) hs = fnv(hs, m.sram[i]);
  console.log(`chk ${steps} ${hex(h)} ${hex(hr)} ${hex(hs)}`);
}
const KEYS = { '0':[0,0],'1':[1,0],'2':[2,0],'3':[3,0],CCE:[4,0],PGM:[5,0],'4':[0,1],'5':[1,1],'6':[2,1],'7':[3,1],RUN:[4,1],HALT:[5,1],
  '8':[0,2],'9':[1,2],A:[2,2],B:[3,2],BKP:[4,2],STEP:[5,2],C:[0,3],D:[1,3],E:[2,3],F:[3,3],NEXT:[4,3],REG:[5,3] };
for (const line of SCENARIO.split('\n')) {
  const w = line.trim().split(/\s+/), op = w[0];
  if (op === 'run') { const n = +w[1], every = +(w[2] || 0); for (let i = 0; i < n; i++) { step(); if (every && steps % every === 0) check(); } }
  else if (op === 'down') m.keyDown(w[1]);
  else if (op === 'up') m.keyUp(w[1]);
  else if (op === 'din') m.din = +w[1];
  else if (op === 'clock') m.clockInput = +w[1] - 1;
  else if (op === 'patch') m.patches.push([+w[1], +w[2]]);
  else if (op === 'unpatch') m.patches = [];
  else if (op === 'load') { let a = parseInt(w[1], 16); for (const x of w.slice(2)) m.writeWord(a++, parseInt(x, 16)); }
  else if (op === 'reset') m.reset(false);
  else if (op === 'check') check();
}
check();
