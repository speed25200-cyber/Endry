/* ==========================================================================
   Endry SA — Maquette XIV « Palace » : mise en mouvement
   Intro portes d’ascenseur, feuille d’or WebGL, indicateur d’étage,
   portes des métiers et ascenseur de la méthode (pin + scrub), curseur.
   ========================================================================== */
(() => {
  'use strict';

  const root = document.documentElement;
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const hasGsap = !!(window.gsap && window.ScrollTrigger);
  const $ = (s, c = document) => c.querySelector(s);
  const $$ = (s, c = document) => Array.from(c.querySelectorAll(s));

  /* ------------------------------------------------------------------------
     Cadrans d’étage (SVG décoratif)
     ------------------------------------------------------------------------ */
  const CX = 100, CY = 104;
  function dialSVG(labels, lamp) {
    const n = labels.length;
    let s = '<path class="d-arc" d="M8 104A92 92 0 0 1 192 104"/><path class="d-arc" d="M44 104A56 56 0 0 1 156 104"/>';
    for (let i = 0; i <= 28; i++) {
      const th = Math.PI - i * Math.PI / 28;
      const r0 = i % 4 === 0 ? 84 : 88;
      s += `<line class="d-tick" x1="${(CX + r0 * Math.cos(th)).toFixed(1)}" y1="${(CY - r0 * Math.sin(th)).toFixed(1)}" x2="${(CX + 92 * Math.cos(th)).toFixed(1)}" y2="${(CY - 92 * Math.sin(th)).toFixed(1)}"/>`;
    }
    labels.forEach((l, i) => {
      const th = Math.PI - i * Math.PI / (n - 1);
      s += `<text class="d-num" x="${(CX + 71 * Math.cos(th)).toFixed(1)}" y="${(CY - 71 * Math.sin(th)).toFixed(1)}">${l}</text>`;
    });
    s += '<g class="d-needle-g"><line class="d-needle" x1="100" y1="104" x2="100" y2="48"/><path class="d-needle-tip" d="M100 40l4 9h-8z"/></g>';
    s += '<circle class="d-hub" cx="100" cy="104" r="5"/><line class="d-base" x1="-4" y1="111" x2="204" y2="111"/>';
    if (lamp) s += '<path class="d-lamp" d="M100 -16l6 6-6 6-6-6z" fill="none" stroke="currentColor"/>';
    return `<svg class="dial-svg" viewBox="-6 ${lamp ? -22 : -2} 212 ${lamp ? 136 : 116}" aria-hidden="true" focusable="false">${s}</svg>`;
  }
  const rot = (i, n) => -90 + i * 180 / (n - 1);
  function setNeedle(el, deg) {
    const g = el && el.querySelector('.d-needle-g');
    if (g) g.setAttribute('transform', `rotate(${deg} ${CX} ${CY})`);
  }
  function lightNum(el, i) {
    if (!el) return;
    el.querySelectorAll('.d-num').forEach((t, k) => t.classList.toggle('is-on', k === i));
  }

  const FLOORS = ['E', '1', '2', '3', '4', '5', '6', '7'];
  $$('[data-dial]').forEach(el => {
    const kind = el.dataset.dial;
    if (kind === 'door') {
      el.innerHTML = dialSVG(['E', '1', '2', '3']);
      const t = +el.dataset.target;
      // Sans animation : l’aiguille indique directement l’étage de la porte.
      setNeedle(el, rot(t, 4));
      lightNum(el, t);
    } else if (kind === 'method') {
      el.innerHTML = dialSVG(['1', '2', '3', '4']);
      setNeedle(el, rot(0, 4));
      lightNum(el, 0);
    } else {
      el.innerHTML = dialSVG(FLOORS, kind === 'big');
      setNeedle(el, rot(kind === 'big' ? 7 : 0, 8));
      lightNum(el, kind === 'big' ? 7 : 0);
    }
  });

  const endIntro = () => {
    root.classList.remove('intro');
    const lift = $('.lift');
    if (lift) lift.remove();
  };

  if (reduce || !hasGsap) {
    endIntro();
    return;
  }

  /* ------------------------------------------------------------------------
     Initialisation GSAP / Lenis
     ------------------------------------------------------------------------ */
  const { gsap, ScrollTrigger } = window;
  gsap.registerPlugin(ScrollTrigger);
  if (window.SplitText) gsap.registerPlugin(window.SplitText);
  if (window.CustomEase) {
    gsap.registerPlugin(window.CustomEase);
    window.CustomEase.create('lux', '0.7,0,0.2,1');
  }
  const LUX = window.CustomEase ? 'lux' : 'expo.inOut';
  root.classList.add('anim');
  // Gravure des portes de l’intro dès que possible (avant l’attente des polices)
  if (root.classList.contains('intro')) {
    const l = $('.lift-door-l'), r = $('.lift-door-r');
    if (l && r) l.innerHTML = r.innerHTML = leafSVG(innerWidth / 2, innerHeight, true);
  }
  ScrollTrigger.config({ ignoreMobileResize: true });

  let lenis = null;
  if (window.Lenis) {
    lenis = new window.Lenis({ lerp: 0.085, smoothWheel: true, anchors: false });
    lenis.on('scroll', ScrollTrigger.update);
    gsap.ticker.add(t => lenis.raf(t * 1000));
    gsap.ticker.lagSmoothing(0);
  }
  const stopScroll = () => lenis && lenis.stop();
  const startScroll = () => lenis && lenis.start();

  // Menu mobile et dialogues : on fige Lenis pendant qu’ils sont ouverts.
  const toggle = $('.menu-toggle');
  const syncLock = () => {
    const menuOpen = toggle && toggle.getAttribute('aria-expanded') === 'true';
    const dlgOpen = $$('dialog').some(d => d.open);
    if (menuOpen || dlgOpen || root.classList.contains('intro')) stopScroll(); else startScroll();
  };
  if (toggle) new MutationObserver(syncLock).observe(toggle, { attributes: true, attributeFilter: ['aria-expanded'] });
  $$('dialog').forEach(d => new MutationObserver(syncLock).observe(d, { attributes: true, attributeFilter: ['open'] }));

  /* ------------------------------------------------------------------------
     Reflet du laiton : position horizontale du pointeur → --mx
     ------------------------------------------------------------------------ */
  const fine = matchMedia('(hover: hover) and (pointer: fine)').matches;
  const pointer = { x: innerWidth * .72, y: innerHeight * .28, active: false };
  let mxRaf = 0;
  addEventListener('pointermove', e => {
    pointer.x = e.clientX; pointer.y = e.clientY; pointer.active = true;
    if (!mxRaf) mxRaf = requestAnimationFrame(() => {
      mxRaf = 0;
      root.style.setProperty('--mx', (-20 + 140 * pointer.x / innerWidth).toFixed(1) + '%');
    });
  }, { passive: true });

  /* ------------------------------------------------------------------------
     Feuille d’or — WebGL brut, un seul shader plein écran
     ------------------------------------------------------------------------ */
  const gl = initGL();

  function initGL() {
    const canvas = $('.leaf-gl');
    if (!canvas) return null;
    let ctx = null;
    try { ctx = canvas.getContext('webgl', { antialias: false, alpha: false, depth: false, stencil: false, powerPreference: 'high-performance' }); } catch (e) { ctx = null; }
    if (!ctx) return null;
    const vs = 'attribute vec2 p;void main(){gl_Position=vec4(p,0.,1.);}';
    const fs = `
precision highp float;
uniform vec2 uSun;
uniform vec2 uLight;
uniform float uTime;
uniform float uDeploy;
uniform float uVel;
uniform float uDpr;
float hash(vec2 p){p=fract(p*vec2(233.34,851.73));p+=dot(p,p+23.45);return fract(p.x*p.y);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);vec2 u=f*f*(3.-2.*f);
  return mix(mix(hash(i),hash(i+vec2(1.,0.)),u.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),u.x),u.y);}
void main(){
  vec2 fp=gl_FragCoord.xy/uDpr;
  vec2 d=fp-uSun;
  float r=length(d)+1e-3;
  vec2 rad=d/r;
  vec2 tg=vec2(-rad.y,rad.x);
  float a=atan(d.x,d.y);
  const float N=48.;
  float k=(a/6.2831853+.5)*N;
  float idx=floor(k);
  float f=fract(k);
  float ac=abs(((idx+.5)/N-.5)*2.);
  float appear=smoothstep(ac,ac+.07,uDeploy*1.08);
  float reach=mix(0.,2800.,appear)+step(.999,uDeploy)*1e6;
  float grow=1.-smoothstep(reach-220.,reach,r);
  float inner=smoothstep(40.,120.,r);
  float fade=mix(1.,.38,smoothstep(500.,2600.,r));
  float edge=min(f,1.-f)*6.2831853*r/N;
  float aa=smoothstep(0.,1.4,edge);
  float alt=mod(idx,2.);
  float live=appear*grow*inner;
  float ray=alt*aa*live*fade;
  float side=f<.5?-1.:1.;
  vec2 n=tg*side*.09*live*fade;
  vec2 g=fp/72.;
  g.x+=mod(floor(g.y),2.)*.5;
  vec2 cell=floor(g);
  vec2 cf=fract(g);
  float h1=hash(cell),h2=hash(cell+17.3),h3=hash(cell+41.7);
  n+=(vec2(h1,h2)-.5)*.06;
  float seamD=min(min(cf.x,1.-cf.x),min(cf.y,1.-cf.y))+(noise(fp*.15)-.5)*.02;
  float seam=1.-smoothstep(0.,.03,seamD);
  n+=(vec2(noise(fp*.028),noise(fp*.028+9.))-.5)*.06;
  float br=noise(vec2(a*r*.5,r*.005));
  n+=tg*(br-.5)*.05;
  n+=rad*sin(r*.028-uTime*3.4)*uVel*.13;
  vec3 Nn=normalize(vec3(n,1.));
  vec3 L=normalize(vec3(uLight-fp,460.));
  vec3 H=normalize(L+vec3(0.,0.,1.));
  float ndh=max(dot(Nn,H),0.);
  float spec=pow(ndh,120.)*(.55+.9*br);
  float sheen=pow(ndh,9.);
  float diff=dot(Nn,L);
  vec3 base=vec3(.976,.859,.639);
  vec3 rayC=vec3(.95,.81,.575);
  vec3 col=mix(base,rayC,ray*.85);
  col*=.99+.022*h3-.012*seam;
  col*=mix(.955,1.015,diff);
  col+=vec3(1.,.94,.80)*spec*.26+vec3(1.,.9,.7)*sheen*.04;
  col-=(hash(fp)-.5)*.018;
  col=clamp(col,vec3(.86,.72,.50),vec3(1.,.975,.92));
  gl_FragColor=vec4(col,1.);
}`;
    const sh = (type, src) => { const s = ctx.createShader(type); ctx.shaderSource(s, src); ctx.compileShader(s); return ctx.getShaderParameter(s, ctx.COMPILE_STATUS) ? s : null; };
    const v = sh(ctx.VERTEX_SHADER, vs), f = sh(ctx.FRAGMENT_SHADER, fs);
    if (!v || !f) return null;
    const prog = ctx.createProgram();
    ctx.attachShader(prog, v); ctx.attachShader(prog, f); ctx.linkProgram(prog);
    if (!ctx.getProgramParameter(prog, ctx.LINK_STATUS)) return null;
    ctx.useProgram(prog);
    const buf = ctx.createBuffer();
    ctx.bindBuffer(ctx.ARRAY_BUFFER, buf);
    ctx.bufferData(ctx.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), ctx.STATIC_DRAW);
    const loc = ctx.getAttribLocation(prog, 'p');
    ctx.enableVertexAttribArray(loc);
    ctx.vertexAttribPointer(loc, 2, ctx.FLOAT, false, 0, 0);
    const U = {};
    ['uSun', 'uLight', 'uTime', 'uDeploy', 'uVel', 'uDpr'].forEach(n => { U[n] = ctx.getUniformLocation(prog, n); });

    root.classList.add('gl-on');
    const state = { deploy: 0, vel: 0, lx: innerWidth * .72, ly: innerHeight * .28, visible: true };
    let dpr = 1;
    const resize = () => {
      dpr = Math.min(window.devicePixelRatio || 1, innerWidth < 760 ? 1.25 : 1.5);
      canvas.width = Math.round(innerWidth * dpr);
      canvas.height = Math.round(innerHeight * dpr);
      ctx.viewport(0, 0, canvas.width, canvas.height);
    };
    resize();
    addEventListener('resize', resize);

    // Pause hors écran : on ne dessine que si un aplat or est visible.
    const leafy = new Set();
    const io = new IntersectionObserver(es => {
      es.forEach(e => e.isIntersecting ? leafy.add(e.target) : leafy.delete(e.target));
      state.visible = leafy.size > 0;
    });
    $$('.leafy').forEach(s => io.observe(s));

    const heroWin = $('.hero-window'), anchor = $('.sun-anchor');
    const mobileQ = matchMedia('(max-width: 760px)');
    const t0 = performance.now();
    gsap.ticker.add(() => {
      if (!state.visible || document.hidden) return;
      const t = (performance.now() - t0) / 1000;
      // Lumière : pointeur (desktop) ou course lente autonome (tactile)
      let tx, ty;
      if (fine && pointer.active) { tx = pointer.x; ty = pointer.y; }
      else { tx = innerWidth * (.5 + .38 * Math.sin(t * .23)); ty = innerHeight * (.35 + .25 * Math.cos(t * .17)); }
      state.lx += (tx - state.lx) * .08;
      state.ly += (ty - state.ly) * .08;
      const v = lenis ? Math.min(Math.abs(lenis.velocity) / 45, 1) : 0;
      state.vel += (v - state.vel) * .06;
      let sx, sy;
      if (mobileQ.matches && heroWin) { const r = heroWin.getBoundingClientRect(); sx = r.left + r.width / 2; sy = r.top; }
      else { const r = anchor.getBoundingClientRect(); sx = r.left; sy = r.top; }
      ctx.uniform2f(U.uSun, sx, innerHeight - sy);
      ctx.uniform2f(U.uLight, state.lx, innerHeight - state.ly);
      ctx.uniform1f(U.uTime, t);
      ctx.uniform1f(U.uDeploy, state.deploy);
      ctx.uniform1f(U.uVel, state.vel);
      ctx.uniform1f(U.uDpr, dpr);
      ctx.drawArrays(ctx.TRIANGLES, 0, 3);
    });
    return state;
  }

  /* ------------------------------------------------------------------------
     Gravures Art déco des vantaux (laiton)
     ------------------------------------------------------------------------ */
  function leafSVG(w, h, big) {
    w = Math.max(40, Math.round(w)); h = Math.max(80, Math.round(h));
    const m = big ? 30 : 12, i = big ? 8 : 6;
    const sx = w, sy = h * (big ? .36 : .27);
    const R = Math.max(20, Math.min(w - m * 1.7, h * (big ? .24 : .19)));
    const p = [];
    p.push(`M${w} ${m}H${m}V${h - m}H${w}`);
    p.push(`M${w} ${m + i}H${m + i}V${h - m - i}H${w}`);
    [1, .84, .38, .3].forEach(k => { const r = R * k; p.push(`M${sx} ${sy - r}A${r} ${r} 0 0 0 ${sx} ${sy + r}`); });
    for (let j = 1; j < 18; j++) {
      const ph = j * Math.PI / 18, s = Math.sin(ph), c = Math.cos(ph);
      const r0 = R * .38, r1 = j % 2 ? R * .84 : R;
      p.push(`M${(sx - r0 * s).toFixed(1)} ${(sy - r0 * c).toFixed(1)}L${(sx - r1 * s).toFixed(1)} ${(sy - r1 * c).toFixed(1)}`);
    }
    const x0 = m + i + (big ? 26 : 10);
    const bt = sy + R + (big ? 46 : 22), zz = big ? 22 : 11;
    p.push(`M${x0} ${bt - 9}H${w}M${x0} ${bt + zz + 9}H${w}`);
    let z = `M${x0} ${bt + zz}`, up = true;
    for (let x = x0; x < w; x += zz) { z += `L${Math.min(x + zz, w).toFixed(1)} ${up ? bt : bt + zz}`; up = !up; }
    p.push(z);
    const pt = bt + zz + (big ? 46 : 24), kt = h - m - i - h * .1, pb = kt - (big ? 30 : 16), st = big ? 16 : 8;
    if (pb - pt > 60) {
      p.push(`M${w} ${pt}H${x0 + st * 2}V${pt + st}H${x0 + st}V${pt + st * 2}H${x0}V${pb}H${w}`);
      const fx = big ? 16 : 10;
      for (let x = x0 + st * 2 + fx; x < w - 4; x += fx) p.push(`M${x} ${pt + st * 2 + (big ? 16 : 10)}V${pb - (big ? 16 : 10)}`);
    }
    p.push(`M${x0} ${kt}H${w}`);
    const d = p.join('');
    return `<svg viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" aria-hidden="true" focusable="false">` +
      `<rect class="engrave-fill" x="${x0}" y="${kt}" width="${w - x0}" height="${h - m - i - kt}"/>` +
      `<path class="engrave-light" transform="translate(1 1)" d="${d}"/><path class="engrave-dark" d="${d}"/></svg>`;
  }

  // Vantaux des portes des métiers
  const doors = $$('.door');
  doors.forEach(door => {
    const frame = $('.door-frame', door);
    ['l', 'r'].forEach(side => {
      const leaf = document.createElement('div');
      leaf.className = `leaf leaf-${side}`;
      leaf.setAttribute('aria-hidden', 'true');
      frame.append(leaf);
    });
  });
  const engraveDoors = () => doors.forEach(door => {
    const f = $('.door-frame', door);
    const w = f.clientWidth / 2, h = f.clientHeight;
    $$('.leaf', door).forEach(l => { l.innerHTML = leafSVG(w, h, false); });
  });
  engraveDoors();
  ScrollTrigger.addEventListener('refreshInit', engraveDoors);

  /* Tout ce qui suit attend les polices (SplitText mesure les glyphes), 900 ms au plus. */
  const boot = () => {
  /* ------------------------------------------------------------------------
     Découpage typographique
     ------------------------------------------------------------------------ */
  const hasSplit = !!window.SplitText;
  const h1 = $('.hero-title');
  let heroChars = [], heroT2 = [];
  if (hasSplit) {
    const s1 = window.SplitText.create($('.t1', h1), { type: 'chars', mask: 'chars', charsClass: 'hc', aria: 'none' });
    heroChars = s1.chars;
    h1.setAttribute('aria-label', h1.textContent.replace(/\s+/g, ' ').trim());
    $$('.t1, .t2', h1).forEach(s => s.setAttribute('aria-hidden', 'true'));
    heroT2 = [$('.t2', h1)];
  } else {
    heroChars = [$('.t1', h1)];
    heroT2 = [$('.t2', h1)];
  }

  /* ------------------------------------------------------------------------
     Entrée du héros (après l’intro, ou directement)
     ------------------------------------------------------------------------ */
  const hero = $('.hero');
  const heroParts = {
    eyebrow: $('.hero-eyebrow'), sub: $('.hero-sub'), actions: $('.hero-actions'),
    plaques: $$('.hero > .plaque'), window: $('.hero-window'), rings: $$('.sun-rings path')
  };
  gsap.set(heroChars, { yPercent: 108 });
  gsap.set(heroT2, { autoAlpha: 0, y: 24 });
  gsap.set([heroParts.eyebrow, heroParts.sub, heroParts.actions], { autoAlpha: 0, y: 26 });
  gsap.set(heroParts.plaques, { autoAlpha: 0, y: 40 });
  gsap.set(heroParts.window, { yPercent: 34 });
  gsap.set(heroParts.rings, { strokeDasharray: 1, strokeDashoffset: 1 });
  root.classList.add('booted');

  function heroIn(delay) {
    const tl = gsap.timeline({ delay });
    if (gl) tl.to(gl, { deploy: 1, duration: 1.5, ease: 'power2.out' }, 0);
    tl.to(heroParts.window, { yPercent: 0, duration: 1.4, ease: 'expo.out' }, 0)
      .to(heroParts.rings, { strokeDashoffset: 0, duration: 1.4, ease: 'power3.out', stagger: .08 }, .05)
      .to(heroChars, { yPercent: 0, duration: 1.2, ease: 'expo.out', stagger: .035 }, .1)
      .to(heroParts.eyebrow, { autoAlpha: 1, y: 0, duration: 1, ease: 'expo.out' }, .2)
      .to(heroT2, { autoAlpha: 1, y: 0, duration: 1.1, ease: 'expo.out' }, .45)
      .to([heroParts.sub, heroParts.actions], { autoAlpha: 1, y: 0, duration: 1.1, ease: 'expo.out', stagger: .08 }, .55)
      .to(heroParts.plaques, { autoAlpha: 1, y: 0, duration: 1.1, ease: 'expo.out', stagger: .06 }, .6)
      .add(() => gsap.to('.floor', { autoAlpha: 1, duration: .8 }), .7);
    return tl;
  }

  /* ------------------------------------------------------------------------
     Intro : l’aiguille descend jusqu’à « E », les portes s’ouvrent
     ------------------------------------------------------------------------ */
  const lift = $('.lift');
  if (root.classList.contains('intro') && lift) {
    stopScroll();
    const dL = $('.lift-door-l', lift), dR = $('.lift-door-r', lift);
    const dial = $('.lift-dial', lift), needle = $('.d-needle-g', dial), lamp = $('.d-lamp', dial);
    const n = { v: 7 };
    // Si les polices ont retardé le démarrage, l’intro accélère pour finir avant 2,5 s.
    const left = Math.max(.9, 2.45 - performance.now() / 1000);
    const tl = gsap.timeline();
    tl.timeScale(Math.max(1, 2.32 / left));
    tl.add(() => { endIntro(); syncLock(); ScrollTrigger.refresh(); }, 2.32);
    tl.to(n, {
      v: 0, duration: 1.05, ease: 'power2.inOut',
      onUpdate: () => { setNeedle(dial, rot(n.v, 8)); lightNum(dial, Math.round(n.v)); }
    }, .1)
      .to(lamp, { fill: '#FFF1CF', duration: .12, repeat: 1, yoyo: true }, 1.1)
      .to(lift.querySelector('.lift-transom'), { yPercent: -110, duration: .7, ease: 'power3.in' }, 1.15)
      .to(dL, { xPercent: -101, duration: 1.1, ease: LUX }, 1.2)
      .to(dR, { xPercent: 101, duration: 1.1, ease: LUX }, 1.2)
      .add(heroIn(0), 1.3);
    // Garde-fou : l’intro ne bloque jamais plus de 2,5 s.
    setTimeout(() => { if (root.classList.contains('intro')) { tl.progress(1); } }, Math.max(300, 2600 - performance.now()));
  } else {
    endIntro();
    heroIn(.1);
  }

  /* ------------------------------------------------------------------------
     Scénographie au défilement
     ------------------------------------------------------------------------ */
  const mm = gsap.matchMedia();
  const pins = new Map();

  mm.add({ desk: '(min-width: 1025px)', mob: '(max-width: 1024px)' }, ctx => {
    const { desk } = ctx.conditions;

    /* E · la fenêtre à gradins s’ouvre en plein écran */
    if (desk) {
      const t = gsap.timeline({
        scrollTrigger: { trigger: hero, start: 'top top', end: '+=115%', pin: true, scrub: 1, anticipatePin: 1, onUpdate: self => hero.classList.toggle('is-open', self.progress > .3) }
      });
      t.to(hero, { '--w': '50%', '--t': '0%', '--s': '0px', ease: 'power2.inOut', duration: 1 }, 0)
        .fromTo('.hw-clip img', { scale: 1.3 }, { scale: 1, ease: 'none', duration: 1 }, 0)
        .fromTo('.hero-stage', { yPercent: 0 }, { yPercent: -18, ease: 'none', duration: .8, immediateRender: false }, 0)
        .to(hero, { '--o': 0, ease: 'power1.in', duration: .32 }, .2)
        .fromTo('.hw-motto', { autoAlpha: 0, y: 40 }, { autoAlpha: 1, y: 0, duration: .25, ease: 'power2.out', immediateRender: false }, .72)
        .fromTo('.hw-motto-sub', { autoAlpha: 0, y: 24 }, { autoAlpha: 1, y: 0, duration: .22, ease: 'power2.out', immediateRender: false }, .8)
        .to({}, { duration: .12 });
      pins.set(hero, t.scrollTrigger);
    } else {
      gsap.fromTo('.hw-clip img', { yPercent: -6, scale: 1.12 }, {
        yPercent: 6, scale: 1, ease: 'none',
        scrollTrigger: { trigger: '.hero-window', start: 'top bottom', end: 'bottom top', scrub: true }
      });
    }

    /* Salons bruns : l’arche à gradins s’élargit */
    const stepped = $$('.hall, .salon, .method');
    stepped.forEach(sec => {
      sec.classList.add('stepped');
      gsap.fromTo(sec, { '--p': 0 }, {
        '--p': 1, ease: 'none',
        scrollTrigger: { trigger: sec, start: 'top bottom', end: 'top 12%', scrub: true }
      });
    });

    /* 1 · Portes d’ascenseur des métiers */
    if (desk) {
      const t = gsap.timeline({
        scrollTrigger: { trigger: '.hall', start: 'top top', end: '+=250%', pin: true, scrub: 1, anticipatePin: 1, onToggle: self => root.classList.toggle('pin-own-dial', self.isActive) }
      });
      doors.forEach((door, i) => {
        const at = i * 1.15;
        const dial = $('.door-dial', door);
        const nv = { v: 0 };
        const kids = $$('.door-room > *', door);
        t.fromTo(nv, { v: 0 }, {
          v: i + 1, duration: .45, ease: 'power2.inOut', immediateRender: false,
          onUpdate: () => { setNeedle(dial, rot(nv.v, 4)); lightNum(dial, Math.round(nv.v)); }
        }, at)
          .to($('.leaf-l', door), { xPercent: -101, duration: .85, ease: 'power2.inOut' }, at + .35)
          .to($('.leaf-r', door), { xPercent: 101, duration: .85, ease: 'power2.inOut' }, at + .35)
          .from(kids, { y: 34, autoAlpha: 0, duration: .5, stagger: .045, ease: 'power2.out' }, at + .6)
          .fromTo($('.door-emblem', door), { strokeDasharray: 1, strokeDashoffset: 1 }, { strokeDashoffset: 0, duration: .8, ease: 'power1.inOut' }, at + .55);
        // Clavier : un lien focalisé derrière une porte fait défiler jusqu’à son ouverture.
        door.addEventListener('focusin', () => {
          const st = t.scrollTrigger;
          if (!st) return;
          const y = st.start + (st.end - st.start) * ((at + 1.25) / t.duration());
          if (Math.abs(scrollY - y) > 20) lenis ? lenis.scrollTo(y, { immediate: true }) : scrollTo(0, y);
        });
      });
      // Aiguilles au repos sur « E » avant l’ouverture
      doors.forEach(door => { const d = $('.door-dial', door); setNeedle(d, rot(0, 4)); lightNum(d, 0); });
      t.to({}, { duration: .5 });
      pins.set($('.hall'), t.scrollTrigger);
    } else {
      doors.forEach(door => {
        const dial = $('.door-dial', door);
        const nv = { v: 0 };
        setNeedle(dial, rot(0, 4)); lightNum(dial, 0);
        const target = +dial.dataset.target;
        const t = gsap.timeline({ scrollTrigger: { trigger: door, start: 'top 72%', end: 'top 12%', scrub: 1 } });
        t.to(nv, { v: target, duration: .4, onUpdate: () => { setNeedle(dial, rot(nv.v, 4)); lightNum(dial, Math.round(nv.v)); } }, 0)
          .to($('.leaf-l', door), { xPercent: -101, duration: 1, ease: 'power2.inOut' }, .2)
          .to($('.leaf-r', door), { xPercent: 101, duration: 1, ease: 'power2.inOut' }, .2)
          .from($$('.door-room > *', door), { y: 26, autoAlpha: 0, duration: .5, stagger: .05 }, .6)
          .fromTo($('.door-emblem', door), { strokeDasharray: 1, strokeDashoffset: 1 }, { strokeDashoffset: 0, duration: .8 }, .5);
      });
    }

    /* 3 · Salon : l’arche et la citation */
    gsap.fromTo('.arch-frame img', { yPercent: -12 }, {
      yPercent: 0, ease: 'none',
      scrollTrigger: { trigger: '.arch', start: 'top bottom', end: 'bottom top', scrub: true }
    });
    gsap.fromTo('.arch-frame', { clipPath: 'inset(100% 0% 0% 0%)' }, {
      clipPath: 'inset(0% 0% 0% 0%)', duration: 1.6, ease: LUX,
      scrollTrigger: { trigger: '.arch', start: 'top 82%', once: true },
      onComplete() { this.targets()[0].style.removeProperty('clip-path'); }
    });
    if (desk) {
      gsap.fromTo('.salon-quote .q1', { xPercent: -6 }, { xPercent: 2, ease: 'none', scrollTrigger: { trigger: '.salon-quote', start: 'top bottom', end: 'bottom top', scrub: true } });
      gsap.fromTo('.salon-quote .q2', { xPercent: 6 }, { xPercent: -2, ease: 'none', scrollTrigger: { trigger: '.salon-quote', start: 'top bottom', end: 'bottom top', scrub: true } });
    }

    /* 4 · Façade des réalisations */
    $$('.bay').forEach((bay, i) => {
      const btn = $('.project-image', bay), img = $('img', bay);
      gsap.fromTo(btn, { clipPath: 'inset(100% 0% 0% 0%)' }, {
        clipPath: 'inset(0% 0% 0% 0%)', duration: 1.5, ease: LUX, delay: (i % 4) * .09,
        scrollTrigger: { trigger: '.facade', start: 'top 80%', once: true },
        onComplete: () => btn.style.removeProperty('clip-path')
      });
      gsap.fromTo(img, { scale: 1.35 }, { scale: 1.06, duration: 1.9, ease: 'expo.out', delay: (i % 4) * .09, scrollTrigger: { trigger: '.facade', start: 'top 80%', once: true } });
      if (desk) {
        const inner = i === 1 || i === 2;
        gsap.fromTo(bay, { y: inner ? 90 : 30 }, { y: inner ? -50 : -10, ease: 'none', scrollTrigger: { trigger: '.facade', start: 'top bottom', end: 'bottom top', scrub: true } });
      }
    });

    /* 5 · Méthode : l’ascenseur monte de 1 à 4 */
    if (desk) {
      const steps = $$('.method .step');
      const reel = $('.numeral-reel'), cabin = $('.shaft-cabin'), rail = $('.shaft-rail');
      const mdial = $('.numeral-dial');
      gsap.set(steps.slice(1), { autoAlpha: 0, yPercent: 30 });
      const t = gsap.timeline({
        scrollTrigger: { trigger: '.method', start: 'top top', end: '+=260%', pin: true, scrub: 1, anticipatePin: 1, onToggle: self => root.classList.toggle('pin-own-dial', self.isActive) }
      });
      t.to({}, { duration: .35 });
      const mv = { v: 0 };
      for (let k = 1; k < 4; k++) {
        const at = .35 + (k - 1) * 1.1;
        t.to(reel, { yPercent: -100 * k, duration: .75, ease: 'power3.inOut' }, at)
          .to(cabin, { y: () => -(rail.offsetHeight - cabin.offsetHeight) * k / 3, duration: .75, ease: 'power2.inOut' }, at)
          .to(steps[k - 1], { autoAlpha: 0, yPercent: -30, duration: .4, ease: 'power2.in' }, at)
          .to(steps[k], { autoAlpha: 1, yPercent: 0, duration: .5, ease: 'power2.out' }, at + .3)
          .to(mv, { v: k, duration: .75, ease: 'power3.inOut', onUpdate: () => { setNeedle(mdial, rot(mv.v, 4)); lightNum(mdial, Math.round(mv.v)); } }, at);
      }
      t.to({}, { duration: .4 });
      pins.set($('.method'), t.scrollTrigger);
    }
  });

  /* ------------------------------------------------------------------------
     En-tête : thème sombre sur les salons bruns
     ------------------------------------------------------------------------ */
  const lobby = $('.lobby');
  const darkSecs = $$('.dark');
  let onDark = null;
  const syncHeader = () => {
    const y = 40;
    const d = darkSecs.some(sec => { const r = sec.getBoundingClientRect(); return r.top <= y && r.bottom > y; });
    if (d !== onDark) { onDark = d; lobby.classList.toggle('on-dark', d); }
  };
  if (lenis) lenis.on('scroll', syncHeader);
  addEventListener('scroll', syncHeader, { passive: true });
  ScrollTrigger.addEventListener('refresh', syncHeader);
  syncHeader();

  /* ------------------------------------------------------------------------
     Indicateur d’étage : l’aiguille suit la progression de la page
     ------------------------------------------------------------------------ */
  const floorEl = $('.floor'), floorDial = $('.floor-dial'), floorName = $('.floor-name');
  const floorSecs = $$('[data-floor]');
  let curFloor = 0;
  const needleState = { v: 0 };
  const needleTo = gsap.quickTo(needleState, 'v', { duration: .7, ease: 'power3.out', onUpdate: () => setNeedle(floorDial, rot(needleState.v, 8)) });
  floorSecs.forEach(sec => {
    const idx = +sec.dataset.floor;
    ScrollTrigger.create({
      trigger: sec, start: 'top center', end: 'bottom center',
      onUpdate: self => {
        needleTo(Math.max(0, Math.min(7, idx - .5 + self.progress)));
      },
      onToggle: self => {
        if (!self.isActive || curFloor === idx) return;
        curFloor = idx;
        lightNum(floorDial, idx);
        gsap.timeline()
          .to(floorName, { yPercent: -60, autoAlpha: 0, duration: .25, ease: 'power2.in' })
          .add(() => { floorName.textContent = sec.dataset.floorName; })
          .fromTo(floorName, { yPercent: 60, autoAlpha: 0 }, { yPercent: 0, autoAlpha: 1, duration: .4, ease: 'power3.out' });
      }
    });
  });
  if (floorEl && !root.classList.contains('intro')) gsap.set(floorEl, { autoAlpha: 1 });

  /* ------------------------------------------------------------------------
     Révélations typographiques et ornements
     ------------------------------------------------------------------------ */
  const reveals = () => {
    if (hasSplit) {
      $$('[data-split]').forEach(el => {
        window.SplitText.create(el, {
          type: 'lines', mask: 'lines', linesClass: 'split-line', autoSplit: true, aria: el.tagName === 'SPAN' ? 'none' : 'auto',
          onSplit: self => gsap.from(self.lines, {
            yPercent: 112, duration: 1.4, ease: 'expo.out', stagger: .09,
            scrollTrigger: { trigger: el, start: 'top 88%', once: true }
          })
        });
      });
    }
    ScrollTrigger.batch('[data-rise]', {
      start: 'top 92%', once: true,
      onEnter: els => gsap.to(els, { autoAlpha: 1, y: 0, duration: 1.2, ease: 'expo.out', stagger: .08 })
    });
    $$('.draw').forEach(svg => {
      if (svg.closest('.door')) return;
      gsap.fromTo(svg, { strokeDasharray: 1, strokeDashoffset: 1 }, {
        strokeDashoffset: 0, duration: 2.2, ease: 'power2.inOut',
        scrollTrigger: { trigger: svg, start: 'top 90%', once: true }
      });
    });
    $$('.eyebrow').forEach(e => {
      if (e.closest('.hero') || e.closest('dialog')) return;
      gsap.from(e, { autoAlpha: 0, letterSpacing: '.6em', duration: 1.4, ease: 'expo.out', scrollTrigger: { trigger: e, start: 'top 92%', once: true } });
    });
    ScrollTrigger.refresh();
  };
  gsap.set('[data-rise]', { autoAlpha: 0, y: 40 });
  (document.fonts && document.fonts.ready ? document.fonts.ready : Promise.resolve()).then(reveals);

  /* ------------------------------------------------------------------------
     Ancres : défilement Lenis (tient compte des sections épinglées)
     ------------------------------------------------------------------------ */
  const headerH = () => lobby.offsetHeight;
  $$('a[href^="#"]').forEach(a => a.addEventListener('click', e => {
    const id = a.getAttribute('href');
    if (!lenis) return;
    if (id === '#') { e.preventDefault(); startScroll(); lenis.scrollTo(0, { duration: 1.8 }); return; }
    const target = document.querySelector(id);
    if (!target) return;
    e.preventDefault();
    startScroll();
    const pinned = pins.get(target);
    let y;
    if (pinned) y = pinned.start + (target === hero ? 0 : 2);
    else y = target.getBoundingClientRect().top + scrollY - (target.id === 'principal' ? 0 : headerH() - 1);
    const dist = Math.abs(y - scrollY);
    lenis.scrollTo(y, { duration: Math.min(2.4, .9 + dist / 5000), easing: t => 1 - Math.pow(1 - t, 4) });
    if (!target.hasAttribute('tabindex')) target.setAttribute('tabindex', '-1');
    target.focus({ preventScroll: true });
  }));

  /* ------------------------------------------------------------------------
     Curseur et boutons magnétiques (pointeur fin uniquement)
     ------------------------------------------------------------------------ */
  if (fine) {
    root.classList.add('has-cursor');
    const cur = $('.cursor'), dot = $('.cursor-dot'), sun = $('.cursor-sun');
    const dx = gsap.quickTo(dot, 'x', { duration: .08, ease: 'power3' }), dy = gsap.quickTo(dot, 'y', { duration: .08, ease: 'power3' });
    const sxq = gsap.quickTo(sun, 'x', { duration: .5, ease: 'power3' }), syq = gsap.quickTo(sun, 'y', { duration: .5, ease: 'power3' });
    gsap.set([dot, sun], { x: -100, y: -100 });
    addEventListener('pointermove', e => { dx(e.clientX); dy(e.clientY); sxq(e.clientX); syq(e.clientY); }, { passive: true });
    document.addEventListener('pointerover', e => {
      cur.classList.toggle('is-hover', !!e.target.closest('a, button, summary, label, .project-image'));
    });
    document.addEventListener('pointerleave', () => gsap.to(cur, { autoAlpha: 0, duration: .3 }));
    document.addEventListener('pointerenter', () => gsap.to(cur, { autoAlpha: 1, duration: .3 }));

    $$('.magnetic').forEach(el => {
      const xTo = gsap.quickTo(el, 'x', { duration: .7, ease: 'power3' });
      const yTo = gsap.quickTo(el, 'y', { duration: .7, ease: 'power3' });
      el.addEventListener('pointermove', e => {
        const r = el.getBoundingClientRect();
        xTo((e.clientX - r.left - r.width / 2) * .22);
        yTo((e.clientY - r.top - r.height / 2) * .32);
      });
      el.addEventListener('pointerleave', () => { xTo(0); yTo(0); });
    });
  }

  addEventListener('load', () => ScrollTrigger.refresh());
  };
  const fontsOk = document.fonts && document.fonts.ready ? document.fonts.ready : Promise.resolve();
  Promise.race([fontsOk, new Promise(r => setTimeout(r, 900))]).then(boot);
})();
