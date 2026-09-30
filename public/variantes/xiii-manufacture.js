/* ==========================================================================
   Endry SA — Maquette XIII « Manufacture »
   Guilloché procédural (WebGL), intro « remontage », complications épinglées,
   fond saphir, vitrine à diaphragme, mouvement mécanique, loupe d’horloger.
   ========================================================================== */
(() => {
  'use strict';

  const root = document.documentElement;
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const fine = matchMedia('(hover: hover) and (pointer: fine)').matches;
  const $ = (s, c = document) => c.querySelector(s);
  const $$ = (s, c = document) => [...c.querySelectorAll(s)];
  const lib = window.gsap && window.ScrollTrigger;
  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));

  /* ------------------------------------------------------------------------
     Motifs horlogers générés à l’exécution (cadran des complications,
     mouvement, mini-cadrans) : allège le HTML de ~180 Ko de tracés SVG.
     Sans JS, ces éléments purement décoratifs sont masqués par le CSS.
     ------------------------------------------------------------------------ */
  (() => {
    const f = n => +n.toFixed(2);
    const rad = d => d * Math.PI / 180;
    // point à l'angle a (degrés, 0 = midi, sens horaire)
    const P = (cx, cy, r, a) => [f(cx + r * Math.sin(rad(a))), f(cy - r * Math.cos(rad(a)))];
    const ticks = (cx, cy, r1, r2, n, skip = () => false) => {
      let d = '';
      for (let i = 0; i < n; i++) { if (skip(i)) continue; const a = 360 * i / n; const [x1, y1] = P(cx, cy, r1, a), [x2, y2] = P(cx, cy, r2, a); d += `M${x1} ${y1}L${x2} ${y2}`; }
      return d;
    };
    const ROMAN = ['XII', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI'];
    const circ = (cx, cy, r, extra = '') => `<circle cx="${cx}" cy="${cy}" r="${r}"${extra}/>`;

    // ---------- Engrenages ----------
    function gear(cx, cy, N, m, {spokes = 5, hub = .22, rim = .78, pinion = 0} = {}) {
      const r = m * N / 2, ra = r + m * .9, rr = r - m * 1.15, step = 360 / N;
      let d = '';
      for (let i = 0; i < N; i++) {
        const a = i * step;
        const pts = [[rr, a - step * .5], [rr, a - step * .26], [r, a - step * .2], [ra, a - step * .12], [ra, a + step * .12], [r, a + step * .2], [rr, a + step * .26]];
        pts.forEach(([rad_, ang], j) => { const [x, y] = P(0, 0, rad_, ang); d += (i === 0 && j === 0 ? 'M' : 'L') + x + ' ' + y; });
      }
      d += 'Z';
      const rimR = rr * rim, hubR = Math.max(rr * hub, 6);
      let sp = '';
      const w = Math.max(3, rr * .09);
      for (let i = 0; i < spokes; i++) {
        const a = i * 360 / spokes;
        const dh = Math.asin(Math.min(.9, w / hubR)) * 180 / Math.PI, dr = Math.asin(w / rimR) * 180 / Math.PI;
        const [x1, y1] = P(0, 0, hubR, a - dh), [x2, y2] = P(0, 0, rimR, a - dr), [x3, y3] = P(0, 0, rimR, a + dr), [x4, y4] = P(0, 0, hubR, a + dh);
        sp += `M${x1} ${y1}L${x2} ${y2}A${f(rimR)} ${f(rimR)} 0 0 1 ${x3} ${y3}L${x4} ${y4}A${f(hubR)} ${f(hubR)} 0 0 0 ${x1} ${y1}Z`;
      }
      let pin = '';
      if (pinion) {
        const pr = m * .55 * pinion / 2 + 2, pa = pr + 2.2, prr = pr - 2.6, ps = 360 / pinion;
        let pd = '';
        for (let i = 0; i < pinion; i++) { const a = i * ps; [[prr, a - ps * .5], [prr, a - ps * .22], [pa, a - ps * .1], [pa, a + ps * .1], [prr, a + ps * .22]].forEach(([q, g], j) => { const [x, y] = P(0, 0, q, g); pd += (i === 0 && j === 0 ? 'M' : 'L') + x + ' ' + y; }); }
        pin = `<path class="g-pinion" d="${pd}Z"/>`;
      }
      return {r, svg: `<g class="gear" data-n="${N}" transform="translate(${f(cx)} ${f(cy)})"><g class="gear-rot"><path class="g-teeth" d="${d}"/><path class="g-spokes" d="${sp}"/>${circ(0, 0, f(rimR * .96), ' class="g-ring"')}${pin}${circ(0, 0, f(hubR * .6), ' class="g-hub"')}</g><g class="jewel">${circ(0, 0, 7.5, ' class="j-set"')}${circ(0, 0, 3.6, ' class="j-stone"')}</g></g>`};
    }
    function escapeWheel(cx, cy, N, r) {
      let d = '';
      const step = 360 / N;
      for (let i = 0; i < N; i++) {
        const a = i * step;
        const pts = [[r * .78, a], [r * .98, a + step * .18], [r * 1.02, a + step * .32], [r * .9, a + step * .38], [r * .78, a + step * .5]];
        pts.forEach(([q, g], j) => { const [x, y] = P(0, 0, q, g); d += (i === 0 && j === 0 ? 'M' : 'L') + x + ' ' + y; });
      }
      let sp = '';
      for (let i = 0; i < 4; i++) { const a = i * 90; const [x1, y1] = P(0, 0, 8, a), [x2, y2] = P(0, 0, r * .74, a); sp += `M${x1} ${y1}L${x2} ${y2}`; }
      return `<g class="gear gear-escape" data-n="${N}" transform="translate(${f(cx)} ${f(cy)})"><g class="gear-rot"><path class="g-teeth" d="${d}Z"/>${circ(0, 0, f(r * .74), ' class="g-ring"')}<path class="g-spokes" d="${sp}"/></g><g class="jewel">${circ(0, 0, 6.5, ' class="j-set"')}${circ(0, 0, 3, ' class="j-stone"')}</g></g>`;
    }
    function balance(cx, cy, r) {
      let spiral = '';
      for (let t = 0; t <= 14 * Math.PI; t += .12) { const q = 7 + t * (r * .55) / (14 * Math.PI); const x = f(Math.cos(t) * q), y = f(Math.sin(t) * q); spiral += (t === 0 ? 'M' : 'L') + x + ' ' + y; }
      let screws = '';
      for (let i = 0; i < 12; i++) { const [x, y] = P(0, 0, r + 4, i * 30 + 15); screws += circ(x, y, 3.2, ' class="b-screw"'); }
      const arms = [0, 120, 240].map(a => { const [x1, y1] = P(0, 0, 10, a), [x2, y2] = P(0, 0, r - 5, a); return `M${x1} ${y1}L${x2} ${y2}`; }).join('');
      return `<g class="balance" transform="translate(${cx} ${cy})"><path class="b-spring" d="${spiral}"/><g class="balance-rot">${circ(0, 0, r, ' class="b-rim"')}${circ(0, 0, r - 6, ' class="b-rim b-rim--in"')}<path class="b-arms" d="${arms}"/>${screws}</g><g class="jewel">${circ(0, 0, 8, ' class="j-set"')}${circ(0, 0, 3.8, ' class="j-stone"')}</g></g>`;
    }
    function screw(x, y, a = 30) { const [x1, y1] = P(x, y, 5.5, a), [x2, y2] = P(x, y, 5.5, a + 180); return `<g class="screw">${circ(x, y, 8)}<path d="M${x1} ${y1}L${x2} ${y2}"/></g>`; }

    // ---------- Cadran des trois complications (800, centre 400) ----------
    function complicationDial() {
      const c = 400;
      const names = ['SANITAIRE', 'CHAUFFAGE', 'VENTILATION'], nums = ['I', 'II', 'III'];
      // motifs guillochés des plaques centrales
      let eau = '';
      for (let i = 0; i < 26; i++) eau += circ(c, c, f(22 + i * 9.6));
      let feu = '';
      for (let i = 0; i < 144; i++) { const a = i * 2.5; let d = ''; for (let k = 0; k <= 24; k++) { const q = 30 + k * 10.5; const w = a + 3.2 * Math.sin(k * .7); const [x, y] = P(c, c, q, w); d += (k ? 'L' : 'M') + x + ' ' + y; } feu += `<path d="${d}"/>`; }
      let air = '';
      for (let j = 0; j < 3; j++) { let d = ''; for (let t = 0; t <= 16 * Math.PI; t += .08) { const q = 14 + t * 4.95; const [x, y] = P(c, c, q, t * 180 / Math.PI + j * 120); d += (t ? 'L' : 'M') + x + ' ' + y; } air += `<path d="${d}"/>`; }
      let rose = '';
      for (let i = 0; i < 48; i++) { const [x, y] = P(c, c, 80, i * 7.5); rose += circ(x, y, 80); }
      let disc = '';
      nums.forEach((n, i) => {
        const a = i * 120; const [x, y] = P(c, c, 330, a);
        disc += `<g class="disc-sector" transform="rotate(${a} ${c} ${c})"><text class="disc-num" x="${c}" y="${c - 318}" text-anchor="middle">${n}</text></g>`;
        disc += `<text class="disc-name"><textPath href="#disc-arc-${i}" startOffset="50%" text-anchor="middle">${names[i]}</textPath></text>`;
      });
      let arcs = '';
      [0, 120, 240].forEach((a, i) => { arcs += `<path id="disc-arc-${i}" d="M${P(c, c, 336, a + 14).join(' ')}A336 336 0 0 1 ${P(c, c, 336, a + 106).join(' ')}"/>`; });
      let diamonds = '';
      [60, 180, 300].forEach(a => { const [x, y] = P(c, c, 322, a); diamonds += `<path d="M${x} ${y - 6}l5 6-5 6-5-6z"/>`; });
      return `<svg class="cx-dial" viewBox="0 0 800 800" aria-hidden="true" focusable="false">
      <defs>${arcs}<clipPath id="cx-plate"><circle cx="${c}" cy="${c}" r="286"/></clipPath></defs>
      <g fill="none" stroke="currentColor">
        ${circ(c, c, 398, ' stroke-width="1.2"')}${circ(c, c, 392, ' stroke-width=".4"')}
        <path stroke-width=".35" d="${ticks(c, c, 378, 388, 240, i => i % 4 === 0)}"/>
        <path stroke-width=".9" d="${ticks(c, c, 372, 388, 60)}"/>
        ${circ(c, c, 368, ' stroke-width=".5"')}
      </g>
      <g class="cx-disc">
        <g fill="none" stroke="currentColor">${circ(c, c, 360, ' stroke-width=".6"')}${circ(c, c, 296, ' stroke-width=".6"')}${circ(c, c, 302, ' stroke-width=".3"')}
          <path stroke-width=".3" d="${ticks(c, c, 352, 358, 180)}"/></g>
        <g class="disc-text" fill="currentColor">${disc}</g>
      </g>
      <path class="cx-index" d="M${c} 364l-9 -22h18z" fill="currentColor"/>
      <g clip-path="url(#cx-plate)" fill="none" stroke="currentColor" stroke-width=".45">
        <g class="cx-motif cx-motif--1">${eau}</g>
        <g class="cx-motif cx-motif--2">${feu}</g>
        <g class="cx-motif cx-motif--3">${air}</g>
        <g class="cx-rose" stroke-width=".3">${rose}</g>
      </g>
      ${circ(c, c, 286, ' fill="none" stroke="currentColor" stroke-width=".8"')}
      <g class="cx-hand">
        <path d="M${c} ${c + 60}V${c - 262}" stroke="currentColor" stroke-width="1.6"/>
        <path d="M${c} ${c - 282}l-6 18 6 8 6-8z" fill="currentColor"/>
        <circle cx="${c}" cy="${c + 72}" r="12" fill="none" stroke="currentColor" stroke-width="1.6"/>
      </g>
      ${circ(c, c, 11, ' fill="currentColor"')}${circ(c, c, 4, ' fill="var(--pearl)"')}
    </svg>`;
    }

    // ---------- Mouvement mécanique (800, centre 400) ----------
    function movement() {
      const c = 400, m = 3.2;
      const cA = [285, 285], rA = m * 84 / 2;
      const A = gear(cA[0], cA[1], 84, m, {spokes: 6, hub: .34, rim: .88});
      const rB = m * 64 / 2, cB = P(cA[0], cA[1], rA + rB, 120);
      const B = gear(cB[0], cB[1], 64, m, {spokes: 5, pinion: 10});
      const rC = m * 48 / 2, cC = P(cB[0], cB[1], rB + rC, 190);
      const C = gear(cC[0], cC[1], 48, m, {spokes: 4, pinion: 8});
      const rD = m * 36 / 2, cD = P(cC[0], cC[1], rC + rD, 250);
      const D = gear(cD[0], cD[1], 36, m, {spokes: 4, pinion: 8});
      const rE = 34, cE = P(cD[0], cD[1], rD + rE + 2, 232);
      const E = escapeWheel(cE[0], cE[1], 20, rE);
      // rochet (sur le barillet) et roue de couronne
      const rR = 86, cK = P(cA[0], cA[1], rR + 58, 58);
      const K = gear(cK[0], cK[1], 36, 3.2, {spokes: 0, hub: .5});
      let ratchet = '';
      for (let i = 0; i < 48; i++) { const a = i * 360 / 48; const [x1, y1] = P(0, 0, rR - 9, a), [x2, y2] = P(0, 0, rR + 1, a + 6), [x3, y3] = P(0, 0, rR - 9, a + 360 / 48); ratchet += (i ? 'L' : 'M') + x1 + ' ' + y1 + 'L' + x2 + ' ' + y2 + 'L' + x3 + ' ' + y3; }
      const cBal = [172, 548];
      const bal = balance(cBal[0], cBal[1], 80);
      let perl = '';
      for (let y = 30; y < 790; y += 24) for (let x = 30 + ((y / 24) % 2) * 12; x < 790; x += 24) { if (Math.hypot(x - c, y - c) < 376) perl += circ(x, y, 14); }
      // ponts : tracés épais (contour = double trait)
      const bridges = [
        {d: `M${cA.join(' ')}L${cK.join(' ')}L${P(c, c, 330, 40).join(' ')}`, w: 50},
        {d: `M${P(c, c, 360, 100).join(' ')}Q${P(c, c, 250, 110).join(' ')} ${cB.join(' ')}Q${f((cB[0] + cC[0]) / 2 + 40)} ${f((cB[1] + cC[1]) / 2)} ${cC.join(' ')}L${cD.join(' ')}`, w: 32},
        {d: `M${P(c, c, 372, 232).join(' ')}Q${f(cBal[0] - 40)} ${f(cBal[1] + 90)} ${cBal.join(' ')}`, w: 26},
      ];
      const bridgeSvg = bridges.map(b => `<path class="mv-bridge-o" d="${b.d}" stroke-width="${b.w + 2}"/><path class="mv-bridge" d="${b.d}" stroke-width="${b.w}"/><path class="mv-bridge-c" d="${b.d}" stroke-width="${b.w - 8}"/>`).join('');
      const jewel = (p, r = 8.5) => `<g class="jewel jewel--top">${circ(p[0], p[1], r, ' class="j-set"')}${circ(p[0], p[1], r * .48, ' class="j-stone"')}</g>`;
      return {
        svg: `<svg class="mv-svg" viewBox="0 0 800 800" aria-hidden="true" focusable="false">
      <defs>
        <clipPath id="mv-plate"><circle cx="${c}" cy="${c}" r="376"/></clipPath>
        <pattern id="mv-cotes" width="14" height="14" patternUnits="userSpaceOnUse" patternTransform="rotate(28)"><rect width="14" height="14" fill="#2c2319"/><rect width="7" height="14" fill="#3b2f22"/></pattern>
        <radialGradient id="mv-stone" cx=".35" cy=".35" r=".8"><stop offset="0" stop-color="#FFF3DA"/><stop offset=".45" stop-color="#F9DBA3"/><stop offset="1" stop-color="#9F722A"/></radialGradient>
      </defs>
      <g class="mv-plate">
        ${circ(c, c, 398, ' class="mv-case"')}${circ(c, c, 390, ' class="mv-case mv-case--thin"')}
        <path class="mv-ticks" d="${ticks(c, c, 378, 388, 120)}"/>
        <g class="mv-perlage" clip-path="url(#mv-plate)">${perl}</g>
        ${circ(c, c, 376, ' class="mv-case"')}
      </g>
      <g class="mv-train">
        <g class="mv-a">${A.svg}</g>
        <g class="mv-ratchet" transform="translate(${cA.join(' ')})"><g class="ratchet-rot"><path d="${ratchet}Z"/>${circ(0, 0, 60)}${circ(0, 0, 36)}<path d="M-36 0H36M0 -36V36"/></g></g>
        <g class="mv-k">${K.svg}</g>
        <g class="mv-b">${B.svg}</g>
        <g class="mv-c">${C.svg}</g>
        <g class="mv-d">${D.svg}</g>
        <g class="mv-e">${E}</g>
      </g>
      <g class="mv-bal">${bal}</g>
      <g class="mv-bridges">${bridgeSvg}
        ${screw(...P(c, c, 330, 40), 20)}${screw(...P(c, c, 360, 100), 70)}${screw(...P(c, c, 372, 232).map((v, i) => v + (i ? -14 : 12)), 140)}
      </g>
      <g class="mv-jewels">${[cA, cK, cB, cC, cD].map(p => jewel(p)).join('')}${jewel(cBal, 9)}</g>
    </svg>`, meta: {A: [...cA, 84], K: [...cK, 36], B: [...cB, 64], C: [...cC, 48], D: [...cD, 36], E: [...cE, 20], Bal: cBal}
      };
    }


    // ---------- Mini-cadrans (mobile / sans animation) ----------
    function mini(i) {
      const c = 100;
      let motif = '';
      if (i === 0) for (let k = 0; k < 16; k++) motif += circ(c, c, f(8 + k * 4.2));
      if (i === 1) for (let k = 0; k < 72; k++) { const a = k * 5; let d = ''; for (let j = 0; j <= 10; j++) { const q = 12 + j * 6; const [x, y] = P(c, c, q, a + 3 * Math.sin(j * .8)); d += (j ? 'L' : 'M') + x + ' ' + y; } motif += `<path d="${d}"/>`; }
      if (i === 2) { let d = ''; for (let t = 0; t <= 12 * Math.PI; t += .1) { const q = 6 + t * 1.75; const [x, y] = P(c, c, q, t * 180 / Math.PI); d += (t ? 'L' : 'M') + x + ' ' + y; } motif = `<path d="${d}"/>`; }
      return `<svg class="mini-dial" viewBox="0 0 200 200" aria-hidden="true" focusable="false">
      <g fill="none" stroke="currentColor">${circ(c, c, 98, ' stroke-width=".9"')}${circ(c, c, 93, ' stroke-width=".4"')}<path stroke-width=".4" d="${ticks(c, c, 84, 90, 60)}"/><path stroke-width="1.2" d="${ticks(c, c, 80, 90, 12)}"/>${circ(c, c, 76, ' stroke-width=".5"')}<g stroke-width=".35">${motif}</g></g>
      <text x="100" y="42" text-anchor="middle" class="mini-num" fill="currentColor">${['I', 'II', 'III'][i]}</text>
      ${circ(c, c, 4, ' fill="currentColor"')}
    </svg>`;
    }


    const make = {'cx-dial': complicationDial, 'movement': () => movement().svg, 'mini-0': () => mini(0), 'mini-1': () => mini(1), 'mini-2': () => mini(2)};
    document.querySelectorAll('[data-svg]').forEach(slot => { const fn = make[slot.dataset.svg]; if (fn) slot.outerHTML = fn(); });
  })();

  const endIntro = () => root.classList.remove('is-intro');
  if (!lib) { endIntro(); }

  /* ------------------------------------------------------------------------
     Heure de Bussy FR (Europe/Zurich)
     ------------------------------------------------------------------------ */
  let tzFmt = null;
  try { tzFmt = new Intl.DateTimeFormat('en-GB', {timeZone: 'Europe/Zurich', hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false}); } catch (e) { tzFmt = null; }
  function bussyTime() {
    const now = new Date();
    let h = now.getHours(), m = now.getMinutes(), s = now.getSeconds();
    if (tzFmt) {
      const p = {};
      tzFmt.formatToParts(now).forEach(x => { p[x.type] = x.value; });
      h = +p.hour % 24; m = +p.minute; s = +p.second;
    }
    return {h, m, s: s + now.getMilliseconds() / 1000};
  }
  const angles = t => ({h: (t.h % 12) * 30 + t.m * .5 + t.s / 120, m: t.m * 6 + t.s * .1, s: t.s * 6});

  const handH = $('.hand-h'), handM = $('.hand-m'), handS = $('.hand-s');
  const spin = {k: reduce ? 0 : -1};
  function setHands() {
    const a = angles(bussyTime());
    const k = spin.k;
    handH?.setAttribute('transform', `rotate(${(a.h + k * a.h).toFixed(3)} 500 500)`);
    handM?.setAttribute('transform', `rotate(${(a.m + k * (a.m + 360)).toFixed(3)} 500 500)`);
    handS?.setAttribute('transform', `rotate(${(a.s + k * (a.s + 720)).toFixed(3)} 500 500)`);
  }
  setHands();

  const fcH = $('.fc-h'), fcM = $('.fc-m'), fcS = $('.fc-s'), fcTime = $('.fc-time');
  function setFooterClock() {
    const t = bussyTime(), a = angles(t);
    fcH?.setAttribute('transform', `rotate(${a.h.toFixed(2)} 60 60)`);
    fcM?.setAttribute('transform', `rotate(${a.m.toFixed(2)} 60 60)`);
    fcS?.setAttribute('transform', `rotate(${a.s.toFixed(2)} 60 60)`);
    if (fcTime) fcTime.textContent = String(t.h).padStart(2, '0') + ':' + String(t.m).padStart(2, '0');
  }
  setFooterClock();
  if (reduce) setInterval(setFooterClock, 30000);

  /* ------------------------------------------------------------------------
     Guilloché procédural — WebGL brut, un seul canevas déplacé d’hôte en hôte
     ------------------------------------------------------------------------ */
  const VERT = 'attribute vec2 p;void main(){gl_Position=vec4(p,0.,1.);}';
  const FRAG = `
precision highp float;
uniform vec2 uRes, uCenter, uLight;
uniform float uR, uTime, uRot, uSweep, uMode, uDpr, uZoom;
#define PI 3.14159265359
#define TAU 6.28318530718
mat2 rot(float a){float c=cos(a),s=sin(a);return mat2(c,s,-s,c);}
float hash(vec2 p){return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453);}
float aniso(vec2 t2, vec3 H, float e){float th=dot(vec3(t2,0.),H);return pow(sqrt(max(0.,1.-th*th)),e);}
void main(){
  vec2 frag=vec2(gl_FragCoord.x,uRes.y-gl_FragCoord.y);
  float R=uR*uZoom;
  vec2 d=(frag-uCenter)/R; d.y=-d.y;
  float px=1./R;
  vec2 lp=(uLight-frag)/R; lp.y=-lp.y;
  vec3 L=normalize(vec3(lp,.85));
  vec3 H=normalize(L+vec3(0.,0.,1.));
  vec3 nacre=vec3(.969,.949,.914);
  vec3 champ=vec3(.944,.906,.838);
  vec3 bronze=vec3(.624,.447,.165);
  vec3 gold=vec3(.976,.859,.639);
  vec3 col;
  if(uMode<.5){
    float r=length(d);
    vec2 rh=r>1e-4?d/r:vec2(0.,1.);
    vec2 th=vec2(-rh.y,rh.x);
    vec2 q=rot(uRot)*d;
    float a=atan(q.y,q.x);
    float phi=0.,dens=1e4,depth=.9,amt=1.,inter=1.;
    vec2 g=rh;
    if(r<.336){
      float F=150.,A=.85,P=16.;
      float w=A*sin(P*a+r*6.);
      phi=r*F+w;
      vec2 gr=F*rh+(A*P*cos(P*a+r*6.)/max(r,.035))*th;
      dens=length(gr);g=gr/dens;
      inter=.55+.45*cos(TAU*(r*F-w));
      amt=.8;
    }else if(r<.732){
      float N=360.,W=.55,K=44.;
      phi=a*N/TAU+W*sin(r*K);
      vec2 gr=(N/TAU)/r*th+W*K*cos(r*K)*rh;
      dens=length(gr);g=gr/dens;
      amt=.95;
    }else if(r<.964){
      phi=r*260.;dens=260.;g=rh;amt=.55;
    }else{
      phi=r*900.;dens=900.;g=rh;amt=.3;
    }
    float lpp=dens*px;
    float vis=1.-smoothstep(.2,.48,lpp);
    float s=sin(TAU*phi),c=cos(TAU*phi);
    vec3 N=normalize(vec3(g*s*depth*vis,1.));
    float diff=dot(N,L);
    vec2 tg=vec2(-g.y,g.x);
    float an=aniso(tg,H,120.),an2=aniso(tg,H,16.);
    vec3 dial=champ*(.86+.17*diff);
    dial=mix(dial,bronze,(.5-.5*c)*.11*vis*amt*inter);
    dial+=gold*an2*.05+vec3(1.,.96,.88)*an*.15;
    dial=mix(dial,dial*vec3(1.02,1.,.965),.5+.5*sin(a*2.+r*7.+uTime*.15));
    // bévels polis
    float b=0.;
    b=max(b,1.-smoothstep(.0022,.0022+px*1.5,abs(r-.336)));
    b=max(b,1.-smoothstep(.0016,.0016+px*1.5,abs(r-.732)));
    b=max(b,1.-smoothstep(.0016,.0016+px*1.5,abs(r-.744)));
    b=max(b,1.-smoothstep(.0026,.0026+px*1.5,abs(r-.964)));
    float lb=dot(rh,normalize(lp+1e-5));
    dial=mix(dial,mix(bronze*1.08,vec3(1.,.97,.9),.5+.5*lb),b*.6);
    // tracé du tour à guillocher (intro)
    float tt=fract(atan(d.x,d.y)/TAU+1.);
    float rev=uSweep>=.999?1.:1.-smoothstep(uSweep-.006,uSweep,tt);
    vec3 blank=champ*(.9+.12*L.z)+gold*aniso(th,H,24.)*.1;
    dial=mix(blank,dial,rev);
    dial+=gold*exp(-abs(tt-uSweep)*220.)*step(uSweep,.999)*.55*step(r,1.);
    // extérieur : nacre et rayons très fins
    float ao=a*720./TAU;
    float od=(720./TAU)/max(r,.2);
    float ov=(1.-smoothstep(.2,.45,od*px))*(1.-smoothstep(1.,1.9,r));
    float os=sin(TAU*ao);
    vec3 NO=normalize(vec3(th*os*.5*ov,1.));
    vec3 outer=nacre*(.955+.05*dot(NO,L))+gold*aniso(rh,H,40.)*.05*ov;
    outer*=1.-.07*exp(-(r-1.)*26.);
    col=mix(dial,outer,smoothstep(1.-px,1.+px,r));
  }else{
    vec2 pp=d*R;
    vec2 q=rot(.785398)*pp/(30.*uDpr);
    vec2 f=fract(q)-.5;
    float ew=1.2/(30.*uDpr);
    float w=smoothstep(-ew,ew,abs(f.x)-abs(f.y));
    vec2 n2=mix(vec2(0.,sign(f.y)),vec2(sign(f.x),0.),w);
    n2=rot(-.785398)*n2;
    vec3 N=normalize(vec3(n2*.26,1.));
    float groove=smoothstep(.5-ew*1.6,.5,max(abs(f.x),abs(f.y)));
    float diff=dot(N,L);
    float sp=pow(max(dot(N,H),0.),90.);
    col=champ*(.88+.16*diff)+vec3(1.,.96,.88)*sp*.22;
    col=mix(col,bronze,groove*.12);
    float vg=length(d);
    col=mix(col,nacre,smoothstep(.2,1.4,vg)*.35);
  }
  col+=(hash(frag+uTime)-.5)/255.;
  gl_FragColor=vec4(col,1.);
}`;

  const GL = (() => {
    const hosts = $$('[data-gl-host]');
    if (!hosts.length) return null;
    const canvas = document.createElement('canvas');
    canvas.className = 'gl-canvas';
    canvas.setAttribute('aria-hidden', 'true');
    let gl = null;
    try { gl = canvas.getContext('webgl', {antialias: false, alpha: false, depth: false, stencil: false, powerPreference: 'high-performance', preserveDrawingBuffer: false}); } catch (e) { gl = null; }
    if (!gl) return null;
    const sh = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) { console.warn(gl.getShaderInfoLog(s)); return null; } return s; };
    const vs = sh(gl.VERTEX_SHADER, VERT), fs = sh(gl.FRAGMENT_SHADER, FRAG);
    if (!vs || !fs) return null;
    const prog = gl.createProgram();
    gl.attachShader(prog, vs); gl.attachShader(prog, fs); gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) return null;
    gl.useProgram(prog);
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(prog, 'p');
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
    const U = {};
    ['uRes', 'uCenter', 'uLight', 'uR', 'uTime', 'uRot', 'uSweep', 'uMode', 'uDpr', 'uZoom'].forEach(n => { U[n] = gl.getUniformLocation(prog, n); });

    const state = {sweep: reduce ? 1 : 0, zoom: reduce ? 1 : .56, rot: 0, scrollRot: 0};
    const dialWrap = $('.dial-wrap'), cert = $('.certificate');
    let host = null, mode = 0, dpr = 1, W = 0, H = 0, running = false, visible = new Set(), lost = false;
    const light = {x: 0, y: 0, tx: 0, ty: 0, init: false};
    const pointer = {x: -1, y: -1, has: false};
    const t0 = performance.now();

    function place(h) {
      if (host === h) return;
      host = h;
      mode = h.dataset.glHost === 'clous' ? 1 : 0;
      h.prepend(canvas);
      resize();
    }
    function resize() {
      if (!host) return;
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      W = Math.max(1, Math.round(host.clientWidth * dpr));
      H = Math.max(1, Math.round(host.clientHeight * dpr));
      if (canvas.width !== W || canvas.height !== H) { canvas.width = W; canvas.height = H; }
      gl.viewport(0, 0, W, H);
      light.init = false;
      if (!running) draw();
    }
    function geometry() {
      if (mode === 0 && dialWrap) return {cx: W / 2, cy: dialWrap.offsetTop * dpr, r: dialWrap.offsetWidth / 2 * dpr};
      if (cert) return {cx: (cert.offsetLeft + cert.offsetWidth / 2) * dpr, cy: (cert.offsetTop + cert.offsetHeight / 2) * dpr, r: Math.max(W, H) * .6};
      return {cx: W / 2, cy: H / 2, r: Math.max(W, H) * .5};
    }
    function draw() {
      if (!host || lost) return;
      const t = (performance.now() - t0) / 1000;
      const g = geometry();
      const rect = canvas.getBoundingClientRect();
      if (pointer.has && fine) {
        light.tx = (pointer.x - rect.left) * dpr;
        light.ty = (pointer.y - rect.top) * dpr;
      } else {
        const ang = t * .22 + state.scrollRot * 2.2;
        light.tx = g.cx + Math.cos(ang) * g.r * .9;
        light.ty = g.cy - Math.abs(Math.sin(ang)) * g.r * .7 - g.r * .2;
      }
      if (!light.init) { light.x = light.tx; light.y = light.ty; light.init = true; }
      light.x += (light.tx - light.x) * .08;
      light.y += (light.ty - light.y) * .08;
      gl.uniform2f(U.uRes, W, H);
      gl.uniform2f(U.uCenter, g.cx, g.cy);
      gl.uniform1f(U.uR, g.r);
      gl.uniform2f(U.uLight, light.x, light.y);
      gl.uniform1f(U.uTime, t);
      gl.uniform1f(U.uRot, state.rot + state.scrollRot + (reduce ? 0 : t * .012));
      gl.uniform1f(U.uSweep, mode === 0 ? state.sweep : 1);
      gl.uniform1f(U.uMode, mode);
      gl.uniform1f(U.uDpr, dpr);
      gl.uniform1f(U.uZoom, mode === 0 ? state.zoom : 1);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      if (!canvas.classList.contains('is-ready')) { canvas.classList.add('is-ready'); root.classList.add('has-gl'); }
    }
    function tick() { draw(); }
    function update() {
      const active = hosts.find(h => visible.has(h));
      const shouldRun = !!active && !document.hidden && !reduce && !lost;
      if (active) place(active);
      if (shouldRun && !running) { running = true; if (lib) gsap.ticker.add(tick); else loop(); }
      if (!shouldRun && running) { running = false; if (lib) gsap.ticker.remove(tick); }
      if (reduce && active) draw();
    }
    function loop() { if (!running) return; draw(); requestAnimationFrame(loop); }
    const io = new IntersectionObserver(es => { es.forEach(e => e.isIntersecting ? visible.add(e.target) : visible.delete(e.target)); update(); }, {rootMargin: '80px 0px'});
    hosts.forEach(h => io.observe(h));
    document.addEventListener('visibilitychange', update);
    const ro = new ResizeObserver(() => resize());
    hosts.forEach(h => ro.observe(h));
    addEventListener('pointermove', e => { if (e.pointerType === 'mouse') { pointer.x = e.clientX; pointer.y = e.clientY; pointer.has = true; } }, {passive: true});
    canvas.addEventListener('webglcontextlost', e => { e.preventDefault(); lost = true; root.classList.remove('has-gl'); canvas.classList.remove('is-ready'); update(); });
    place(hosts[0]);
    return {state, draw};
  })();

  /* ------------------------------------------------------------------------
     Sans GSAP ou mouvement réduit : on s’arrête ici (page statique complète)
     ------------------------------------------------------------------------ */
  if (!lib || reduce) {
    endIntro();
    if (GL) GL.draw();
    return;
  }

  gsap.registerPlugin(ScrollTrigger);
  if (window.SplitText) gsap.registerPlugin(SplitText);
  if (window.CustomEase) { gsap.registerPlugin(CustomEase); CustomEase.create('lux', '0.7,0,0.2,1'); }
  const LUX = window.CustomEase ? 'lux' : 'power3.inOut';
  root.classList.add('motion');

  /* ------------------------------------------------------------------------
     Lenis
     ------------------------------------------------------------------------ */
  let lenis = null;
  if (window.Lenis) {
    lenis = new Lenis({duration: 1.35, easing: t => 1 - Math.pow(1 - t, 4), smoothWheel: true, syncTouch: false});
    lenis.on('scroll', ScrollTrigger.update);
    gsap.ticker.add(t => lenis.raf(t * 1000));
    gsap.ticker.lagSmoothing(0);
  }
  const nav = $('#navigation');
  const lock = () => lenis && lenis.stop();
  const unlock = () => { if (!lenis) return; if (nav?.classList.contains('open') || $$('dialog[open]').length) return; lenis.start(); };
  if (nav) new MutationObserver(() => nav.classList.contains('open') ? lock() : unlock()).observe(nav, {attributes: true, attributeFilter: ['class']});
  $$('dialog').forEach(d => new MutationObserver(() => d.open ? lock() : unlock()).observe(d, {attributes: true, attributeFilter: ['open']}));

  // Ancres
  $$('a[href^="#"]').forEach(a => a.addEventListener('click', e => {
    const id = a.getAttribute('href');
    const target = id === '#' ? null : $(id);
    if (id !== '#' && !target) return;
    e.preventDefault();
    const go = () => {
      const off = target && target.id === 'depannage' ? -110 : 0;
      if (lenis) lenis.scrollTo(target || 0, {offset: off, duration: 1.8, easing: t => (t < .5 ? 16 * t ** 5 : 1 - Math.pow(-2 * t + 2, 5) / 2)});
      else (target || document.body).scrollIntoView({behavior: 'smooth'});
      if (target) { if (!target.hasAttribute('tabindex')) target.setAttribute('tabindex', '-1'); setTimeout(() => target.focus({preventScroll: true}), 900); }
      history.replaceState(null, '', id === '#' ? location.pathname : id);
    };
    // laisse site.js fermer le menu avant de défiler
    requestAnimationFrame(() => { unlock(); go(); });
  }));

  // En-tête qui se retire au défilement vers le bas
  const header = $('.header');
  let lastY = 0, upAcc = 0;
  const onScrollHeader = y => {
    if (!header) return;
    const dy = y - lastY;
    lastY = y;
    if (y < 80) { header.classList.remove('is-hidden'); upAcc = 0; return; }
    if (dy > 0) { upAcc = 0; if (y > window.innerHeight * .6 && !nav?.classList.contains('open')) header.classList.add('is-hidden'); return; }
    // n’affiche l’en-tête qu’au défilement volontaire vers le haut (pas pendant un aimantage)
    const user = !lenis || !fine || lenis.isScrolling === 'smooth';
    if (dy < 0 && user) { upAcc -= dy; if (upAcc > 50) header.classList.remove('is-hidden'); }
  };
  if (lenis) lenis.on('scroll', ({scroll}) => onScrollHeader(scroll)); else addEventListener('scroll', () => onScrollHeader(scrollY), {passive: true});
  header?.addEventListener('focusin', () => header.classList.remove('is-hidden'));

  /* ------------------------------------------------------------------------
     Outils : SplitText
     ------------------------------------------------------------------------ */
  function split(el, opts = {}) {
    if (!window.SplitText || !el) return null;
    return SplitText.create(el, Object.assign({type: 'lines,chars', mask: 'lines', linesClass: 'st-line', charsClass: 'st-char', aria: 'auto'}, opts));
  }

  /* ------------------------------------------------------------------------
     Intro : on remonte la couronne
     ------------------------------------------------------------------------ */
  const heroTitle = $('.hero-title');
  const dialWrap = $('.dial-wrap');
  const sweepArc = $('.sweep-arc');
  const knurl = $('.crown-knurl');
  const introItems = $$('.hero [data-intro]');
  const clockState = {run: true};
  gsap.ticker.add(() => { if (clockState.run) setHands(); });
  // l’aiguille des heures du héros n’avance que si le héros est visible
  new IntersectionObserver(es => { clockState.run = es[0].isIntersecting; }).observe($('.hero'));

  function runIntro() {
    let capsSplit = null, emEl = heroTitle ? $('.t-em', heroTitle) : null;
    if (heroTitle) {
      heroTitle.setAttribute('aria-label', heroTitle.textContent.replace(/\s+/g, ' ').trim());
      capsSplit = split($('.t-caps', heroTitle), {type: 'chars', mask: 'chars', aria: 'none', charsClass: 'st-char'});
      if (capsSplit) capsSplit.chars.forEach(c => c.setAttribute('aria-hidden', 'true'));
      if (emEl) emEl.setAttribute('aria-hidden', 'true');
    }
    gsap.set(header, {opacity: 0, y: -18});
    gsap.set(introItems, {opacity: 0, y: 22});
    gsap.set('.hands', {opacity: 0});
    gsap.set(dialWrap, {scale: .56});
    if (sweepArc) gsap.set(sweepArc, {strokeDashoffset: 1});
    if (capsSplit) gsap.set(capsSplit.chars, {yPercent: 118});
    if (emEl) gsap.set(emEl, {clipPath: 'inset(-10% 100% -25% -5%)'});
    endIntro();
    lock();

    const glState = GL ? GL.state : {sweep: 1, zoom: 1};
    const tl = gsap.timeline({defaults: {ease: LUX}, onComplete: () => {
      gsap.set([header, ...introItems], {clearProps: 'transform,opacity'});
      if (emEl) gsap.set(emEl, {clearProps: 'clipPath'});
      heroScroll();
    }});
    tl.to(knurl, {y: -28, duration: .85, ease: 'power1.inOut'}, 0)
      .to(sweepArc, {strokeDashoffset: 0, duration: .95, ease: 'power2.inOut'}, .05)
      .to(glState, {sweep: 1, duration: 1, ease: 'power2.inOut'}, .08)
      .to('.hands', {opacity: .38, duration: .3, ease: 'none'}, .35)
      .to(spin, {k: 0, duration: 1.05, ease: 'expo.inOut'}, .4)
      .to(glState, {zoom: 1, duration: 1.05, ease: 'expo.inOut'}, 1.0)
      .to(dialWrap, {scale: 1, duration: 1.05, ease: 'expo.inOut'}, 1.0)
      .add(() => unlock(), 1.5);
    if (capsSplit) tl.to(capsSplit.chars, {yPercent: 0, duration: 1.05, stagger: .04, ease: 'expo.out'}, 1.18);
    if (emEl) tl.to(emEl, {clipPath: 'inset(-10% -5% -25% -5%)', duration: 1.1, ease: LUX}, 1.45);
    tl.to(header, {opacity: 1, y: 0, duration: .9, ease: 'expo.out'}, 1.55)
      .to(introItems, {opacity: 1, y: 0, duration: .9, stagger: .06, ease: 'expo.out'}, 1.6);
  }

  function heroScroll() {
    const hero = $('.hero');
    gsap.timeline({scrollTrigger: {trigger: hero, start: 'top top', end: 'bottom top', scrub: .6}})
      .to('.hero-stage', {yPercent: 16, ease: 'none'}, 0)
      .to('.hero-content', {yPercent: -22, opacity: 0, ease: 'none'}, 0)
      .to('.hero-phone', {yPercent: -60, opacity: 0, ease: 'none'}, 0)
      .to('.ring-body', {rotation: -18, svgOrigin: '500 500', ease: 'none'}, 0)
      .to(GL ? GL.state : {}, {scrollRot: -.9, ease: 'none'}, 0);
  }

  /* ------------------------------------------------------------------------
     Titres : gravure (caractères masqués)
     ------------------------------------------------------------------------ */
  function headings() {
    $$('[data-split]').forEach(el => {
      const s = split(el);
      if (!s) return;
      gsap.set(s.chars, {yPercent: 118});
      ScrollTrigger.create({
        trigger: el, start: 'top 86%', once: true,
        onEnter: () => gsap.to(s.chars, {yPercent: 0, duration: 1.25, stagger: .022, ease: 'expo.out'})
      });
    });
  }

  /* ------------------------------------------------------------------------
     Fond saphir
     ------------------------------------------------------------------------ */
  function sapphire() {
    const sec = $('.sapphire');
    if (!sec) return;
    const win = $('.sp-window', sec), img = $('.sp-window img', sec), ring = $('.sp-ring', sec);
    const words = $$('.sp-line--a span', sec), lineB = $('.sp-line--b', sec), lineEm = $('.sp-line--b em', sec), scrim = $('.sp-scrim', sec);
    const r0 = () => win.offsetHeight ? parseFloat(getComputedStyle(ring).width) * .828 / 2 : 200;
    const r1 = () => Math.hypot(win.offsetWidth, win.offsetHeight) / 2 + 4;
    gsap.set(words, {yPercent: 40, opacity: 0});
    gsap.set(lineB, {y: 30, opacity: 0});
    ScrollTrigger.create({trigger: sec, start: 'top 70%', once: true, onEnter: () => {
      gsap.to(words, {yPercent: 0, opacity: 1, duration: 1.2, stagger: .12, ease: 'expo.out'});
      gsap.to(lineB, {y: 0, opacity: 1, duration: 1.2, delay: .3, ease: 'expo.out'});
    }});
    gsap.fromTo(ring, {rotation: -40}, {rotation: 0, ease: 'none', scrollTrigger: {trigger: sec, start: 'top bottom', end: 'top top', scrub: true}});
    const tl = gsap.timeline({scrollTrigger: {trigger: sec, start: 'top top', end: '+=150%', pin: true, scrub: .8, invalidateOnRefresh: true}});
    tl.fromTo(win, {clipPath: () => `circle(${r0()}px at 50% 50%)`}, {clipPath: () => `circle(${r1()}px at 50% 50%)`, ease: 'power2.in', duration: 1}, 0)
      .fromTo(img, {scale: 1.18}, {scale: 1, ease: 'none', duration: 1.2}, 0)
      .to(ring, {scale: () => r1() / r0(), opacity: 0, ease: 'power2.in', duration: 1}, 0)
      .to(words[0], {xPercent: -120, opacity: 0, ease: 'power2.in', duration: .7}, 0)
      .to(words[2], {xPercent: 120, opacity: 0, ease: 'power2.in', duration: .7}, 0)
      .to(words[1], {yPercent: -80, opacity: 0, ease: 'power2.in', duration: .7}, 0)
      .to(lineB, {y: 60, opacity: 0, ease: 'power2.in', duration: .45}, 0)
      // l’image est ouverte : la devise se pose sur l’ambiance, en or
      .set(lineB, {color: '#FBF8F2', textShadow: '0 2px 30px rgba(33,26,19,.45)'}, .5)
      .set(lineEm, {color: '#F9DBA3'}, .5)
      .to(scrim, {opacity: 1, ease: 'none', duration: .4}, .7)
      .to(lineB, {y: 0, opacity: 1, ease: 'expo.out', duration: .45}, .88)
      .to({}, {duration: .3});
  }

  /* ------------------------------------------------------------------------
     Territoire : la règle se grave
     ------------------------------------------------------------------------ */
  function territory() {
    const t = $('.territory');
    if (!t) return;
    gsap.from($$('.tr-cell, .tr-main', t), {opacity: 0, y: 18, duration: 1.2, stagger: .12, ease: 'expo.out', scrollTrigger: {trigger: t, start: 'top 85%', once: true}});
  }

  /* ------------------------------------------------------------------------
     Expertises : trois complications (épinglé, grand écran)
     ------------------------------------------------------------------------ */
  function expertisesPinned() {
    const sec = $('#expertises');
    const stage = $('.x-stage', sec), arts = $$('.metier', sec);
    const disc = $('.cx-disc', sec), hand = $('.cx-hand', sec), motifs = $$('.cx-motif', sec), rose = $('.cx-rose', sec);
    const cur = $('.x-cur', sec);
    sec.classList.add('is-pinned');
    arts.forEach(a => { a.removeAttribute('data-reveal'); a.classList.add('is-in'); });
    const parts = arts.map(a => {
      const h3 = $('h3', a);
      const s = split(h3, {type: 'words,chars', mask: 'chars'});
      return {el: a, chars: s ? s.chars : [h3], rest: $$('.metier-kicker, .metier-lead, .metier-text, .metier-list li, .text-link', a), split: s};
    });
    parts.forEach((p, i) => { if (i) { gsap.set(p.chars, {yPercent: 118}); gsap.set(p.rest, {opacity: 0, y: 40}); } });
    const setCurrent = i => { arts.forEach((a, j) => a.classList.toggle('is-current', j === i)); if (cur) cur.textContent = ['I', 'II', 'III'][i]; };
    setCurrent(0);
    const tl = gsap.timeline({defaults: {ease: 'none'}, scrollTrigger: {
      trigger: stage, start: 'top top', end: '+=260%', pin: true, scrub: .9,
      snap: {snapTo: [0, .5, 1], duration: {min: .4, max: .9}, delay: .12, inertia: false, ease: 'power2.inOut'},
      onUpdate: self => setCurrent(clamp(Math.round(self.progress * 2), 0, 2))
    }});
    tl.addLabel('m0', 0);
    [1, 2].forEach(i => {
      const at = i - 1;
      const prev = parts[i - 1], next = parts[i];
      tl.to(disc, {rotation: -120 * i, svgOrigin: '400 400', duration: 1, ease: 'power2.inOut'}, at)
        .to(hand, {rotation: 360 * i, svgOrigin: '400 400', duration: 1, ease: 'power2.inOut'}, at)
        .to(rose, {rotation: 60 * i, svgOrigin: '400 400', duration: 1, ease: 'power2.inOut'}, at)
        .to(motifs[i - 1], {opacity: 0, duration: .45}, at + .15)
        .to(motifs[i], {opacity: .75, duration: .45}, at + .45)
        .to(prev.chars, {yPercent: -118, duration: .35, stagger: .012, ease: 'power2.in'}, at + .1)
        .to(prev.rest, {opacity: 0, y: -30, duration: .3, stagger: .015, ease: 'power2.in'}, at + .08)
        .to(next.chars, {yPercent: 0, duration: .4, stagger: .014, ease: 'power3.out'}, at + .5)
        .to(next.rest, {opacity: 1, y: 0, duration: .35, stagger: .02, ease: 'power3.out'}, at + .55)
        .addLabel('m' + i, i);
    });
    // clavier : un lien masqué qui reçoit le focus fait avancer le cadran
    arts.forEach((a, i) => a.addEventListener('focusin', () => {
      const st = tl.scrollTrigger;
      if (!st) return;
      const y = st.start + (st.end - st.start) * (i / 2);
      if (Math.abs(window.scrollY - y) > 20) lenis ? lenis.scrollTo(y, {immediate: true}) : window.scrollTo(0, y);
    }));
    return () => {
      sec.classList.remove('is-pinned');
      parts.forEach(p => { p.split && p.split.revert(); gsap.set(p.rest, {clearProps: 'all'}); });
      arts.forEach(a => a.classList.remove('is-current'));
    };
  }

  /* ------------------------------------------------------------------------
     Dépannage : bulletin qui se pose, sceau qui se frappe
     ------------------------------------------------------------------------ */
  function certificate() {
    const cert = $('.certificate');
    if (!cert) return;
    gsap.fromTo(cert, {y: 120, rotateX: 14, transformPerspective: 1400, transformOrigin: '50% 100%', opacity: .2},
      {y: 0, rotateX: 0, opacity: 1, ease: 'none', scrollTrigger: {trigger: '.repair', start: 'top 95%', end: 'top 25%', scrub: .8}});
    const seal = $('.cert-seal', cert);
    gsap.fromTo(seal, {scale: 1.6, rotation: -40, opacity: 0}, {scale: 1, rotation: 0, opacity: 1, duration: 1, ease: 'back.out(1.6)',
      scrollTrigger: {trigger: cert, start: 'top 80%', once: true}});
    gsap.to($('.seal-text', cert), {rotation: 120, svgOrigin: '120 120', ease: 'none', scrollTrigger: {trigger: '.repair', start: 'top bottom', end: 'bottom top', scrub: true}});
    gsap.from($$('.cert-lines > div, .cert-actions > *', cert), {opacity: 0, y: 24, duration: 1, stagger: .08, ease: 'expo.out', scrollTrigger: {trigger: $('.cert-lines', cert), start: 'top 88%', once: true}});
  }

  /* ------------------------------------------------------------------------
     L’esprit : boîtier coussin qui s’ouvre, parallaxe
     ------------------------------------------------------------------------ */
  function approach() {
    const cs = $('.ap-case'), img = $('.ap-case img');
    if (!cs) return;
    gsap.fromTo(cs, {clipPath: 'inset(22% 18% 22% 18% round 50%)'}, {clipPath: 'inset(0% 0% 0% 0% round 0%)', ease: 'none', scrollTrigger: {trigger: cs, start: 'top 95%', end: 'top 30%', scrub: .8}});
    gsap.fromTo(img, {yPercent: -7, scale: 1.24}, {yPercent: 7, scale: 1.08, ease: 'none', scrollTrigger: {trigger: cs, start: 'top bottom', end: 'bottom top', scrub: true}});
    gsap.fromTo('.ap-left', {y: 60}, {y: -40, ease: 'none', scrollTrigger: {trigger: '.ap-grid', start: 'top bottom', end: 'bottom top', scrub: true}});
    gsap.fromTo('.ap-right', {y: 100}, {y: -60, ease: 'none', scrollTrigger: {trigger: '.ap-grid', start: 'top bottom', end: 'bottom top', scrub: true}});
  }

  /* ------------------------------------------------------------------------
     Réalisations : vitrine, diaphragme circulaire (épinglé)
     ------------------------------------------------------------------------ */
  function worksPinned() {
    const sec = $('#realisations');
    const stage = $('.works-stage', sec), vit = $('.vitrine', sec);
    const plates = $$('.plate', sec), idx = $$('.works-index li', sec), bezIdx = $('.vt-index', sec);
    sec.classList.add('is-pinned');
    const iris = document.createElement('div');
    iris.className = 'vt-iris';
    iris.setAttribute('aria-hidden', 'true');
    vit.appendChild(iris);
    const btns = plates.map(p => $('.project-image', p)), imgs = plates.map(p => $('img', p)), caps = plates.map(p => $('figcaption', p));
    btns.forEach((b, i) => gsap.set(b, {clipPath: i ? 'circle(0% at 50% 50%)' : 'circle(75% at 50% 50%)'}));
    caps.forEach((c, i) => gsap.set(c, {opacity: i ? 0 : 1, y: i ? 16 : 0}));
    const setCur = i => idx.forEach((li, j) => li.classList.toggle('is-active', j === i));
    setCur(0);
    const tl = gsap.timeline({defaults: {ease: 'none'}, scrollTrigger: {
      trigger: stage, start: 'top top', end: '+=300%', pin: true, scrub: .9,
      snap: {snapTo: [0, 1 / 3, 2 / 3, 1], duration: {min: .4, max: .9}, delay: .12, inertia: false, ease: 'power2.inOut'},
      onUpdate: self => setCur(clamp(Math.round(self.progress * 3), 0, 3))
    }});
    for (let i = 1; i < 4; i++) {
      const at = i - 1;
      tl.fromTo(btns[i], {clipPath: 'circle(0% at 50% 50%)'}, {clipPath: 'circle(75% at 50% 50%)', duration: 1, ease: LUX}, at)
        .fromTo(iris, {scale: 0, opacity: 1}, {scale: 1.06, opacity: 0, duration: 1, ease: LUX}, at)
        .to(imgs[i - 1], {scale: 1.3, duration: 1, ease: 'power1.in'}, at)
        .fromTo(imgs[i], {scale: 1.35}, {scale: 1.04, duration: 1, ease: 'power2.out'}, at)
        .to(caps[i - 1], {opacity: 0, y: -16, duration: .35}, at + .1)
        .to(caps[i], {opacity: 1, y: 0, duration: .35}, at + .6)
        .to(bezIdx, {rotation: 90 * i, svgOrigin: '500 500', duration: 1, ease: LUX}, at);
    }
    btns.forEach((b, i) => b.addEventListener('focus', () => {
      const st = tl.scrollTrigger;
      if (!st) return;
      const y = st.start + (st.end - st.start) * (i / 3);
      if (Math.abs(window.scrollY - y) > 20) lenis ? lenis.scrollTo(y, {immediate: true}) : window.scrollTo(0, y);
    }));
    return () => { sec.classList.remove('is-pinned'); iris.remove(); gsap.set([...btns, ...caps, ...imgs], {clearProps: 'all'}); };
  }
  function worksFlow() {
    $$('#realisations .project-image').forEach(b => {
      gsap.fromTo(b, {clipPath: 'circle(8% at 50% 50%)'}, {clipPath: 'circle(72% at 50% 50%)', ease: 'none', scrollTrigger: {trigger: b, start: 'top 95%', end: 'top 35%', scrub: .6}});
      gsap.fromTo($('img', b), {scale: 1.4}, {scale: 1.04, ease: 'none', scrollTrigger: {trigger: b, start: 'top bottom', end: 'bottom 30%', scrub: .6}});
    });
  }

  /* ------------------------------------------------------------------------
     Méthode : le mouvement
     ------------------------------------------------------------------------ */
  const mvSvg = $('.mv-svg');
  const gearRot = n => $(`.mv-${n} .gear-rot`);
  const G = mvSvg ? {a: gearRot('a'), k: gearRot('k'), b: gearRot('b'), c: gearRot('c'), d: gearRot('d'), e: gearRot('e'), r: $('.ratchet-rot')} : null;
  const bal = $('.balance-rot'), spring = $('.b-spring');
  function setTrain(deg) {
    if (!G) return;
    const r = (el, v) => el && el.setAttribute('transform', `rotate(${v.toFixed(2)})`);
    r(G.a, deg); r(G.r, deg);
    r(G.k, -deg * 48 / 36);
    r(G.b, -deg * 84 / 64);
    r(G.c, deg * 84 / 48);
    r(G.d, -deg * 84 / 36);
    r(G.e, deg * 84 / 20);
  }
  // balancier : oscille tant que la section est visible
  if (bal) {
    let on = false;
    const t0 = performance.now();
    const swing = () => {
      const t = (performance.now() - t0) / 1000;
      const v = Math.sin(t * Math.PI * 2 * 1.25) * 150;
      bal.setAttribute('transform', `rotate(${v.toFixed(2)})`);
      spring?.setAttribute('transform', `rotate(${(v * .12).toFixed(2)}) scale(${(1 + Math.sin(t * Math.PI * 2 * 1.25) * .025).toFixed(4)})`);
    };
    new IntersectionObserver(es => {
      const vis = es[0].isIntersecting;
      if (vis && !on) { on = true; gsap.ticker.add(swing); }
      if (!vis && on) { on = false; gsap.ticker.remove(swing); }
    }).observe(mvSvg);
  }
  // le fond brun s’ouvre comme un boîtier qu’on retourne
  function movementReveal() {
    const sec = $('.movement');
    if (!sec) return;
    gsap.fromTo(sec, {clipPath: 'inset(0% 6% 0% 6% round 56px 56px 0px 0px)'}, {
      clipPath: 'inset(0% 0% 0% 0% round 0px 0px 0px 0px)', ease: 'none',
      scrollTrigger: {trigger: sec, start: 'top bottom', end: 'top 15%', scrub: .6, onLeave: () => gsap.set(sec, {clearProps: 'clipPath'})}
    });
  }
  function movementPinned() {
    const sec = $('.movement'), stage = $('.mv-stage', sec), steps = $$('.step', sec);
    sec.classList.add('is-pinned');
    steps.forEach(s => { s.removeAttribute('data-reveal'); s.classList.add('is-in'); });
    const rs = $('.rs-fill', sec);
    const train = {deg: 0};
    const setStep = i => steps.forEach((s, j) => s.classList.toggle('is-active', j === i));
    setStep(0);
    const tl = gsap.timeline({defaults: {ease: 'none'}, scrollTrigger: {
      trigger: stage, start: 'top top', end: '+=240%', pin: true, scrub: 1,
      onUpdate: self => setStep(clamp(Math.floor(self.progress * 4 - .0001), 0, 3))
    }});
    tl.to(train, {deg: 150, duration: 1, onUpdate: () => setTrain(train.deg)}, 0);
    if (rs) tl.fromTo(rs, {strokeDashoffset: 1}, {strokeDashoffset: 0, duration: 1}, 0);
    tl.fromTo('.mv-visual', {rotation: -8}, {rotation: 4, duration: 1}, 0);
    steps.forEach((s, i) => s.addEventListener('focusin', () => {
      const st = tl.scrollTrigger; if (!st) return;
      lenis ? lenis.scrollTo(st.start + (st.end - st.start) * ((i + .5) / 4), {immediate: true}) : 0;
    }));
    return () => { sec.classList.remove('is-pinned'); steps.forEach(s => s.classList.remove('is-active')); };
  }
  function movementFlow() {
    const train = {deg: 0};
    gsap.to(train, {deg: 140, ease: 'none', onUpdate: () => setTrain(train.deg), scrollTrigger: {trigger: '.movement', start: 'top bottom', end: 'bottom top', scrub: .6}});
    const rs = $('.rs-fill');
    if (rs) gsap.fromTo(rs, {strokeDashoffset: 1}, {strokeDashoffset: 0, ease: 'none', scrollTrigger: {trigger: '.movement', start: 'top 60%', end: 'bottom 60%', scrub: true}});
  }

  /* ------------------------------------------------------------------------
     Pied de page : horloge de Bussy
     ------------------------------------------------------------------------ */
  const footer = $('.footer');
  if (footer) {
    let on = false;
    new IntersectionObserver(es => {
      const vis = es[0].isIntersecting;
      if (vis && !on) { on = true; gsap.ticker.add(setFooterClock); }
      if (!vis && on) { on = false; gsap.ticker.remove(setFooterClock); }
    }).observe(footer);
    gsap.from($$('.footer-top > *, .footer-mid > *', footer), {opacity: 0, y: 30, duration: 1.2, stagger: .06, ease: 'expo.out', scrollTrigger: {trigger: footer, start: 'top 80%', once: true}});
  }

  /* ------------------------------------------------------------------------
     Boutons magnétiques
     ------------------------------------------------------------------------ */
  if (fine) {
    $$('[data-magnetic]').forEach(el => {
      const xTo = gsap.quickTo(el, 'x', {duration: .8, ease: 'elastic.out(1, .45)'});
      const yTo = gsap.quickTo(el, 'y', {duration: .8, ease: 'elastic.out(1, .45)'});
      el.addEventListener('pointermove', e => {
        const r = el.getBoundingClientRect();
        const dx = e.clientX - (r.left + r.width / 2), dy = e.clientY - (r.top + r.height / 2);
        xTo(dx * .22); yTo(dy * .34);
        el.style.setProperty('--mx', (e.clientX - r.left) + 'px');
        el.style.setProperty('--my', (e.clientY - r.top) + 'px');
      });
      el.addEventListener('pointerleave', () => { xTo(0); yTo(0); });
    });
  }

  /* ------------------------------------------------------------------------
     Loupe d’horloger
     ------------------------------------------------------------------------ */
  if (fine) {
    const ticksPath = Array.from({length: 24}, (_, i) => {
      const a = i * 15 * Math.PI / 180, r1 = i % 6 === 0 ? 17 : 19.2, r2 = 21;
      return `M${(22 + Math.sin(a) * r1).toFixed(2)} ${(22 - Math.cos(a) * r1).toFixed(2)}L${(22 + Math.sin(a) * r2).toFixed(2)} ${(22 - Math.cos(a) * r2).toFixed(2)}`;
    }).join('');
    const lp = document.createElement('div');
    lp.className = 'loupe is-off';
    lp.setAttribute('aria-hidden', 'true');
    lp.innerHTML = `<div class="loupe-pos"><div class="loupe-ring"><svg viewBox="0 0 44 44"><defs><radialGradient id="lg-glass" cx=".35" cy=".3" r=".8"><stop offset="0" stop-color="#fff" stop-opacity=".55"/><stop offset=".6" stop-color="#F9DBA3" stop-opacity=".12"/><stop offset="1" stop-color="#9F722A" stop-opacity=".18"/></radialGradient></defs><circle class="loupe-glass" cx="22" cy="22" r="20.6" fill="url(#lg-glass)"/><circle cx="22" cy="22" r="21" fill="none" stroke="currentColor" stroke-width=".9"/><g class="loupe-ticks"><path d="${ticksPath}" stroke="currentColor" stroke-width=".6" fill="none"/></g></svg></div><span class="loupe-label">Agrandir</span></div><div class="loupe-dotpos"><span class="loupe-dot"></span></div>`;
    document.body.appendChild(lp);
    root.classList.add('has-loupe');
    const pos = $('.loupe-pos', lp), dot = $('.loupe-dotpos', lp);
    const px = gsap.quickTo(pos, 'x', {duration: .55, ease: 'power3'}), py = gsap.quickTo(pos, 'y', {duration: .55, ease: 'power3'});
    const dx = gsap.quickTo(dot, 'x', {duration: .12, ease: 'power3'}), dy = gsap.quickTo(dot, 'y', {duration: .12, ease: 'power3'});
    let first = true;
    addEventListener('pointermove', e => {
      if (e.pointerType !== 'mouse') return;
      if (first) { gsap.set([pos, dot], {x: e.clientX, y: e.clientY}); first = false; }
      px(e.clientX); py(e.clientY); dx(e.clientX); dy(e.clientY);
      lp.classList.remove('is-off');
      const t = e.target instanceof Element ? e.target : null;
      if (!t) return;
      const view = t.closest('.project-image');
      const text = t.closest('input, textarea, select');
      const hov = !view && !text && t.closest('a, button, summary, label, [data-magnetic]');
      lp.classList.toggle('is-view', !!view);
      lp.classList.toggle('is-text', !!text);
      lp.classList.toggle('is-hover', !!hov);
      lp.classList.toggle('on-dark', !!t.closest('[data-tone="dark"]') || document.body.style.backgroundColor === 'rgb(33, 26, 19)');
    }, {passive: true});
    document.addEventListener('pointerleave', () => lp.classList.add('is-off'));
    addEventListener('pointerdown', () => lp.classList.add('is-down'));
    addEventListener('pointerup', () => lp.classList.remove('is-down'));
  }

  /* ------------------------------------------------------------------------
     Montage
     ------------------------------------------------------------------------ */
  const ready = Promise.race([document.fonts ? document.fonts.ready : Promise.resolve(), new Promise(r => setTimeout(r, 900))]);
  ready.then(() => {
    runIntro();
    headings();
    sapphire();
    territory();
    certificate();
    approach();
    movementReveal();
    const mm = gsap.matchMedia();
    mm.add({desk: '(min-width: 1024px) and (min-height: 600px)', small: '(max-width: 1023px), (max-height: 599px)'}, ctx => {
      const {desk} = ctx.conditions;
      const undo = [];
      if (desk) {
        undo.push(expertisesPinned());
        undo.push(worksPinned());
        undo.push(movementPinned());
      } else {
        worksFlow();
        movementFlow();
      }
      return () => undo.forEach(f => f && f());
    });
    // Ordre des épinglages et recalcul une fois les images chargées
    ScrollTrigger.sort();
    addEventListener('load', () => ScrollTrigger.refresh());
    setTimeout(() => ScrollTrigger.refresh(), 1200);
  });
})();
