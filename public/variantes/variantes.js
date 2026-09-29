'use strict';
// Commun aux maquettes : apparition au défilement, état de l'en-tête et navigation de revue entre variantes.
(()=>{
const reduce=matchMedia('(prefers-reduced-motion: reduce)').matches;
const items=document.querySelectorAll('[data-reveal]');
if(reduce||!('IntersectionObserver' in window)){items.forEach(el=>el.classList.add('is-in'));}
else{const io=new IntersectionObserver(entries=>entries.forEach(e=>{if(e.isIntersecting){e.target.classList.add('is-in');io.unobserve(e.target);}}),{rootMargin:'0px 0px -8% 0px',threshold:.12});items.forEach(el=>io.observe(el));}
const onScroll=()=>document.body.classList.toggle('is-scrolled',scrollY>40);
addEventListener('scroll',onScroll,{passive:true});onScroll();
const variants=[['xiii-manufacture.html','XIII','Manufacture'],['xiv-palace.html','XIV','Palace'],['xv-matiere.html','XV','Matière'],['xvi-thermes.html','XVI','Thermes']];
const file=location.pathname.split('/').pop();const i=variants.findIndex(v=>v[0]===file);
if(i<0)return;
const prev=variants[(i+variants.length-1)%variants.length],next=variants[(i+1)%variants.length];
const bar=document.createElement('nav');bar.className='review-switch';bar.setAttribute('aria-label','Maquettes à comparer');
bar.innerHTML=`<a href="${prev[0]}" aria-label="Maquette précédente : ${prev[2]}">‹</a><a href="./" class="review-current">Maquette ${variants[i][1]} · ${variants[i][2]}</a><a href="${next[0]}" aria-label="Maquette suivante : ${next[2]}">›</a>`;
document.body.append(bar);
})();
