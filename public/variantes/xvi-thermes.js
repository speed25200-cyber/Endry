'use strict';
/* ==========================================================================
   Endry SA — Maquette XVI · Thermes
   Intro « la goutte », surface d’eau WebGL (reflet, rides, caustiques, vapeur),
   immersion épinglée, trois niches de lumière, bassins en terrasses.
   Dépendances locales : GSAP 3.13 (+ ScrollTrigger, SplitText, CustomEase), Lenis.
   ========================================================================== */
(() => {
  const d = document;
  const root = d.documentElement;
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const ready = window.gsap && window.ScrollTrigger && window.SplitText && window.CustomEase && window.Lenis;

  if (reduce || !ready) {
    root.classList.remove('intro');
    return;
  }

  gsap.registerPlugin(ScrollTrigger, SplitText, CustomEase);
  root.classList.add('motion');
  CustomEase.create('lux', '0.7,0,0.2,1');
  CustomEase.create('rise', '0.16,1,0.3,1');

  const $ = (s, c = d) => c.querySelector(s);
  const $$ = (s, c = d) => [...c.querySelectorAll(s)];
  const fine = matchMedia('(hover: hover) and (pointer: fine)').matches;
  const fontsReady = d.fonts ? d.fonts.ready : Promise.resolve();

  /* ------------------------------------------------------------------------
     Défilement fluide (Lenis) synchronisé avec ScrollTrigger
     ------------------------------------------------------------------------ */
  if ('scrollRestoration' in history) history.scrollRestoration = 'manual';
  const lenis = new Lenis({ lerp: 0.085, wheelMultiplier: 0.9, smoothWheel: true });
  lenis.on('scroll', ScrollTrigger.update);
  gsap.ticker.add(t => lenis.raf(t * 1000));
  gsap.ticker.lagSmoothing(0);

  // Ancres : lenis.scrollTo, focus déplacé pour les lecteurs d’écran
  $$('a[href^="#"]').forEach(a => a.addEventListener('click', e => {
    const id = a.getAttribute('href');
    if (id === '#' || id === '#top') {
      e.preventDefault();
      lenis.scrollTo(0, { duration: 1.8 });
      return;
    }
    const target = $(id);
    if (!target) return;
    e.preventDefault();
    lenis.scrollTo(target, { duration: 1.6, offset: 0 });
    if (!target.hasAttribute('tabindex')) target.setAttribute('tabindex', '-1');
    setTimeout(() => target.focus({ preventScroll: true }), 900);
  }));

  // Menu mobile : Lenis s’arrête quand le menu est ouvert
  const nav = $('#navigation');
  if (nav) new MutationObserver(() => {
    const open = nav.classList.contains('open');
    open ? lenis.stop() : lenis.start();
    hdr.classList.remove('is-hidden');
  }).observe(nav, { attributes: true, attributeFilter: ['class'] });

  // Dialogues : pause du défilement fluide
  $$('dialog').forEach(dlg => {
    new MutationObserver(() => (dlg.open ? lenis.stop() : lenis.start())).observe(dlg, { attributes: true, attributeFilter: ['open'] });
  });

  /* ------------------------------------------------------------------------
     En-tête : masqué en descendant, tonalité sombre selon la section
     ------------------------------------------------------------------------ */
  const hdr = $('.hdr');
  let cursorTone = () => {};
  const darkZones = $$('[data-tone="dark"]');
  let plungeST = null;
  let lastY = 0;
  const updateHeader = () => {
    const y = lenis.scroll;
    const menuOpen = nav && nav.classList.contains('open');
    if (!menuOpen) hdr.classList.toggle('is-hidden', y > lastY + 2 && y > 240);
    if (y < lastY - 2) hdr.classList.remove('is-hidden');
    lastY = y;
    let dark = darkZones.some(z => { const r = z.getBoundingClientRect(); return r.top <= 44 && r.bottom >= 44; });
    if (plungeST && plungeST.progress > 0.66 && plungeEl.getBoundingClientRect().bottom > 44) dark = true;
    hdr.classList.toggle('is-dark', dark);
    cursorTone(dark);
  };
  lenis.on('scroll', updateHeader);

  /* ------------------------------------------------------------------------
     Outils WebGL
     ------------------------------------------------------------------------ */
  const GLSL_COMMON = `
    precision highp float;
    float hash(vec2 p){p=fract(p*vec2(123.34,456.21));p+=dot(p,p+45.32);return fract(p.x*p.y);}
    float noise(vec2 p){vec2 i=floor(p),f=fract(p);vec2 u=f*f*(3.-2.*f);
      return mix(mix(hash(i),hash(i+vec2(1.,0.)),u.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),u.x),u.y);}
    float fbm(vec2 p){float v=0.,a=.5;for(int i=0;i<5;i++){v+=a*noise(p);p=p*2.03+vec2(1.7,9.2);a*=.5;}return v;}
    float caustic(vec2 p0,float t){
      vec2 p=mod(p0*6.28318,6.28318)-250.;
      vec2 i=p;float c=1.;float inten=.005;
      for(int n=0;n<4;n++){
        float tt=t*(1.-(3.5/float(n+1)));
        i=p+vec2(cos(tt-i.x)+sin(tt+i.y),sin(tt-i.y)+cos(tt+i.x));
        c+=1./length(vec2(p.x/(sin(i.x+tt)/inten),p.y/(cos(i.y+tt)/inten)));
      }
      c/=4.;c=1.17-pow(c,1.4);return pow(abs(c),8.);
    }`;
  const VERT = 'attribute vec2 p;void main(){gl_Position=vec4(p,0.,1.);}';

  function makeGL(canvas, frag, alpha) {
    let gl;
    try {
      gl = canvas.getContext('webgl', { alpha: !!alpha, antialias: false, premultipliedAlpha: true, preserveDrawingBuffer: false, powerPreference: 'high-performance' });
    } catch (e) { gl = null; }
    if (!gl) return null;
    const sh = (type, src) => {
      const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) { console.warn(gl.getShaderInfoLog(s)); return null; }
      return s;
    };
    const vs = sh(gl.VERTEX_SHADER, VERT), fs = sh(gl.FRAGMENT_SHADER, frag);
    if (!vs || !fs) return null;
    const pr = gl.createProgram(); gl.attachShader(pr, vs); gl.attachShader(pr, fs); gl.linkProgram(pr);
    if (!gl.getProgramParameter(pr, gl.LINK_STATUS)) return null;
    // Rendu logiciel (SwiftShader, llvmpipe) : on réduit fortement la résolution
    const dbg = gl.getExtension('WEBGL_debug_renderer_info');
    const renderer = dbg ? String(gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL)) : '';
    const scale = /swiftshader|llvmpipe|software/i.test(renderer) ? 0.3 : 1;
    gl.useProgram(pr);
    const buf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(pr, 'p'); gl.enableVertexAttribArray(loc); gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
    const u = {};
    const n = gl.getProgramParameter(pr, gl.ACTIVE_UNIFORMS);
    for (let i = 0; i < n; i++) { const info = gl.getActiveUniform(pr, i); const name = info.name.replace(/\[0\]$/, ''); u[name] = gl.getUniformLocation(pr, name); }
    return { gl, u, scale };
  }

  const visibleWatch = (el, cb) => {
    const io = new IntersectionObserver(es => es.forEach(e => cb(e.isIntersecting)), { rootMargin: '10% 0px' });
    io.observe(el);
  };
  let tabHidden = d.hidden;
  d.addEventListener('visibilitychange', () => { tabHidden = d.hidden; });

  /* ------------------------------------------------------------------------
     WebGL signature n° 1 — le bassin du héros
     Image d’ambiance au-dessus de l’horizon, reflet ondulé au-dessous,
     rides au pointeur, caustiques dorées sur la pierre, vapeur fbm.
     ------------------------------------------------------------------------ */
  const HERO_FRAG = GLSL_COMMON + `
    uniform sampler2D uTex;
    uniform vec2 uRes,uImg,uMouse;
    uniform float uTime,uBox,uHz,uSub,uZoom,uVeil,uCaus,uGlow;
    uniform vec4 uRip[8];
    vec2 cover(vec2 p){
      float ra=uRes.x/(uRes.y*uBox);float ia=uImg.x/uImg.y;
      vec2 s=ra>ia?vec2(1.,ia/ra):vec2(ra/ia,1.);
      return (p-.5)*s/uZoom+.5;
    }
    vec3 grade(vec3 c){float l=dot(c,vec3(.299,.587,.114));vec3 w=l*vec3(1.08,.94,.76);c=mix(c,w,.52);return c*vec3(1.02,.995,.955);}
    vec3 img(vec2 p){return grade(texture2D(uTex,clamp(cover(p),.001,.999)).rgb);}
    void main(){
      vec2 uv=vec2(gl_FragCoord.x/uRes.x,1.-gl_FragCoord.y/uRes.y);
      float asp=uRes.x/uRes.y;float t=uTime;
      vec2 disp=vec2(0.);float ring=0.;
      for(int k=0;k<8;k++){
        vec4 r=uRip[k];float age=t-r.z;
        if(r.w<=0.||age<0.||age>5.)continue;
        vec2 dv=(uv-r.xy)*vec2(asp,1.);dv.y*=2.1;
        float dd=length(dv);float x=dd-age*.2;
        float env=exp(-x*x*220.)*exp(-age*.9)*r.w;
        float w=sin(x*95.)*env;
        disp+=normalize(dv+1e-5)*w*.010;ring+=max(w,0.);
      }
      float hz=uHz+sin(uv.x*21.+t*1.25)*.0015+sin(uv.x*47.-t*1.9)*.0007;
      float inW=smoothstep(hz-.0012,hz+.0012,uv.y);
      float dz=max(uv.y-hz,.0001);
      vec2 q=vec2(uv.x*asp*(1.3+.5/(dz*7.+.35)),1./(dz+.07));
      float n1=noise(q*vec2(2.6,1.15)+vec2(t*.22,-t*.34));
      float n2=noise(q*vec2(6.5,2.4)+vec2(-t*.38,-t*.55));
      vec2 wave=vec2(n1-.5,n2-.5)*(.005+dz*.045)+disp;
      vec2 pr=uv.y>uBox?vec2(uv.x,2.-uv.y/uBox):vec2(uv.x,uv.y/uBox);
      vec3 refl=img(pr+wave*vec2(1.,1.7));
      float fres=mix(.88,.42,smoothstep(0.,.3,dz))*(1.-uSub*.94);
      vec3 deep=mix(vec3(.2,.15,.1),vec3(.129,.102,.075),uSub);
      vec3 wc=mix(deep,refl*vec3(.84,.76,.62),fres);
      float g=pow(max(noise(q*vec2(13.,3.6)+vec2(t*.5,-t*.8))-.56,0.)*2.3,3.);
      wc+=vec3(1.,.87,.62)*g*.42*(1.-uSub);
      wc+=vec3(1.,.9,.72)*ring*.22;
      float cz=caustic(vec2(uv.x*asp,uv.y*1.5)*2.3+wave*9.,t*.33+23.);
      wc+=vec3(.98,.8,.5)*cz*(.07+.32*uSub)*uCaus;
      vec2 pa=vec2(uv.x,uv.y/uBox);
      float sh=(fbm(vec2(uv.x*7.,uv.y*3.-t*.45))-.5)*.0035;
      vec3 ab=img(pa+vec2(sh,sh*.4)+disp*.18);
      float up=max(hz-uv.y,0.);
      float cw=caustic(vec2(uv.x*asp*1.5,uv.y*3.)*1.35+vec2(0.,t*.02),t*.28+7.)*exp(-up*6.5);
      ab+=vec3(1.,.84,.56)*cw*.26*uCaus;
      float ml=exp(-length((uv-uMouse)*vec2(asp,1.))*3.2);
      ab+=vec3(1.,.82,.52)*ml*.10*uGlow;
      ab=mix(ab,ab*vec3(.5,.43,.35),uVeil);
      vec3 col=mix(ab,wc,inW);
      col+=vec3(1.,.9,.7)*exp(-abs(uv.y-hz)*520.)*.32;
      float stm=fbm(vec2(uv.x*asp*2.1-t*.035,uv.y*2.4+t*.13));
      float sm=smoothstep(-.02,.05,hz-uv.y)*exp(-up*3.2);
      col=mix(col,vec3(.98,.93,.84),smoothstep(.48,.9,stm)*sm*.42*(1.-uSub));
      col*=1.-.22*pow(length((uv-vec2(.5,.55))*vec2(.9,1.1)),2.2)*(1.-uSub);
      col+=(hash(uv*uRes+fract(t*7.)*91.)-.5)*.022;
      gl_FragColor=vec4(col,1.);
    }`;

  const heroStage = $('.hero-stage');
  const heroCanvas = $('.hero-gl');
  const heroImg = $('.hero-img');
  const hero = {
    zoom: 1.14, sub: 0, veil: 0, caus: 1, hz: 0.64, box: 0.64, glow: 1,
    rip: new Float32Array(32), ripI: 0, mouse: [0.5, 0.4], on: false, vis: true, gl: null,
  };
  hero.box = parseFloat(getComputedStyle(heroStage).getPropertyValue('--hz')) / 100 || 0.64;
  const t0 = performance.now();
  const now = () => (performance.now() - t0) / 1000;
  const addRipple = (x, y, amp) => {
    const i = (hero.ripI++ % 8) * 4;
    hero.rip[i] = x; hero.rip[i + 1] = y; hero.rip[i + 2] = now(); hero.rip[i + 3] = amp;
  };

  function initHeroGL() {
    const ctx = makeGL(heroCanvas, HERO_FRAG, false);
    if (!ctx) return false;
    const { gl, u, scale } = ctx;
    hero.gl = gl; hero.u = u;
    let drawn = false;
    const tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    const upload = () => {
      try {
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, gl.RGB, gl.UNSIGNED_BYTE, heroImg);
        hero.on = true;
      } catch (e) { hero.on = false; }
    };
    if (heroImg.complete && heroImg.naturalWidth) upload();
    else heroImg.addEventListener('load', upload, { once: true });
    const resize = () => {
      const dpr = Math.min(devicePixelRatio || 1, 1.5) * scale;
      const r = heroStage.getBoundingClientRect();
      heroCanvas.width = Math.max(2, Math.round(r.width * dpr));
      heroCanvas.height = Math.max(2, Math.round(r.height * dpr));
      gl.viewport(0, 0, heroCanvas.width, heroCanvas.height);
      hero.box = parseFloat(getComputedStyle(heroStage).getPropertyValue('--hz')) / 100 || 0.64;
    };
    resize();
    new ResizeObserver(resize).observe(heroStage);
    visibleWatch(heroStage, v => { hero.vis = v; });
    gl.uniform2f(u.uImg, heroImg.naturalWidth || 1672, heroImg.naturalHeight || 941);
    gsap.ticker.add(() => {
      if (!hero.on || !hero.vis || tabHidden) return;
      const hz = hero.box + (-0.1 - hero.box) * hero.sub;
      gl.uniform2f(u.uRes, heroCanvas.width, heroCanvas.height);
      gl.uniform2f(u.uImg, heroImg.naturalWidth || 1672, heroImg.naturalHeight || 941);
      gl.uniform1f(u.uTime, now());
      gl.uniform1f(u.uBox, hero.box);
      gl.uniform1f(u.uHz, hz);
      gl.uniform1f(u.uSub, hero.sub);
      gl.uniform1f(u.uZoom, hero.zoom);
      gl.uniform1f(u.uVeil, hero.veil);
      gl.uniform1f(u.uCaus, hero.caus);
      gl.uniform1f(u.uGlow, hero.glow);
      gl.uniform2f(u.uMouse, hero.mouse[0], hero.mouse[1]);
      gl.uniform4fv(u.uRip, hero.rip);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      if (!drawn) { drawn = true; requestAnimationFrame(() => d.body.classList.add('gl-hero')); }
    });
    // Le pointeur laisse une onde à la surface
    let lx = 0, ly = 0, lt = 0;
    heroStage.addEventListener('pointermove', e => {
      const r = heroStage.getBoundingClientRect();
      const x = (e.clientX - r.left) / r.width, y = (e.clientY - r.top) / r.height;
      gsap.to(hero.mouse, { 0: x, 1: y, duration: 1.2, ease: 'power3.out', overwrite: true });
      const hz = hero.box + (-0.1 - hero.box) * hero.sub;
      const tt = performance.now();
      const dist = Math.hypot((e.clientX - lx) / r.width, (e.clientY - ly) / r.height);
      if (y > hz + 0.01 && dist > 0.03 && tt - lt > 70) {
        addRipple(x, y, e.pointerType === 'touch' ? 0.9 : 0.55);
        lx = e.clientX; ly = e.clientY; lt = tt;
      }
    }, { passive: true });
    heroStage.addEventListener('pointerdown', e => {
      const r = heroStage.getBoundingClientRect();
      const x = (e.clientX - r.left) / r.width, y = (e.clientY - r.top) / r.height;
      const hz = hero.box + (-0.1 - hero.box) * hero.sub;
      addRipple(x, Math.max(y, hz + 0.03), 1.2);
    }, { passive: true });
    return true;
  }
  const heroGL = initHeroGL();

  /* ------------------------------------------------------------------------
     WebGL signature n° 2 — trois niches : la lumière sur la pierre
     eau (caustiques) · chaleur (lueur, air qui tremble) · air (rais, brume)
     ------------------------------------------------------------------------ */
  const NICHE_FRAG = GLSL_COMMON + `
    uniform vec2 uRes,uM;uniform float uTime;uniform vec4 uR[3];uniform vec3 uVis,uRev;
    vec3 shade(float mode,vec2 q,float asp,float t,float vis){
      vec2 sp=q*vec2(asp,1.);
      float s=fbm(sp*5.+3.);
      float vein=smoothstep(.6,.64,fbm(sp*vec2(1.6,6.)+11.))*.05;
      float ao=mix(.42,1.,smoothstep(0.,.8,q.y));ao*=1.-.4*pow(abs(q.x-.5)*2.,3.);
      vec3 gold=vec3(1.,.83,.55);vec3 col;
      if(mode<.5){
        col=(mix(vec3(.15,.115,.08),vec3(.26,.2,.14),s)+vein)*ao;
        float wl=.8+sin(q.x*10.+t*1.1)*.004+sin(q.x*23.-t*1.6)*.002;
        float c=caustic(sp*2.4+vec2(uM.x*.25,t*.015),t*.42);
        if(q.y<wl){
          float fall=exp(-(wl-q.y)*3.);
          col+=gold*(c*.8*fall+.12*fall);
        }else{
          float dq=q.y-wl;
          col=mix(vec3(.2,.15,.1),vec3(.34,.26,.16),.5+.5*sin(q.x*38.+t*.8+dq*60.))*.75;
          col+=gold*(c*.35+.1);
          col+=gold*exp(-dq*70.)*.55;
        }
      }else if(mode<1.5){
        float h=fbm(vec2(q.x*5.,q.y*2.4+t*.42));
        vec2 wq=q+vec2((h-.5)*.04*(1.-q.y*.3),0.);
        float s2=fbm(wq*vec2(asp,1.)*5.+3.);
        col=(mix(vec3(.16,.1,.06),vec3(.27,.17,.1),s2)+vein)*ao;
        vec2 gc=vec2(.5+uM.x*.14,1.08);
        float gl=exp(-length((q-gc)*vec2(1.25,1.))*2.3);
        col+=vec3(1.,.6,.28)*gl*.95;
        float bands=smoothstep(.5,.85,fbm(vec2(q.x*3.2,q.y*2.1+t*.3)+h));
        col+=vec3(1.,.72,.4)*bands*.12*(.35+q.y);
      }else{
        col=(mix(vec3(.19,.16,.13),vec3(.3,.26,.21),s)+vein)*ao;
        float ang=(q.x-.12-uM.x*.1)+q.y*.55;
        float rays=pow(.5+.5*sin(ang*24.+fbm(vec2(ang*5.,t*.12))*4.),5.)*smoothstep(1.,.05,q.y);
        col+=vec3(1.,.93,.8)*rays*.17;
        float mist=fbm(vec2(q.x*2.3-t*.055,q.y*3.1+sin(t*.2)*.3));
        float mist2=fbm(vec2(q.x*4.+t*.08,q.y*5.));
        col=mix(col,vec3(.74,.66,.55),smoothstep(.2,.8,mist*mist2*1.6)*.5);
      }
      return col*(.5+.5*vis);
    }
    void main(){
      vec2 f=vec2(gl_FragCoord.x,uRes.y-gl_FragCoord.y);
      vec4 o=vec4(0.);
      for(int k=0;k<3;k++){
        vec4 r=uR[k];
        if(r.z<2.)continue;
        vec2 lp=f-r.xy;
        if(lp.x<-1.||lp.y<-1.||lp.x>r.z+1.||lp.y>r.w+1.)continue;
        float rad=r.z*.5;
        float sd=lp.y<rad?rad-length(lp-vec2(rad,rad)):min(lp.x,r.z-lp.x);
        sd=min(sd,r.w-lp.y);
        float a=clamp(sd+.5,0.,1.);
        if(a<=0.)continue;
        vec2 q=lp/r.zw;
        a*=clamp((q.y-(1.-uRev[k]))*r.w+.5,0.,1.);
        if(a<=0.)continue;
        vec3 c=shade(float(k),q,r.z/r.w,uTime,uVis[k]);
        c+=(hash(f+fract(uTime*5.)*37.)-.5)*.03;
        o=vec4(c*a,a);
      }
      gl_FragColor=o;
    }`;

  const xp = $('.xp');
  const xpCanvas = $('.xp-gl');
  const niches = $$('.niche');
  const nicheRev = new Float32Array(3);
  function initNicheGL() {
    const ctx = makeGL(xpCanvas, NICHE_FRAG, true);
    if (!ctx) return;
    const { gl, u, scale } = ctx;
    xp.classList.add('gl-xp');
    let vis = false, mx = 0;
    const rects = new Float32Array(12), v = new Float32Array(3);
    const resize = () => {
      const dpr = Math.min(devicePixelRatio || 1, 1.5) * scale;
      const r = xpCanvas.getBoundingClientRect();
      xpCanvas.width = Math.max(2, Math.round(r.width * dpr));
      xpCanvas.height = Math.max(2, Math.round(r.height * dpr));
      gl.viewport(0, 0, xpCanvas.width, xpCanvas.height);
    };
    resize();
    new ResizeObserver(resize).observe(xpCanvas);
    visibleWatch(xp, s => { vis = s; });
    xp.addEventListener('pointermove', e => { mx = e.clientX / innerWidth - 0.5; }, { passive: true });
    // Mobile : pas de pin, le défilement tactile est composité hors du fil principal.
    // Le canvas est alors déplacé DANS la niche la plus proche du centre de l’écran,
    // pour défiler avec elle sans décalage (au lieu d’un canvas collant partagé).
    const small = matchMedia('(max-width: 899px)');
    const home = xpCanvas.parentNode, homeNext = xpCanvas.nextSibling;
    let host = null;
    const setHost = n => {
      if (host === n) return;
      if (host) host.classList.remove('has-gl');
      host = n;
      if (n) { n.prepend(xpCanvas); n.classList.add('has-gl'); }
      else home.insertBefore(xpCanvas, homeNext);
    };
    let um = 0;
    gsap.ticker.add(() => {
      if (!vis || tabHidden) return;
      if (small.matches) {
        let best = null, bd = Infinity;
        niches.forEach(n => { const r = n.getBoundingClientRect(); const dd = Math.abs(r.top + r.height / 2 - innerHeight / 2); if (dd < bd) { bd = dd; best = n; } });
        setHost(best);
      } else if (host) setHost(null);
      const cr = xpCanvas.getBoundingClientRect();
      const dpr = xpCanvas.width / Math.max(1, cr.width);
      niches.forEach((n, i) => {
        const r = n.getBoundingClientRect();
        const on = r.right > cr.left - 20 && r.left < cr.right + 20 && r.bottom > cr.top - 20 && r.top < cr.bottom + 20;
        rects[i * 4] = (r.left - cr.left) * dpr; rects[i * 4 + 1] = (r.top - cr.top) * dpr;
        rects[i * 4 + 2] = on ? r.width * dpr : 0; rects[i * 4 + 3] = r.height * dpr;
        const c = (r.left + r.width / 2) / innerWidth - 0.5;
        const cy = (r.top + r.height / 2) / innerHeight - 0.5;
        v[i] = Math.max(0, 1 - Math.hypot(c * 1.4, cy * 1.1));
      });
      um += (mx - um) * 0.05;
      gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT);
      gl.uniform2f(u.uRes, xpCanvas.width, xpCanvas.height);
      gl.uniform1f(u.uTime, now());
      gl.uniform2f(u.uM, um, 0);
      gl.uniform4fv(u.uR, rects);
      gl.uniform3fv(u.uVis, v);
      gl.uniform3fv(u.uRev, nicheRev);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    });
  }
  initNicheGL();

  /* ------------------------------------------------------------------------
     Géométrie de l’arche du héros
     ------------------------------------------------------------------------ */
  const archBox = $('.hero-archbox');
  const archSvg = $('.hero-arch');
  const win = $('.hero-window');
  const fill = $('.hero-fill');
  const arch = () => {
    const s = heroStage.getBoundingClientRect(), b = archBox.getBoundingClientRect();
    return { t: b.top - s.top, l: b.left - s.left, r: s.right - b.right, w: b.width, h: b.height, R: b.width / 2, H: s.height };
  };
  const archClip = () => { const a = arch(); return `inset(${a.t}px ${a.r}px 0px ${a.l}px round ${a.R}px ${a.R}px 0px 0px)`; };
  const drawArchPaths = () => {
    const a = arch();
    archSvg.style.left = a.l + 'px'; archSvg.style.top = a.t + 'px';
    const o = innerWidth < 900 ? 10 : 16;
    const set = (sel, path) => $$(sel, archSvg).forEach(p => { p.setAttribute('d', path); p.setAttribute('pathLength', '1'); });
    const R = a.R, h = a.h;
    set('.arch-in.arch-l', `M0 ${h} L0 ${R} A${R} ${R} 0 0 1 ${R} 0`);
    set('.arch-in.arch-r', `M${a.w} ${h} L${a.w} ${R} A${R} ${R} 0 0 0 ${R} 0`);
    const Ro = R + o;
    set('.arch-out.arch-l', `M${-o} ${h} L${-o} ${R} A${Ro} ${Ro} 0 0 1 ${R} ${-o}`);
    set('.arch-out.arch-r', `M${a.w + o} ${h} L${a.w + o} ${R} A${Ro} ${Ro} 0 0 0 ${R} ${-o}`);
  };
  drawArchPaths();
  addEventListener('resize', drawArchPaths);
  $$('path', archSvg).forEach(p => { p.style.strokeDasharray = '1'; p.style.strokeDashoffset = '0'; });

  /* ------------------------------------------------------------------------
     Intro : une goutte tombe, l’onde se propage, l’arche se dessine,
     la vapeur monte, le titre émerge de l’eau (≤ 2,5 s)
     ------------------------------------------------------------------------ */
  const titles = $$('.ht');
  const metaKids = $$('.hero-meta > *');
  const drop = $('.hero-drop');
  const rings = $$('.hero-rings i');
  let heroSplits = [];
  const h1 = $('.ht-main');
  h1.setAttribute('aria-label', h1.textContent.replace(/\s+/g, ' ').trim());
  const splitHero = () => {
    heroSplits = $$('.ht-l1, .ht-l2').map(el => SplitText.create(el, { type: 'lines,chars', mask: 'lines', aria: 'hidden' }));
    return heroSplits.flatMap(s => s.chars);
  };

  function playIntro() {
    const skip = !root.classList.contains('intro');
    const hzPct = hero.box;
    gsap.set(titles, { opacity: 1 });
    gsap.set(win, { opacity: 1 });
    root.classList.remove('intro');
    if (skip) {
      fontsReady.then(() => { splitHero(); });
      return;
    }
    lenis.stop();
    const tl = gsap.timeline({ defaults: { ease: 'rise' }, onComplete: () => lenis.start() });
    const impact = `50% ${((hzPct + 0.09) * 100).toFixed(2)}%`;
    gsap.set(fill, { clipPath: `ellipse(0% 0% at ${impact})` });
    gsap.set($$('path', archSvg), { strokeDashoffset: 1 });
    gsap.set(metaKids, { opacity: 0, y: 26 });
    gsap.set('.hero-cap', { opacity: 0 });
    gsap.set(hdr, { opacity: 0, y: -20 });
    gsap.set(titles, { filter: 'blur(14px)' });
    const dropY = heroStage.getBoundingClientRect().height * (hzPct + 0.09);
    tl.fromTo(drop, { y: -dropY, opacity: 0, scaleY: 0.8 }, { y: 0, opacity: 1, scaleY: 1.25, duration: 0.55, ease: 'power2.in' }, 0.05)
      .to(drop, { opacity: 0, scaleX: 2.4, scaleY: 0.1, duration: 0.14, ease: 'power2.out' }, 0.6)
      .call(() => {
        addRipple(0.5, hzPct + 0.09, 1.7);
        setTimeout(() => addRipple(0.5, hzPct + 0.09, 0.9), 260);
        setTimeout(() => addRipple(0.5, hzPct + 0.09, 0.5), 560);
      }, null, 0.6)
      .fromTo(rings, { scale: 0.05, opacity: 0.95 }, { scale: 1.4, opacity: 0, duration: 1.8, stagger: 0.22, ease: 'power2.out', immediateRender: false }, 0.6)
      .to($$('path', archSvg), { strokeDashoffset: 0, duration: 1.2, ease: 'lux', stagger: 0.05 }, 0.62)
      // Le bassin s’étale depuis l’impact, puis l’image monte et remplit l’arche
      .to(fill, { clipPath: `ellipse(26% 6% at ${impact})`, duration: 0.6, ease: 'power3.out' }, 0.6)
      .to(fill, { clipPath: `ellipse(130% 150% at ${impact})`, duration: 1.2, ease: 'lux', clearProps: 'clipPath' }, 1.02)
      .fromTo(hero, { zoom: 1.24 }, { zoom: 1.14, duration: 1.9, ease: 'rise' }, 0.8)
      .to(titles, { filter: 'blur(0px)', duration: 1.2, ease: 'power2.out', clearProps: 'filter' }, 1.12)
      .to(hdr, { opacity: 1, y: 0, duration: 0.9, clearProps: 'opacity,transform' }, 1.45)
      .to(metaKids, { opacity: 1, y: 0, duration: 1, stagger: 0.06, clearProps: 'transform' }, 1.5)
      .to('.hero-cap', { opacity: 1, duration: 0.8 }, 1.7);
    // Le titre : caractères qui remontent de l’eau
    gsap.set(titles, { opacity: 0 });
    Promise.race([fontsReady, new Promise(r => setTimeout(r, 900))]).then(() => {
      splitHero();
      gsap.set(titles, { opacity: 1 });
      const base = Math.max(0, 1.05 - tl.time());
      heroSplits.forEach(sp => {
        const isL2 = sp.elements[0].classList.contains('ht-l2');
        gsap.fromTo(sp.chars, { yPercent: 115, opacity: 0 }, {
          yPercent: 0, opacity: 1, duration: 1.15, ease: 'rise',
          stagger: 0.03, delay: base + (isL2 ? 0.22 : 0),
        });
      });
    });
  }

  /* ------------------------------------------------------------------------
     Scroll : pins et scrubs (bureau / mobile)
     ------------------------------------------------------------------------ */
  const mm = gsap.matchMedia();
  const plungeEl = $('.plunge');
  const pwKicker = $('.pw-kicker');
  const pwLine = $('.pw-line');

  mm.add('(min-width: 900px)', () => {
    /* Pin 1 — on entre dans les bains : l’arche s’ouvre, l’eau monte */
    let pwSplit = null;
    const tl = gsap.timeline({
      defaults: { ease: 'none' },
      scrollTrigger: {
        trigger: plungeEl, start: 'top top', end: '+=280%', pin: true, scrub: 1.1,
        invalidateOnRefresh: true, anticipatePin: 1,
        onUpdate: updateHeader,
      },
    });
    plungeST = tl.scrollTrigger;
    tl.fromTo(win, { clipPath: () => archClip() }, { clipPath: 'inset(0px 0px 0px 0px round 0px 0px 0px 0px)', duration: 4, ease: 'power2.inOut' }, 0)
      .fromTo(hero, { zoom: 1.14 }, { zoom: 1, duration: 4, ease: 'power2.inOut', immediateRender: false }, 0)
      .fromTo(archSvg, { opacity: 1, scale: 1 }, { opacity: 0, scale: 1.08, transformOrigin: '50% 100%', duration: 1.4 }, 0)
      .fromTo('.ht-l1', { yPercent: 0, xPercent: 0, opacity: 1 }, { yPercent: -120, xPercent: -6, opacity: 0, duration: 2.6, ease: 'power1.in' }, 0.2)
      .fromTo('.ht-l2', { yPercent: 0, xPercent: 0, opacity: 1 }, { yPercent: 110, xPercent: 5, opacity: 0, duration: 2.6, ease: 'power1.in' }, 0.2)
      .fromTo('.hero-meta--a', { y: 0, opacity: 1 }, { y: -80, opacity: 0, duration: 1.6, ease: 'power1.in' }, 0)
      .fromTo('.hero-meta--b', { y: 0, opacity: 1 }, { y: -120, opacity: 0, duration: 1.6, ease: 'power1.in' }, 0)
      .fromTo('.hero-cap', { opacity: 1 }, { opacity: 0, duration: 0.8, immediateRender: false }, 0.4)
      .fromTo(hero, { veil: 0 }, { veil: 0.55, duration: 1.6, ease: 'power1.inOut', immediateRender: false }, 3.1)
      .set('.plunge-words', { visibility: 'visible' }, 3.2)
      .fromTo(pwKicker, { opacity: 0, y: 30 }, { opacity: 1, y: 0, duration: 1.1, ease: 'power2.out' }, 3.4)
      .fromTo(pwLine, { opacity: 0, yPercent: 16 }, { opacity: 1, yPercent: 0, duration: 1.6, ease: 'power2.out' }, 3.6)
      .fromTo(hero, { sub: 0 }, { sub: 1, duration: 3.4, ease: 'power1.inOut', immediateRender: false }, 5.6)
      .to([pwKicker, pwLine], { opacity: 0, yPercent: -30, duration: 1.3, ease: 'power1.in', stagger: 0.1 }, 6.8)
      .fromTo(hero, { caus: 1, glow: 1 }, { caus: 0.7, glow: 0, duration: 1, ease: 'power1.in', immediateRender: false }, 8.6)
      .fromTo('.hero-deep', { opacity: 0 }, { opacity: 1, duration: 1.4, ease: 'power1.inOut' }, 8.2)
      .to({}, { duration: 0.6 });
    fontsReady.then(() => {
      pwSplit = SplitText.create(pwLine, { type: 'lines', mask: 'lines' });
      tl.fromTo(pwSplit.lines, { yPercent: 110 }, { yPercent: 0, duration: 1.5, stagger: 0.18, ease: 'power3.out' }, 3.6);
    });

    /* Pin 2 — les trois bassins, section horizontale */
    const track = $('.xp-track');
    const dist = () => track.scrollWidth - innerWidth;
    const legend = $$('.xp-legend span');
    const bar = $('.xp-legend b i');
    const tones = ['#211a13', '#231911', '#261a10', '#241d16', '#221c16'];
    const toneAt = gsap.utils.interpolate(tones);
    const move = gsap.to(track, {
      x: () => -dist(), ease: 'none',
      scrollTrigger: {
        trigger: xp, start: 'top top', end: () => '+=' + Math.round(dist() * 1.15), pin: true, scrub: 1,
        invalidateOnRefresh: true, anticipatePin: 1,
        onUpdate: self => {
          const p = self.progress;
          xp.style.backgroundColor = toneAt(p);
          gsap.set(bar, { scaleX: p });
          const idx = p < 0.42 ? 0 : p < 0.8 ? 1 : 2;
          legend.forEach((s, i) => s.classList.toggle('is-on', i === idx));
        },
      },
    });
    $$('.xp-panel').forEach(panel => {
      const copy = $('.xp-copy', panel);
      const niche = $('.niche', panel);
      gsap.fromTo(copy.children, { x: 120, opacity: 0 }, {
        x: 0, opacity: 1, stagger: 0.04, ease: 'power2.out',
        scrollTrigger: { trigger: panel, containerAnimation: move, start: 'left 88%', end: 'left 30%', scrub: 1 },
      });
      const ni = niches.indexOf(niche);
      gsap.fromTo(niche, { clipPath: 'inset(100% -12% 0% -12%)' }, {
        clipPath: 'inset(-6% -12% 0% -12%)', ease: 'power2.inOut',
        onUpdate() { nicheRev[ni] = this.ratio; },
        scrollTrigger: { trigger: panel, containerAnimation: move, start: 'left 95%', end: 'left 35%', scrub: 1 },
      });
      gsap.fromTo($('.niche-word', panel), { yPercent: 60 }, {
        yPercent: -10, ease: 'none',
        scrollTrigger: { trigger: panel, containerAnimation: move, start: 'left right', end: 'right left', scrub: true },
      });
    });
    gsap.fromTo('.xp-hint span', { scaleX: 0, transformOrigin: 'left' }, { scaleX: 1, duration: 1.4, ease: 'lux', repeat: -1, repeatDelay: 0.6 });

    /* Pin 3 — la méthode : les bassins se remplissent l’un après l’autre */
    const terr = $$('.terrace');
    const mtl = gsap.timeline({
      defaults: { ease: 'none' },
      scrollTrigger: { trigger: '.meth', start: 'top top', end: '+=230%', pin: true, scrub: 1, invalidateOnRefresh: true, anticipatePin: 1 },
    });
    terr.forEach((t, i) => {
      const at = i * 1.15;
      mtl.fromTo($('.water', t), { yPercent: 100 }, { yPercent: 0, duration: 1, ease: 'power1.inOut' }, at)
        .fromTo($$('h3, p', t), { opacity: 0.4 }, { opacity: 1, duration: 0.5 }, at + 0.25)
        .fromTo($('.vessel-num', t), { yPercent: 30, opacity: 0.35 }, { yPercent: 0, opacity: 1, duration: 0.6 }, at + 0.2);
      const sp = $('.spill', t);
      if (sp) mtl.fromTo(sp, { scaleY: 0, scaleX: 0 }, { scaleY: 1, scaleX: 1, duration: 0.3 }, at + 0.85);
    });
    mtl.to({}, { duration: 0.4 });

    return () => { if (pwSplit) pwSplit.revert(); plungeST = null; xp.style.backgroundColor = ''; };
  });

  mm.add('(max-width: 899px)', () => {
    // Mobile : pas d’épinglage. L’arche s’ouvre un peu, les bassins se remplissent au fil du défilement.
    gsap.to(hero, { zoom: 1, ease: 'none', scrollTrigger: { trigger: heroStage, start: 'top top', end: 'bottom top', scrub: true } });
    gsap.to('.ht-main .ht-l1, .ht-ghost .ht-l1', { yPercent: -60, ease: 'none', scrollTrigger: { trigger: heroStage, start: 'top top', end: 'bottom top', scrub: true } });
    gsap.fromTo(win, { clipPath: () => archClip() }, {
      clipPath: () => { const a = arch(); return `inset(${a.t * 0.55}px ${a.r * 0.3}px 0px ${a.l * 0.3}px round ${a.R * 1.2}px ${a.R * 1.2}px 0px 0px)`; },
      ease: 'none', immediateRender: false,
      scrollTrigger: { trigger: heroStage, start: 'top top', end: 'bottom top', scrub: true, invalidateOnRefresh: true },
    });
    $$('.terrace').forEach(t => {
      gsap.fromTo($('.water', t), { yPercent: 100 }, { yPercent: 0, ease: 'power1.out', scrollTrigger: { trigger: t, start: 'top 85%', end: 'top 35%', scrub: 1 } });
    });
    niches.forEach((n, i) => {
      gsap.fromTo(n, { clipPath: 'inset(100% -12% 0% -12%)' }, { clipPath: 'inset(-6% -12% 0% -12%)', duration: 1.6, ease: 'lux', onUpdate() { nicheRev[i] = this.ratio; }, scrollTrigger: { trigger: n, start: 'top 82%' } });
    });
  });

  /* ------------------------------------------------------------------------
     Révélations communes
     ------------------------------------------------------------------------ */
  function reveals() {
    // Titres : lignes masquées qui montent
    $$('[data-split]').forEach(el => {
      SplitText.create(el, {
        type: 'lines', mask: 'lines', autoSplit: true,
        onSplit: self => gsap.from(self.lines, {
          yPercent: 112, duration: 1.4, ease: 'lux', stagger: 0.1,
          scrollTrigger: { trigger: el, start: 'top 84%', once: true },
        }),
      });
    });
    $$('[data-rise]').forEach(el => {
      gsap.from(el, { y: 36, opacity: 0, duration: 1.3, ease: 'rise', scrollTrigger: { trigger: el, start: 'top 90%', once: true } });
    });
    $$('.eyebrow').forEach(el => {
      if (el.closest('.hero') || el.closest('dialog')) return;
      gsap.from(el, { opacity: 0, x: -20, duration: 1.1, ease: 'rise', scrollTrigger: { trigger: el, start: 'top 90%', once: true } });
    });
    // Images : masque en arche qui monte
    $$('[data-arch-reveal]').forEach((el, i) => {
      const inCol = el.closest('.colonnade');
      const delay = inCol ? ([...inCol.children].indexOf(el.closest('.col')) * 0.12) : 0;
      gsap.fromTo(el, { clipPath: 'inset(100% 0% 0% 0%)' }, {
        clipPath: 'inset(0% 0% 0% 0%)', duration: 1.7, ease: 'lux', delay, clearProps: 'clipPath',
        scrollTrigger: { trigger: inCol || el, start: 'top 82%', once: true },
      });
    });
    $$('[data-parallax]').forEach(img => {
      gsap.fromTo(img, { yPercent: -6, scale: 1.08 }, {
        yPercent: 6, scale: 1, ease: 'none',
        scrollTrigger: { trigger: img.parentElement, start: 'top bottom', end: 'bottom top', scrub: true },
      });
    });
    // Dépannage : l’arche claire s’ouvre en montant
    gsap.fromTo('.rep-arch', { clipPath: 'inset(16vh 20vw 0vh 20vw round 30vw 30vw 0vw 0vw)' }, {
      clipPath: 'inset(0vh 0vw 0vh 0vw round 0vw 0vw 0vw 0vw)', ease: 'none',
      scrollTrigger: { trigger: '.rep', start: 'top bottom', end: 'top 15%', scrub: 1 },
    });
    // L’esprit : les deux phrases glissent en sens contraire (bureau)
    mm.add('(min-width: 900px)', () => {
      gsap.fromTo('.sp-a', { xPercent: 0 }, { xPercent: 6, ease: 'none', scrollTrigger: { trigger: '.spirit-head', start: 'top bottom', end: 'bottom top', scrub: true } });
      gsap.fromTo('.sp-b', { xPercent: 0 }, { xPercent: -7, ease: 'none', scrollTrigger: { trigger: '.spirit-head', start: 'top bottom', end: 'bottom top', scrub: true } });
    });
    // Colonnade : légère respiration verticale décalée
    $$('.col').forEach((c, i) => {
      gsap.fromTo(c, { y: 40 + (i % 2) * 50 }, { y: -(i % 2) * 30, ease: 'none', scrollTrigger: { trigger: '.colonnade', start: 'top bottom', end: 'bottom top', scrub: true } });
    });
    // FAQ, contact, pied de page
    $$('.faq-list details').forEach((el, i) => gsap.from(el, { opacity: 0, y: 30, duration: 1.1, ease: 'rise', delay: i * 0.06, scrollTrigger: { trigger: '.faq-list', start: 'top 85%', once: true } }));
    gsap.fromTo('.basin-form', { clipPath: 'inset(100% 0% 0% 0%)' }, { clipPath: 'inset(0% 0% 0% 0%)', duration: 1.8, ease: 'lux', scrollTrigger: { trigger: '.basin-form', start: 'top 85%', once: true }, clearProps: 'clipPath' });
    $$('.phone').forEach((el, i) => gsap.from(el, { opacity: 0, y: 24, duration: 1.1, ease: 'rise', delay: i * 0.08, scrollTrigger: { trigger: '.contact-phones', start: 'top 88%', once: true } }));
    gsap.from('.foot-claim', { yPercent: 30, opacity: 0, duration: 1.6, ease: 'rise', scrollTrigger: { trigger: '.foot', start: 'top 75%', once: true } });
    gsap.fromTo('.foot-glow', { scale: 0.6, opacity: 0 }, { scale: 1, opacity: 1, ease: 'none', scrollTrigger: { trigger: '.foot', start: 'top bottom', end: 'bottom bottom', scrub: true } });
  }

  /* ------------------------------------------------------------------------
     Curseur « goutte » et boutons magnétiques (pointeur fin uniquement)
     ------------------------------------------------------------------------ */
  const cursor = $('.cursor');
  if (fine && cursor) {
    root.classList.add('has-cursor');
    const xTo = gsap.quickTo(cursor, 'x', { duration: 0.28, ease: 'power3' });
    const yTo = gsap.quickTo(cursor, 'y', { duration: 0.28, ease: 'power3' });
    gsap.set(cursor, { x: -100, y: -100 });
    addEventListener('pointermove', e => { xTo(e.clientX); yTo(e.clientY); }, { passive: true });
    d.addEventListener('pointerover', e => {
      const hit = e.target.closest('a, button, summary, label, [data-magnetic], input, select, textarea');
      cursor.classList.toggle('is-link', !!hit && !e.target.closest('input, select, textarea'));
      cursor.classList.toggle('is-hidden', !!e.target.closest('input, select, textarea'));
    });
    d.addEventListener('pointerleave', () => cursor.classList.add('is-hidden'));
    d.addEventListener('pointerenter', () => cursor.classList.remove('is-hidden'));
    addEventListener('pointerdown', e => {
      const r = d.createElement('span');
      r.className = 'drop-ripple';
      if (cursor.classList.contains('is-dark')) r.style.borderColor = '#f9dba3';
      d.body.append(r);
      gsap.fromTo(r, { x: e.clientX, y: e.clientY, scale: 0.1, opacity: 0.9 }, { scale: 1.6, opacity: 0, duration: 1.1, ease: 'power2.out', onComplete: () => r.remove() });
    }, { passive: true });
    cursorTone = dark => cursor.classList.toggle('is-dark', dark);
    const darkCheck = () => {
      const el = d.elementFromPoint(gsap.getProperty(cursor, 'x'), gsap.getProperty(cursor, 'y'));
      if (el) cursor.classList.toggle('is-dark', !!el.closest('.xp, .foot, .mobile-contact, #image-dialog') || (!!plungeST && plungeST.isActive && plungeST.progress > 0.62 && !!el.closest('.plunge')));
    };
    setInterval(darkCheck, 250);

    $$('[data-magnetic]').forEach(el => {
      const inner = el.firstElementChild;
      const xs = gsap.quickTo(el, 'x', { duration: 0.6, ease: 'power3' });
      const ys = gsap.quickTo(el, 'y', { duration: 0.6, ease: 'power3' });
      el.addEventListener('pointermove', e => {
        const r = el.getBoundingClientRect();
        const dx = e.clientX - (r.left + r.width / 2), dy = e.clientY - (r.top + r.height / 2);
        xs(dx * 0.26); ys(dy * 0.36);
        if (inner) gsap.to(inner, { x: dx * 0.1, y: dy * 0.12, duration: 0.6, ease: 'power3' });
      });
      el.addEventListener('pointerleave', () => {
        gsap.to(el, { x: 0, y: 0, duration: 1.1, ease: 'elastic.out(1, .4)' });
        if (inner) gsap.to(inner, { x: 0, y: 0, duration: 1.1, ease: 'elastic.out(1, .4)' });
      });
    });
  }

  /* ------------------------------------------------------------------------
     Démarrage
     ------------------------------------------------------------------------ */
  playIntro();
  fontsReady.then(() => {
    reveals();
    ScrollTrigger.refresh();
    drawArchPaths();
  });
  addEventListener('load', () => ScrollTrigger.refresh());
  updateHeader();
})();
