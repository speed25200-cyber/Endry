'use strict';
/* ==========================================================================
   Endry SA — Maquette XV · Matière
   Mise en scène : intro « échantillons qui tombent et s’assemblent », matières
   physiques en WebGL (lampe mobile = pointeur), expertises épinglées (la
   matière change au défilement), planche de réalisations qui se recompose,
   éventail de la méthode, curseur « pastille-échantillon », boutons magnétiques.
   Dégradation : sans JS / mouvement réduit / sans WebGL → matières CSS statiques.
   ========================================================================== */
(() => {
  const html = document.documentElement;
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const hasLibs = window.gsap && window.ScrollTrigger && window.SplitText && window.CustomEase;
  if (reduce || !hasLibs) { html.classList.remove('intro'); return; }

  const { gsap, ScrollTrigger, SplitText, CustomEase } = window;
  gsap.registerPlugin(ScrollTrigger, SplitText, CustomEase);
  CustomEase.create('lux', '0.7,0,0.2,1');
  CustomEase.create('drop', '0.16,1,0.3,1');

  const qs = (s, r = document) => r.querySelector(s);
  const qsa = (s, r = document) => [...r.querySelectorAll(s)];
  const fine = window.matchMedia('(hover: hover) and (pointer: fine)').matches;
  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));

  /* ------------------------------------------------------------------------
     Défilement fluide (Lenis) synchronisé avec ScrollTrigger
     ------------------------------------------------------------------------ */
  let lenis = null;
  if (window.Lenis) {
    lenis = new window.Lenis({ lerp: 0.085, wheelMultiplier: 0.95, smoothWheel: true });
    lenis.on('scroll', ScrollTrigger.update);
    gsap.ticker.add((t) => lenis.raf(t * 1000));
    gsap.ticker.lagSmoothing(0);
  }
  qsa('dialog').forEach((d) => d.setAttribute('data-lenis-prevent', ''));

  const headerH = () => qs('.x-header').offsetHeight;
  const scrollToTarget = (target) => {
    let y = 0;
    if (target) {
      const pt = target.matches('.x-rz') ? 0 : parseFloat(getComputedStyle(target).paddingTop) || 0;
      y = target.getBoundingClientRect().top + window.scrollY + pt - headerH() - 18;
      if (target.matches('.x-rz')) y = target.getBoundingClientRect().top + window.scrollY;
    }
    if (lenis) lenis.scrollTo(Math.max(0, y), { duration: 1.6, easing: (t) => 1 - Math.pow(1 - t, 4) });
    else window.scrollTo({ top: Math.max(0, y), behavior: 'smooth' });
  };
  qsa('a[href^="#"]').forEach((a) => a.addEventListener('click', (e) => {
    const id = a.getAttribute('href');
    if (id === '#') { e.preventDefault(); scrollToTarget(null); return; }
    const t = document.querySelector(id);
    if (!t) return;
    e.preventDefault();
    if (lenis) lenis.start();
    scrollToTarget(t);
    t.setAttribute('tabindex', '-1');
    t.focus({ preventScroll: true });
  }));

  // Menu mobile et dialogues : Lenis à l’arrêt tant qu’ils sont ouverts
  const nav = qs('#navigation');
  const syncLock = () => {
    if (!lenis) return;
    const locked = (nav && nav.classList.contains('open')) || qsa('dialog').some((d) => d.open);
    if (locked) lenis.stop(); else lenis.start();
  };
  const mo = new MutationObserver(syncLock);
  if (nav) mo.observe(nav, { attributes: true, attributeFilter: ['class'] });
  qsa('dialog').forEach((d) => mo.observe(d, { attributes: true, attributeFilter: ['open'] }));

  /* ------------------------------------------------------------------------
     Matières physiques en WebGL — une toile par grande tuile
     0 travertin adouci · 1 bronze brossé · 2 laiton poli · 3 lin naturel
     ------------------------------------------------------------------------ */
  const MAT = { travertin: 0, bronze: 1, laiton: 2, lin: 3 };
  const VS = 'attribute vec2 aP;varying vec2 vUv;void main(){vUv=aP*.5+.5;gl_Position=vec4(aP,0.,1.);}';
  const FS = `
#extension GL_OES_standard_derivatives : enable
precision highp float;
varying vec2 vUv;
uniform vec2 uSize;
uniform float uDpr;
uniform vec3 uLamp;
uniform float uTime;
uniform float uA;
uniform float uB;
uniform float uMix;
uniform vec2 uTilt;
uniform float uBoost;

float hash(vec2 p){vec3 p3=fract(vec3(p.xyx)*.1031);p3+=dot(p3,p3.yzx+33.33);return fract((p3.x+p3.y)*p3.z);}
float noise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);vec2 u=f*f*(3.-2.*f);
  return mix(mix(hash(i),hash(i+vec2(1.,0.)),u.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),u.x),u.y);}
float fbm(vec2 p){float s=0.;float a=.5;for(int i=0;i<5;i++){s+=a*noise(p);p=p*2.02+vec2(11.7,5.3);a*=.5;}return s;}

/* Travertin adouci : lits horizontaux, veines, pores allongés */
vec4 matTravertin(vec2 p, out vec4 prm){
  vec2 q=p/380.;
  float w=fbm(q*1.4+2.7);
  float band=fbm(vec2(q.x*.5,q.y*4.6+w*1.8));
  vec3 c=mix(vec3(.935,.89,.815),vec3(.865,.795,.695),smoothstep(.34,.72,band));
  float v1=1.-smoothstep(0.,.016,abs(band-.52));
  float v2=1.-smoothstep(0.,.011,abs(band-.405));
  c=mix(c,vec3(.77,.67,.53),v1*.42+v2*.3);
  float cluster=smoothstep(.5,.74,fbm(q*2.6+5.));
  float pore=smoothstep(.8,.9,noise(vec2(p.x/12.,p.y/3.4)+13.))*cluster;
  pore=max(pore,smoothstep(.86,.93,noise(vec2(p.x/26.,p.y/5.2)+3.))*cluster);
  c=mix(c,vec3(.7,.6,.47),pore*.5);
  float grain=noise(p*.7)*.022;
  c+=grain-.011;
  prm=vec4(.55,0.,0.,.5);
  return vec4(c,band*3.-pore*2.6+grain*5.);
}
/* Bronze brossé : stries horizontales, nuages de patine */
vec4 matBronze(vec2 p, out vec4 prm){
  float s1=noise(vec2(p.x/260.,p.y*1.6));
  float s2=noise(vec2(p.x/70.,p.y*4.3)+7.);
  float s3=noise(vec2(p.x/900.,p.y*.3)+3.);
  float s4=noise(vec2(p.x/22.,p.y*9.7)+1.);
  float streak=s1*.34+s2*.3+s3*.2+s4*.16;
  float cloud=fbm(p/520.+1.7);
  vec3 c=mix(vec3(.65,.465,.235),vec3(.78,.575,.315),streak);
  c=mix(c,vec3(.62,.45,.22),smoothstep(.5,.8,cloud)*.3);
  prm=vec4(.3,1.,1.,streak);
  return vec4(c,streak*1.3);
}
/* Laiton poli : miroir doux, micro-rayures */
vec4 matLaiton(vec2 p, out vec4 prm){
  float cloud=fbm(p/650.+4.2);
  vec3 c=mix(vec3(.85,.67,.38),vec3(.93,.78,.5),cloud);
  float sc=smoothstep(.95,.995,noise(vec2(p.x*.05+p.y*.02,p.y*.9)+2.))*smoothstep(.55,.8,fbm(p/200.));
  c+=sc*.025;
  float band=smoothstep(.2,.9,sin((p.x*.6-p.y)/uSize.y*4.+.7)*.5+.5);
  c*=.95+.09*band;
  prm=vec4(.1,1.,0.,.5);
  return vec4(c,cloud*.6+sc*3.);
}
/* Lin naturel : armure toile, fils irréguliers, fibres */
vec4 matLin(vec2 p, out vec4 prm){
  vec2 g=p/4.6;
  vec2 cell=floor(g);vec2 f=fract(g);
  float slubX=noise(vec2(g.x*.07,cell.y*.73));
  float slubY=noise(vec2(cell.x*.61,g.y*.07));
  float warp=sin(f.x*3.14159);
  float weft=sin(f.y*3.14159);
  float chk=mod(cell.x+cell.y,2.);
  float h=chk>.5?warp*(.7+.6*slubY)+.25*weft:weft*(.7+.6*slubX)+.25*warp;
  vec3 c=vec3(.925,.888,.826)*(.95+.07*fbm(p/42.));
  c-=vec3(.05,.05,.045)*smoothstep(.72,.95,chk>.5?slubY:slubX);
  c-=vec3(.07,.075,.08)*smoothstep(.955,.99,noise(p*.45+9.));
  c*=.94+.06*h;
  prm=vec4(.85,0.,0.,.5);
  return vec4(c,h*1.15);
}
vec4 mat(float id, vec2 p, out vec4 prm){
  if(id<.5) return matTravertin(p,prm);
  if(id<1.5) return matBronze(p,prm);
  if(id<2.5) return matLaiton(p,prm);
  return matLin(p,prm);
}
vec3 shade(vec3 alb, float h, vec4 prm, vec2 p){
  vec2 grad=vec2(dFdx(h),-dFdy(h))*uDpr;
  vec3 N=normalize(vec3(-grad*.9,1.));
  float ex=min(p.x,uSize.x-p.x);float ey=min(p.y,uSize.y-p.y);
  float bev=1.-smoothstep(0.,4.,min(ex,ey));
  vec2 o=ex<ey?vec2(p.x<uSize.x*.5?-1.:1.,0.):vec2(0.,p.y<uSize.y*.5?-1.:1.);
  N=normalize(vec3(N.xy+o*bev*.9+uTilt,N.z));
  vec3 P=vec3(p,0.);
  vec3 Lv=uLamp-P;float d=length(Lv);vec3 L=Lv/d;
  vec3 V=normalize(vec3(uSize.x*.5,uSize.y*.35,1800.)-P);
  vec3 H=normalize(L+V);
  float ndl=max(dot(N,L),0.);
  float reach=max(uSize.x,uSize.y);
  float att=1./(1.+pow(d/(reach*.8),2.));
  float rough=prm.x;float metal=prm.y;float aniso=prm.z;
  float shin=exp2(11.*(1.-rough)+1.);
  float iso=pow(max(dot(N,H),0.),shin)*(shin+8.)/60.;
  vec3 T=normalize(vec3(1.,(prm.w-.5)*.9,0.));
  T=normalize(T-N*dot(N,T));
  float th=dot(T,H);float sT=sqrt(max(0.,1.-th*th));
  float kk=pow(sT,700.)*1.35+pow(sT,60.)*.3+pow(sT,8.)*.06;
  float spec=mix(iso,kk,aniso);
  vec3 F0=mix(vec3(.04),alb,metal);
  vec2 r=(p/uSize)+N.xy*2.2;
  float env=.5+.5*sin((r.x*1.1-r.y*.8)*3.1+1.2+uTime*.03);
  env=mix(.96,1.08,smoothstep(.15,.9,env));
  vec3 base=mix(alb*(.94+.06*N.z),alb*env,metal);
  vec3 lampCol=vec3(1.,.95,.86);
  vec3 col=base+alb*(1.-metal*.55)*ndl*att*mix(.17,.22,metal)*uBoost+F0*lampCol*spec*att*uBoost*(.45+.45*metal);
  float l=dot(col,vec3(.2126,.7152,.0722));
  float lm=l>.72?.72+.28*(1.-exp(-(l-.72)*3.)):l;
  col*=lm/max(l,1e-4);
  col=mix(col,vec3(1.,.94,.82)*lm*1.08,smoothstep(.7,1.,lm)*.55);
  return min(col,vec3(1.));
}
void main(){
  vec2 p=vec2(vUv.x,1.-vUv.y)*uSize;
  vec4 pa;vec4 a=mat(uA,p,pa);
  vec3 col=shade(a.rgb,a.a,pa,p);
  if(uMix>.001){
    vec4 pb;vec4 b=mat(uB,p,pb);
    vec3 colB=shade(b.rgb,b.a,pb,p);
    float n=fbm(p/300.+9.)*.75+noise(p/22.)*.25;
    n=mix(n,1.-p.y/uSize.y,.45);
    float t=uMix*1.16-.08;
    float m=smoothstep(t-.012,t+.012,n);
    col=mix(colB,col,m);
    float edge=1.-smoothstep(0.,.009,abs(n-t));
    float halo=1.-smoothstep(0.,.05,abs(n-t));
    float on=smoothstep(0.,.04,uMix)*smoothstep(1.,.96,uMix);
    col=mix(col,vec3(1.,.93,.8),edge*.75*on);
    col+=vec3(.2,.14,.06)*halo*on*.3;
  }
  gl_FragColor=vec4(col,1.);
}`;

  const pointer = { x: -9999, y: -9999, seen: false };
  const onPointer = (x, y) => { pointer.x = x; pointer.y = y; pointer.seen = true; };
  window.addEventListener('pointermove', (e) => onPointer(e.clientX, e.clientY), { passive: true });
  window.addEventListener('touchmove', (e) => { const t = e.touches[0]; if (t) onPointer(t.clientX, t.clientY); }, { passive: true });

  const surfaces = [];
  function createSurface(tile, opts) {
    const canvas = document.createElement('canvas');
    canvas.className = 'x-gl';
    canvas.setAttribute('aria-hidden', 'true');
    let gl = null;
    try { gl = canvas.getContext('webgl', { antialias: false, alpha: false, depth: false, stencil: false, powerPreference: 'high-performance' }); } catch (e) { gl = null; }
    if (!gl || !gl.getExtension('OES_standard_derivatives')) return null;
    const sh = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); return gl.getShaderParameter(s, gl.COMPILE_STATUS) ? s : null; };
    const vs = sh(gl.VERTEX_SHADER, VS), fs = sh(gl.FRAGMENT_SHADER, FS);
    if (!vs || !fs) return null;
    const prog = gl.createProgram();
    gl.attachShader(prog, vs); gl.attachShader(prog, fs); gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) return null;
    gl.useProgram(prog);
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(prog, 'aP');
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
    const u = {};
    ['uSize', 'uDpr', 'uLamp', 'uTime', 'uA', 'uB', 'uMix', 'uTilt', 'uBoost'].forEach((n) => { u[n] = gl.getUniformLocation(prog, n); });

    const before = opts.before ? qs(opts.before, tile) : tile.firstChild;
    tile.insertBefore(canvas, before);
    tile.classList.add('has-gl');

    const s = {
      tile, canvas, gl, u,
      w: 0, h: 0, dpr: 1, visible: false, drawn: false, lost: false,
      lamp: { x: 0, y: 0, init: false }, boost: 1, tilt: { x: 0, y: 0 }, tiltTarget: { x: 0, y: 0 },
      a: opts.mat, b: opts.mat, mix: 0, seed: Math.random() * 10,
      getMats: opts.getMats || null
    };
    const resize = () => {
      const r = canvas.getBoundingClientRect();
      const w = canvas.clientWidth || r.width, h = canvas.clientHeight || r.height;
      if (!w || !h) return;
      s.w = w; s.h = h;
      s.dpr = Math.min(window.devicePixelRatio || 1, 2, Math.sqrt(1.7e6 / (w * h)));
      canvas.width = Math.round(w * s.dpr);
      canvas.height = Math.round(h * s.dpr);
      gl.viewport(0, 0, canvas.width, canvas.height);
      s.drawn = false;
    };
    s.resize = resize;
    new ResizeObserver(resize).observe(canvas);
    new IntersectionObserver((es) => { s.visible = es[0].isIntersecting; }, { rootMargin: '80px' }).observe(tile);
    canvas.addEventListener('webglcontextlost', (e) => { e.preventDefault(); s.lost = true; canvas.remove(); tile.classList.remove('has-gl'); });
    resize();
    surfaces.push(s);
    return s;
  }

  function renderSurface(s, time) {
    if (s.lost || !s.w || !s.h) return;
    const { gl, u } = s;
    const r = s.canvas.getBoundingClientRect();
    if (r.width < 2 || r.height < 2) return;
    // Lampe : suit le pointeur (où qu’il soit), sinon dérive lente
    let tx, ty, inside = false;
    if (pointer.seen) {
      tx = (pointer.x - r.left) * (s.w / r.width);
      ty = (pointer.y - r.top) * (s.h / r.height);
      inside = tx > 0 && ty > 0 && tx < s.w && ty < s.h;
    } else {
      tx = s.w * (0.5 + 0.34 * Math.sin(time * 0.33 + s.seed));
      ty = s.h * (0.42 + 0.3 * Math.sin(time * 0.24 + s.seed * 1.7));
    }
    if (!s.lamp.init) { s.lamp.x = tx; s.lamp.y = ty; s.lamp.init = true; }
    s.lamp.x += (tx - s.lamp.x) * 0.075;
    s.lamp.y += (ty - s.lamp.y) * 0.075;
    s.boost += ((inside ? 1.25 : 0.95) - s.boost) * 0.05;
    s.tilt.x += (s.tiltTarget.x - s.tilt.x) * 0.1;
    s.tilt.y += (s.tiltTarget.y - s.tilt.y) * 0.1;
    if (s.getMats) { const m = s.getMats(); s.a = m[0]; s.b = m[1]; s.mix = m[2]; }
    gl.uniform2f(u.uSize, s.w, s.h);
    gl.uniform1f(u.uDpr, s.dpr);
    gl.uniform3f(u.uLamp, s.lamp.x, s.lamp.y, Math.max(s.w, s.h) * 0.3);
    gl.uniform1f(u.uTime, time);
    gl.uniform1f(u.uA, s.a);
    gl.uniform1f(u.uB, s.b);
    gl.uniform1f(u.uMix, s.mix);
    gl.uniform2f(u.uTilt, s.tilt.x, s.tilt.y);
    gl.uniform1f(u.uBoost, s.boost);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    if (!s.drawn) { s.drawn = true; s.canvas.classList.add('is-on'); }
  }
  gsap.ticker.add((time) => {
    if (document.hidden) return;
    for (const s of surfaces) if (s.visible) renderSurface(s, time);
  });
  const surfaceOf = (el) => surfaces.find((s) => s.tile === el);

  const heroPlate = qs('.x-plate');
  if (heroPlate) createSurface(heroPlate, { mat: MAT.bronze });
  const plaque = qs('.x-plaque');
  if (plaque) createSurface(plaque, { mat: MAT.laiton });

  /* ------------------------------------------------------------------------
     Intro : les échantillons tombent en pile, puis s’assemblent en bento
     ------------------------------------------------------------------------ */
  const hero = qs('.x-hero');
  const board = qs('.x-hero__board');
  const heroTiles = qsa('.x-hero__board > .x-tile');
  let introDone = false;

  function heroAfter() {
    introDone = true;
    // Profondeur au défilement : chaque échantillon glisse à sa vitesse
    const depth = [-40, -90, -130, -60];
    if (window.innerWidth > 900) heroTiles.forEach((t, i) => {
      gsap.to(t, { y: depth[i] || -60, ease: 'none', scrollTrigger: { trigger: hero, start: 'top top', end: 'bottom top', scrub: true } });
    });
    gsap.to('.x-hero__mask img', { scale: 1.14, yPercent: 6, ease: 'none', scrollTrigger: { trigger: hero, start: 'top top', end: 'bottom top', scrub: true } });
    gsap.to('.x-h1a', { xPercent: -6, ease: 'none', scrollTrigger: { trigger: hero, start: 'top top', end: 'bottom top', scrub: true } });
    gsap.to('.x-h1b', { xPercent: 8, ease: 'none', scrollTrigger: { trigger: hero, start: 'top top', end: 'bottom top', scrub: true } });
    setupTilt();
  }

  function runIntro() {
    const h1a = qs('.x-h1a'), h1b = qs('.x-h1b');
    const mask = qs('.x-hero__mask'), img = qs('.x-hero__mask img');
    const meta = qs('.x-hero__meta');
    const contents = qsa('.x-hero__board [data-i="content"], .x-hero__board .x-chip, .x-hero__note, .x-lamp-hint');
    const skip = window.scrollY > 40;
    if (skip) { html.classList.remove('intro'); heroAfter(); return; }

    const sa = SplitText.create(h1a, { type: 'chars', mask: 'chars' });
    const sb = SplitText.create(h1b, { type: 'lines', mask: 'lines' });

    // Mesures FLIP : position finale de chaque tuile → pile au centre de l’écran
    const vw = window.innerWidth, vh = window.innerHeight;
    const chipW = Math.min(190, vw * 0.34), chipH = chipW * 1.32;
    const cx = vw / 2, cy = Math.min(vh * 0.56, board.getBoundingClientRect().top + 260);
    const rot = [-9, 6, -3, 8];
    const pile = heroTiles.map((t, i) => {
      const r = t.getBoundingClientRect();
      return {
        x: cx - (r.left + r.width / 2) + (i - 1.5) * 10,
        y: cy - (r.top + r.height / 2) + (i - 1.5) * -6,
        sx: chipW / r.width, sy: chipH / r.height
      };
    });
    heroTiles.forEach((t, i) => gsap.set(t, {
      x: pile[i].x, y: pile[i].y - vh * 0.95, scaleX: pile[i].sx, scaleY: pile[i].sy,
      rotation: rot[i] * 2.2, rotationX: 55, transformPerspective: 900, transformOrigin: '50% 50%'
    }));
    gsap.set(contents, { opacity: 0, y: 14 });
    gsap.set(mask, { clipPath: 'inset(100% 0% 0% 0%)' });
    gsap.set(img, { scale: 1.35 });
    gsap.set(sa.chars, { yPercent: 115 });
    gsap.set(sb.lines, { yPercent: 115 });
    gsap.set(meta, { opacity: 0, y: -8 });
    html.classList.remove('intro');

    const tl = gsap.timeline({
      delay: 0.05,
      onComplete() {
        gsap.set(heroTiles, { clearProps: 'transform' });
        gsap.set(contents, { clearProps: 'opacity,transform' });
        gsap.set([mask, img], { clearProps: 'clipPath,transform' });
        sa.revert(); sb.revert();
        heroAfter();
      }
    });
    window.__xvIntro = tl; // (revue : permet d’inspecter la chorégraphie)
    // 1. chute : les échantillons tombent l’un après l’autre sur la table
    heroTiles.forEach((t, i) => {
      tl.to(t, { y: pile[i].y, rotationX: 0, rotation: rot[i], duration: 0.72, ease: 'drop' }, 0.08 * i);
    });
    tl.to(meta, { opacity: 1, y: 0, duration: 0.7, ease: 'power2.out' }, 0.1);
    // 2. assemblage : chaque échantillon glisse à sa place dans la planche
    tl.to(heroTiles, { x: 0, y: 0, scaleX: 1, scaleY: 1, rotation: 0, duration: 1.0, ease: 'lux', stagger: { each: 0.05, from: 'end' } }, 0.86);
    // 3. la tuile image s’ouvre par un masque
    tl.to(mask, { clipPath: 'inset(0% 0% 0% 0%)', duration: 0.95, ease: 'lux' }, 1.18);
    tl.to(img, { scale: 1, duration: 1.3, ease: 'expo.out' }, 1.2);
    // 4. le titre se révèle
    tl.to(sa.chars, { yPercent: 0, duration: 0.9, ease: 'expo.out', stagger: 0.022 }, 1.2);
    tl.to(sb.lines, { yPercent: 0, duration: 0.85, ease: 'expo.out', stagger: 0.08 }, 1.42);
    tl.to(contents, { opacity: 1, y: 0, duration: 0.6, ease: 'power2.out', stagger: 0.025 }, 1.5);
  }

  /* ------------------------------------------------------------------------
     Inclinaison 3D + reflet spéculaire (et inclinaison de la normale en WebGL)
     ------------------------------------------------------------------------ */
  function setupTilt() {
    if (!fine) return;
    qsa('[data-tilt]').forEach((el) => {
      if (el.dataset.tiltReady) return;
      el.dataset.tiltReady = '1';
      const big = el.offsetWidth > 700;
      const max = big ? 2.2 : 5;
      gsap.set(el, { transformPerspective: big ? 1800 : 1000 });
      const rx = gsap.quickTo(el, 'rotationX', { duration: 0.9, ease: 'power3.out' });
      const ry = gsap.quickTo(el, 'rotationY', { duration: 0.9, ease: 'power3.out' });
      el.addEventListener('pointermove', (e) => {
        if (e.pointerType !== 'mouse') return;
        const r = el.getBoundingClientRect();
        const nx = (e.clientX - r.left) / r.width - 0.5, ny = (e.clientY - r.top) / r.height - 0.5;
        rx(-ny * max); ry(nx * max);
        el.style.setProperty('--mx', ((nx + 0.5) * 100).toFixed(1) + '%');
        el.style.setProperty('--my', ((ny + 0.5) * 100).toFixed(1) + '%');
        el.style.setProperty('--spec', '1');
        const s = surfaceOf(el);
        if (s) { s.tiltTarget.x = nx * 0.16; s.tiltTarget.y = ny * 0.16; }
      });
      el.addEventListener('pointerleave', () => {
        rx(0); ry(0);
        el.style.setProperty('--spec', '0');
        const s = surfaceOf(el);
        if (s) { s.tiltTarget.x = 0; s.tiltTarget.y = 0; }
      });
    });
  }

  /* ------------------------------------------------------------------------
     Boutons magnétiques
     ------------------------------------------------------------------------ */
  if (fine) {
    qsa('[data-magnetic]').forEach((el) => {
      const inner = qs('.x-btn__in', el) || el;
      const xTo = gsap.quickTo(el, 'x', { duration: 0.7, ease: 'power3.out' });
      const yTo = gsap.quickTo(el, 'y', { duration: 0.7, ease: 'power3.out' });
      const ixTo = gsap.quickTo(inner, 'x', { duration: 0.7, ease: 'power3.out' });
      const iyTo = gsap.quickTo(inner, 'y', { duration: 0.7, ease: 'power3.out' });
      el.addEventListener('pointermove', (e) => {
        if (e.pointerType !== 'mouse') return;
        const r = el.getBoundingClientRect();
        const dx = e.clientX - (r.left + r.width / 2), dy = e.clientY - (r.top + r.height / 2);
        xTo(dx * 0.26); yTo(dy * 0.4); ixTo(dx * 0.1); iyTo(dy * 0.14);
      });
      el.addEventListener('pointerleave', () => { xTo(0); yTo(0); ixTo(0); iyTo(0); });
    });
  }

  /* ------------------------------------------------------------------------
     Curseur « pastille-échantillon »
     ------------------------------------------------------------------------ */
  const MAT_NAMES = { travertin: 'Travertin', bronze: 'Bronze brossé', laiton: 'Laiton poli', lin: 'Lin naturel', noyer: 'Noyer' };
  if (fine) {
    html.classList.add('has-cursor');
    const cur = document.createElement('div');
    cur.className = 'x-cursor is-hidden';
    cur.setAttribute('aria-hidden', 'true');
    cur.innerHTML = '<span class="x-cursor__dot"></span><span class="x-cursor__label"></span>';
    document.body.append(cur);
    const label = qs('.x-cursor__label', cur);
    const xTo = gsap.quickTo(cur, 'x', { duration: 0.38, ease: 'power3.out' });
    const yTo = gsap.quickTo(cur, 'y', { duration: 0.38, ease: 'power3.out' });
    let lastState = '';
    const setState = (state, mat, text) => {
      const key = state + mat + text;
      if (key === lastState) return;
      lastState = key;
      cur.className = 'x-cursor' + (state ? ' ' + state : '');
      if (mat) cur.dataset.mat = mat; else delete cur.dataset.mat;
      label.textContent = text || '';
    };
    const update = (t) => {
      if (!(t instanceof Element)) return;
      if (t.closest('input, textarea, select, dialog')) return setState('is-hidden');
      if (t.closest('.project-image')) return setState('is-view', '', 'Agrandir');
      const gl = t.closest('.has-gl');
      if (gl && !t.closest('a, button')) return setState('is-mat is-lamp', gl.dataset.mat || '', 'Lampe · ' + (MAT_NAMES[gl.dataset.mat] || ''));
      const m = t.closest('[data-mat]');
      if (m && MAT_NAMES[m.dataset.mat]) return setState('is-mat', m.dataset.mat, MAT_NAMES[m.dataset.mat]);
      if (t.closest('a, button, summary, label')) return setState('is-link');
      setState('');
    };
    let px = -1, py = -1;
    window.addEventListener('pointermove', (e) => {
      if (e.pointerType !== 'mouse') return;
      px = e.clientX; py = e.clientY;
      xTo(px); yTo(py);
      update(e.target);
    }, { passive: true });
    // la page défile sous le curseur : on relit la matière survolée
    let raf = 0;
    window.addEventListener('scroll', () => {
      if (px < 0 || raf) return;
      raf = requestAnimationFrame(() => { raf = 0; update(document.elementFromPoint(px, py)); });
    }, { passive: true });
    document.addEventListener('pointerleave', () => setState('is-hidden'));
    window.addEventListener('blur', () => setState('is-hidden'));
  }

  /* ------------------------------------------------------------------------
     Fond de page qui change de matière (pierre → noyer → pierre)
     et thème de l’en-tête
     ------------------------------------------------------------------------ */
  /* ------------------------------------------------------------------------
     Titres : révélation ligne à ligne (SplitText, masques)
     ------------------------------------------------------------------------ */
  function setupSplits() {
    qsa('[data-split]').forEach((el) => {
      SplitText.create(el, {
        type: 'lines', mask: 'lines', autoSplit: true, linesClass: 'x-line',
        onSplit(self) {
          return gsap.from(self.lines, {
            yPercent: 112, duration: 1.35, ease: 'expo.out', stagger: 0.11,
            scrollTrigger: { trigger: el, start: 'top 86%', once: true }
          });
        }
      });
    });
  }

  // Tuiles inclinables avec apparition : révélées par GSAP (pas de transition CSS sur transform)
  const tiltReveal = qsa('[data-tilt][data-reveal]');
  tiltReveal.forEach((el) => { el.removeAttribute('data-reveal'); gsap.set(el, { opacity: 0, y: 40 }); });
  ScrollTrigger.batch(tiltReveal, {
    start: 'top 90%', once: true,
    onEnter: (els) => gsap.to(els, { opacity: 1, y: 0, duration: 1.2, ease: 'expo.out', stagger: 0.1 })
  });

  /* ------------------------------------------------------------------------
     Scènes par taille d’écran
     ------------------------------------------------------------------------ */
  const mm = gsap.matchMedia();
  const xpState = { m: 0 };
  const XP_ORDER = [MAT.travertin, MAT.bronze, MAT.lin];
  const XP_KEYS = ['travertin', 'bronze', 'lin'];

  mm.add('(min-width: 901px)', () => {
    html.classList.add('m-desk');
    const cleanups = [];

    /* --- 1. Expertises : l’échantillon géant change de matière --- */
    const stage = qs('.x-xp__stage');
    const visual = qs('.x-xp__visual');
    const sheets = qsa('.x-sheet');
    const layers = qsa('.x-xp__layer');
    const rolls = qsa('.x-xp__hud .x-roll');
    let xpSurface = surfaceOf(visual);
    if (!xpSurface) {
      xpSurface = createSurface(visual, {
        mat: MAT.travertin, before: '.x-xp__hud',
        getMats: () => {
          const m = clamp(xpState.m, 0, 2);
          let i = Math.min(Math.floor(m), 1), f = m - i;
          if (f > 0.999) { i += 1; f = 0; }
          return [XP_ORDER[i], XP_ORDER[Math.min(i + 1, 2)], f];
        }
      });
    } else xpSurface.resize();
    const sheetKids = sheets.map((s) => [...s.children].filter((c) => !c.classList.contains('x-sheet__swatch')));
    rolls.forEach((r) => {
      const ref = r.classList.contains('x-xp__ref');
      gsap.set([...r.children].slice(1), ref ? { opacity: 0, yPercent: 0, y: 0 } : { yPercent: 105, y: 0 });
      gsap.set(r.children[0], { yPercent: 0, y: 0, opacity: 1 });
    });
    gsap.set(sheets, { pointerEvents: 'none' });
    gsap.set(sheets[0], { pointerEvents: 'auto' });

    gsap.fromTo(visual, { rotationX: 16, scale: 0.9, y: 60, transformPerspective: 1600 }, {
      rotationX: 0, scale: 1, y: 0, ease: 'none',
      scrollTrigger: { trigger: stage, start: 'top bottom', end: 'top top', scrub: true }
    });
    const tl = gsap.timeline({
      defaults: { ease: 'lux' },
      scrollTrigger: {
        trigger: stage, start: 'top top', end: () => '+=' + Math.round(window.innerHeight * 2.6),
        pin: true, scrub: 0.8, anticipatePin: 1, invalidateOnRefresh: true,
        onUpdate: () => { visual.dataset.mat = XP_KEYS[Math.round(clamp(xpState.m, 0, 2))]; }
      }
    });
    tl.to({}, { duration: 0.5 });
    for (let i = 1; i <= 2; i++) {
      const at = tl.duration();
      tl.to(xpState, { m: i, duration: 1, ease: 'power1.inOut' }, at);
      tl.to(layers[i], { clipPath: 'inset(0% 0% 0% 0%)', duration: 1 }, at);
      rolls.forEach((r) => {
        const kids = r.children;
        if (r.classList.contains('x-xp__ref')) {
          tl.to(kids[i - 1], { opacity: 0, duration: 0.3 }, at + 0.2);
          tl.fromTo(kids[i], { opacity: 0, yPercent: 0 }, { opacity: 1, duration: 0.35 }, at + 0.5);
          return;
        }
        tl.to(kids[i - 1], { yPercent: -105, duration: 0.55 }, at + 0.18);
        tl.fromTo(kids[i], { yPercent: 105 }, { yPercent: 0, duration: 0.6 }, at + 0.3);
      });
      tl.to(sheetKids[i - 1], { y: -46, opacity: 0, duration: 0.42, stagger: 0.035, ease: 'power2.in' }, at);
      tl.set(sheets[i - 1], { pointerEvents: 'none' }, at + 0.4);
      tl.set(sheets[i], { visibility: 'visible', pointerEvents: 'auto' }, at + 0.4);
      tl.fromTo(sheetKids[i], { y: 64, opacity: 0 }, { y: 0, opacity: 1, duration: 0.6, stagger: 0.045, ease: 'power3.out' }, at + 0.45);
      tl.to({}, { duration: 0.55 });
    }
    // Clavier : un lien de fiche reçoit le focus → on défile jusqu’à sa fiche
    const segs = [0.5 / tl.duration(), (0.5 + 1.55 + 0.45) / tl.duration(), 1];
    sheets.forEach((sh, i) => {
      const onFocus = () => {
        const st = tl.scrollTrigger;
        if (!st) return;
        const y = st.start + (st.end - st.start) * Math.min(1, segs[i] + (i ? 0.02 : 0));
        if (lenis) lenis.scrollTo(y, { immediate: true }); else window.scrollTo(0, y);
      };
      sh.addEventListener('focusin', onFocus);
      cleanups.push(() => sh.removeEventListener('focusin', onFocus));
    });

    /* --- 2. Réalisations : la planche se recompose --- */
    const rzSec = qs('.x-rz');
    const rzStage = qs('.x-rz__stage');
    const tiles = {};
    qsa('.x-rz__tile', rzStage).forEach((t) => { tiles[t.dataset.k] = t; });
    const KEYS = ['intro', 'a', 'b', 'c', 'd'];
    const LAYOUTS = [
      { intro: [0, 0, 5, 6], a: [5, 0, 4, 3], b: [5, 3, 2, 3], c: [7, 3, 2, 3], d: [9, 0, 3, 6] },
      { intro: [7, 0, 5, 2], a: [0, 0, 7, 6], b: [7, 2, 2, 4], c: [9, 2, 3, 2], d: [9, 4, 3, 2] },
      { intro: [0, 0, 3, 2], a: [0, 2, 3, 4], d: [3, 0, 5, 6], b: [8, 0, 4, 3], c: [8, 3, 4, 3] },
      { intro: [8, 0, 4, 2], a: [8, 2, 4, 2], d: [8, 4, 4, 2], b: [0, 0, 4, 6], c: [4, 0, 4, 6] }
    ];
    const FOCUS = [['a'], ['a'], ['d'], ['b', 'c']];
    const st8 = {};
    KEYS.forEach((k) => { const l = LAYOUTS[0][k]; st8[k] = { x: l[0], y: l[1], w: l[2], h: l[3], tone: 0.9, e: 0 }; });
    const dims = { W: 0, H: 0, gap: 10, baseW: 0, baseH: 0 };
    const imgs = {}, caps = {}, rings = {};
    KEYS.forEach((k) => {
      const t = tiles[k];
      rings[k] = qs('.x-rz__ring', t);
      if (k === 'intro') return;
      const img = qs('img', t);
      imgs[k] = { el: img, w: +img.getAttribute('width'), h: +img.getAttribute('height') };
      img.style.width = imgs[k].w + 'px';
      img.style.height = imgs[k].h + 'px';
      img.loading = 'eager';
      caps[k] = qs('.x-rz__cap', t);
    });
    const introIn = qs('.x-rz__introin');
    const hint = qs('.x-rz__hint');
    const hintBar = qsa('.x-rz__hint i');
    const measure = () => {
      dims.W = rzStage.clientWidth; dims.H = rzStage.clientHeight;
      dims.gap = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--gap')) || 10;
      dims.baseW = dims.W * 5 / 12 - dims.gap / 2;
      introIn.style.width = dims.baseW + 'px';
      dims.baseH = introIn.offsetHeight;
      KEYS.forEach((k) => { if (caps[k]) caps[k]._h = caps[k].offsetHeight; });
    };
    const rectOf = (s) => {
      const cw = dims.W / 12, rh = dims.H / 6, g = dims.gap / 2;
      const x0 = s.x * cw + (s.x > 0.01 ? g : 0);
      const x1 = (s.x + s.w) * cw - (s.x + s.w < 11.99 ? g : 0);
      const y0 = s.y * rh + (s.y > 0.01 ? g : 0);
      const y1 = (s.y + s.h) * rh - (s.y + s.h < 5.99 ? g : 0);
      let r = { x: x0, y: y0, w: Math.max(0, x1 - x0), h: Math.max(0, y1 - y0) };
      // apparition : chaque tuile s’ouvre depuis son centre
      const e = s.e;
      if (e < 1) {
        const k = 1 - e;
        const cx = r.x + r.w / 2, cy = r.y + r.h / 2;
        r = { x: cx - (r.w * (1 - k * 0.55)) / 2, y: cy - (r.h * (1 - k * 0.9)) / 2, w: r.w * (1 - k * 0.55), h: r.h * (1 - k * 0.9) };
      }
      return r;
    };
    const apply = () => {
      if (!dims.W) return;
      KEYS.forEach((k) => {
        const s = st8[k], t = tiles[k], r = rectOf(s);
        const R = parseFloat(getComputedStyle(t).getPropertyValue('--r')) || 10;
        t.style.clipPath = `inset(${r.y.toFixed(1)}px ${(dims.W - r.x - r.w).toFixed(1)}px ${(dims.H - r.y - r.h).toFixed(1)}px ${r.x.toFixed(1)}px round ${R}px)`;
        if (k === 'intro') {
          const sc = Math.min(1, r.w / dims.baseW, (r.h - 4) / dims.baseH);
          introIn.style.transform = `translate(${r.x.toFixed(1)}px, ${r.y.toFixed(1)}px) scale(${sc.toFixed(4)})`;
          if (hint) {
            const hh = hint.offsetHeight || 40;
            hint.style.transform = `translate(${(r.x + 34).toFixed(1)}px, ${(r.y + r.h - hh - 30).toFixed(1)}px)`;
            hint.style.opacity = clamp((r.h - dims.baseH - hh - 60) / 120, 0, 1).toFixed(3);
          }
        } else {
          const im = imgs[k];
          const sc = Math.max(r.w / im.w, r.h / im.h) * 1.04;
          const tx = r.x + (r.w - im.w * sc) / 2, ty = r.y + (r.h - im.h * sc) / 2;
          im.el.style.transform = `translate(${tx.toFixed(1)}px, ${ty.toFixed(1)}px) scale(${sc.toFixed(4)})`;
          const ch = caps[k]._h || 50;
          caps[k].style.transform = `translate(${(r.x + 12).toFixed(1)}px, ${(r.y + r.h - ch - 12).toFixed(1)}px)`;
          caps[k].style.opacity = r.w < 150 ? 0 : 1;
          t.style.setProperty('--tone', s.tone.toFixed(3));
        }
        if (t.contains(document.activeElement)) {
          Object.assign(rings[k].style, { width: r.w + 'px', height: r.h + 'px', transform: `translate(${r.x}px, ${r.y}px)` });
        }
      });
    };
    measure();
    const onRefresh = () => { measure(); apply(); };
    ScrollTrigger.addEventListener('refreshInit', measure);
    ScrollTrigger.addEventListener('refresh', onRefresh);
    cleanups.push(() => { ScrollTrigger.removeEventListener('refreshInit', measure); ScrollTrigger.removeEventListener('refresh', onRefresh); });

    const ent = gsap.timeline({
      onUpdate: apply,
      scrollTrigger: { trigger: rzSec, start: 'top 85%', end: 'top top', scrub: 0.6 }
    });
    KEYS.forEach((k, i) => ent.to(st8[k], { e: 1, duration: 1, ease: 'power2.out' }, i * 0.12));

    const rz = gsap.timeline({
      defaults: { ease: 'lux' },
      onUpdate: apply,
      scrollTrigger: {
        trigger: rzSec, start: 'top top', end: () => '+=' + Math.round(window.innerHeight * 2.4),
        pin: true, scrub: 0.8, anticipatePin: 1, invalidateOnRefresh: true
      }
    });
    rz.to({}, { duration: 0.35 });
    if (hintBar.length) rz.fromTo(hintBar, { scaleX: 0 }, { scaleX: 1, duration: 0.6, stagger: 0.02, ease: 'none' }, 0);
    for (let li = 1; li < LAYOUTS.length; li++) {
      const at = rz.duration();
      KEYS.forEach((k, j) => {
        const l = LAYOUTS[li][k];
        rz.to(st8[k], { x: l[0], y: l[1], w: l[2], h: l[3], duration: 1, tone: k !== 'intro' && FOCUS[li].includes(k) ? 0.68 : 0.92 }, at + j * 0.04);
      });
      rz.to({}, { duration: 0.45 });
    }
    qsa('.project-image', rzStage).forEach((b) => {
      const f = () => apply();
      b.addEventListener('focus', f);
      cleanups.push(() => b.removeEventListener('focus', f));
    });
    apply();

    /* --- 3. Méthode : l’éventail s’ouvre --- */
    const fan = qs('.x-fan');
    const cards = qsa('.x-card', fan);
    const open = () => {
      const W = fan.clientWidth, cw = cards[0].offsetWidth;
      const sp = Math.min((W - cw) / 3, cw * 1.1);
      return cards.map((c, i) => ({ x: (i - 1.5) * sp, y: [34, 8, 8, 34][i], r: [-7, -2.4, 2.4, 7][i] }));
    };
    cards.forEach((c, i) => { c.style.zIndex = String(10 - i); });
    gsap.fromTo(cards, {
      '--x': (i) => (i - 1.5) * 8 + 'px', '--y': (i) => 70 + i * 6 + 'px', '--r': (i) => [-3, 2, -1.5, 3.5][i] + 'deg'
    }, {
      '--x': (i) => open()[i].x + 'px', '--y': (i) => open()[i].y + 'px', '--r': (i) => open()[i].r + 'deg',
      ease: 'none', stagger: 0.04,
      scrollTrigger: { trigger: fan, start: 'top 90%', end: 'center 64%', scrub: 0.9, invalidateOnRefresh: true }
    });

    /* --- 4. L’esprit : l’image s’ouvre, la plaque se pose --- */
    const frame = qs('.x-spirit__frame');
    gsap.fromTo(frame, { clipPath: 'inset(16% 14% 16% 14% round 10px)' }, {
      clipPath: 'inset(0% 0% 0% 0% round 10px)', ease: 'none',
      scrollTrigger: { trigger: frame, start: 'top 92%', end: 'top 30%', scrub: 0.6 }
    });
    gsap.fromTo('.x-spirit__frame img', { scale: 1.32, yPercent: -6 }, {
      scale: 1.02, yPercent: 4, ease: 'none',
      scrollTrigger: { trigger: frame, start: 'top bottom', end: 'bottom top', scrub: true }
    });
    gsap.fromTo('.x-plaque', { rotationX: 14, y: 80, transformPerspective: 1800, transformOrigin: '50% 100%' }, {
      rotationX: 0, y: 0, ease: 'none',
      scrollTrigger: { trigger: '.x-plaque', start: 'top bottom', end: 'top 35%', scrub: 0.6 }
    });

    return () => {
      html.classList.remove('m-desk');
      cleanups.forEach((f) => f());
      KEYS.forEach((k) => {
        tiles[k].style.clipPath = '';
        tiles[k].style.removeProperty('--tone');
        if (imgs[k]) { imgs[k].el.style.transform = ''; imgs[k].el.style.width = ''; imgs[k].el.style.height = ''; }
        if (caps[k]) { caps[k].style.transform = ''; caps[k].style.opacity = ''; }
      });
      introIn.style.transform = ''; introIn.style.width = '';
      cards.forEach((c) => { c.style.zIndex = ''; });
    };
  });

  mm.add('(max-width: 900px)', () => {
    // Mobile : pas d’épinglage, mais des échantillons vivants
    qsa('.x-sheet__swatch').forEach((sw) => {
      gsap.fromTo(sw, { clipPath: 'inset(0% 0% 100% 0% round 6px)' }, {
        clipPath: 'inset(0% 0% 0% 0% round 6px)', duration: 1.3, ease: 'lux',
        scrollTrigger: { trigger: sw, start: 'top 85%', once: true }
      });
      gsap.fromTo(qs('b', sw), { yPercent: 40 }, { yPercent: -10, ease: 'none', scrollTrigger: { trigger: sw, start: 'top bottom', end: 'bottom top', scrub: true } });
    });
    qsa('.x-rz__shot, .x-card').forEach((el, i) => {
      gsap.from(el, { opacity: 0, y: 50, rotation: i % 2 ? 2 : -2, duration: 1.2, ease: 'expo.out', scrollTrigger: { trigger: el, start: 'top 90%', once: true } });
    });
    const frame = qs('.x-spirit__frame');
    gsap.fromTo(frame, { clipPath: 'inset(10% 8% 10% 8% round 10px)' }, { clipPath: 'inset(0% 0% 0% 0% round 10px)', ease: 'none', scrollTrigger: { trigger: frame, start: 'top 95%', end: 'top 40%', scrub: 0.5 } });
  });

  function setupThemes() {
    html.classList.add('m-bg');
    const STONE = '#EDE7DD', NOYER = '#1B140E';
    let darkCount = 0;
    const setBg = () => gsap.to(document.body, { backgroundColor: darkCount > 0 ? NOYER : STONE, duration: 0.9, ease: 'power2.inOut', overwrite: true });
    const outer = (el) => (el.parentElement && el.parentElement.classList.contains('pin-spacer') ? el.parentElement : el);
    qsa('.x-spirit, .x-rz').forEach((sec) => {
      ScrollTrigger.create({
        trigger: outer(sec), start: 'top 32%', end: 'bottom 40%',
        onToggle: (self) => { darkCount += self.isActive ? 1 : -1; darkCount = Math.max(0, darkCount); setBg(); }
      });
    });
    let darkHead = 0;
    qsa('[data-theme="dark"]').forEach((sec) => {
      ScrollTrigger.create({
        trigger: outer(sec), start: () => 'top ' + (headerH() / 2), end: () => 'bottom ' + (headerH() / 2),
        onToggle: (self) => { darkHead += self.isActive ? 1 : -1; darkHead = Math.max(0, darkHead); html.classList.toggle('theme-dark', darkHead > 0); }
      });
    });
  }

  setupThemes();

  /* ------------------------------------------------------------------------
     FAQ : ouverture douce des tiroirs
     ------------------------------------------------------------------------ */
  let refreshTimer = 0;
  const softRefresh = () => { clearTimeout(refreshTimer); refreshTimer = setTimeout(() => ScrollTrigger.refresh(), 120); };
  qsa('.x-faq details').forEach((d) => {
    const sum = qs('summary', d), body = qs('.x-faq__a', d);
    sum.addEventListener('click', (e) => {
      e.preventDefault();
      if (d.dataset.busy) return;
      d.dataset.busy = '1';
      if (d.open) {
        gsap.to(body, { height: 0, duration: 0.6, ease: 'lux', onComplete() { d.open = false; gsap.set(body, { clearProps: 'height' }); delete d.dataset.busy; softRefresh(); } });
      } else {
        d.open = true;
        gsap.fromTo(body, { height: 0 }, { height: 'auto', duration: 0.8, ease: 'lux', onComplete() { gsap.set(body, { clearProps: 'height' }); delete d.dataset.busy; softRefresh(); } });
        gsap.from(body.firstElementChild, { y: 18, opacity: 0, duration: 0.9, ease: 'power3.out', delay: 0.1 });
      }
    });
  });

  /* ------------------------------------------------------------------------
     Démarrage : polices prêtes → intro → titres
     ------------------------------------------------------------------------ */
  const fontsReady = document.fonts && document.fonts.ready ? Promise.race([document.fonts.ready, new Promise((r) => setTimeout(r, 350))]) : Promise.resolve();
  fontsReady.then(() => {
    runIntro();
    setupSplits();
    if (introDone) setupTilt();
    ScrollTrigger.sort();
    ScrollTrigger.refresh();
  });
  window.addEventListener('load', () => ScrollTrigger.refresh());
})();
