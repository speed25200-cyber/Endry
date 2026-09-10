/* Devis Endry SA — numérotation, calculs et impression. */
(function(){
  'use strict';
  var KEY='endry-devis-v1:'+location.pathname;
  var sheet=document.getElementById('devis');
  var table=document.getElementById('lines');
  /* Format suisse : 14’258.00 */
  function chf(n){
    var neg=n<0;n=Math.abs(Math.round(n*100)/100);
    var parts=n.toFixed(2).split('.');
    var int=parts[0].replace(/\B(?=(\d{3})+(?!\d))/g,'\u2019');
    return (neg?'− ':'')+int+'.'+parts[1];
  }
  var dateFmt=new Intl.DateTimeFormat('fr-CH',{day:'numeric',month:'long',year:'numeric'});

  function parse(text){
    var s=(text||'').replace(/[’'’\s]/g,'').replace(',','.').replace(/[^0-9.\-]/g,'');
    var n=parseFloat(s);return isNaN(n)?0:n;
  }
  function money(n){return chf(n);}
  function round05(n){return Math.round(n*20)/20;}

  function lineTemplate(){
    var tr=document.createElement('tr');tr.className='line';
    tr.innerHTML='<td class="pos"></td><td class="desc" contenteditable="true"></td><td class="qty num" contenteditable="true">1</td><td class="unit" contenteditable="true">pce</td><td class="pu num" contenteditable="true">0.00</td><td class="tot num"></td><td class="rm no-print"><button type="button" title="Supprimer la ligne">×</button></td>';
    return tr;
  }

  function recalc(){
    var groups=table.querySelectorAll('tbody.group');var subtotal=0;
    groups.forEach(function(g,gi){
      var num=String(gi+1).padStart(2,'0');
      var gNum=g.querySelector('.g-num');if(gNum)gNum.textContent=num;
      var name=g.querySelector('.g-name');var ref=g.querySelector('.g-ref');
      if(name&&ref)ref.textContent=name.textContent.trim();
      var sum=0;
      g.querySelectorAll('tr.line').forEach(function(tr,li){
        var q=parse(tr.querySelector('.qty').textContent);
        var p=parse(tr.querySelector('.pu').textContent);
        var t=q*p;sum+=t;
        tr.querySelector('.pos').textContent=(gi+1)+'.'+(li+1);
        tr.querySelector('.tot').textContent=money(t);
      });
      var gt=g.querySelector('.g-total');if(gt)gt.textContent=money(sum);
      subtotal+=sum;
    });
    var remisePct=parse(document.getElementById('t-remise-pct').textContent);
    var tvaPct=parse(document.getElementById('t-tva-pct').textContent);
    var remise=subtotal*remisePct/100;
    var ht=subtotal-remise;
    var tva=ht*tvaPct/100;
    var ttcBrut=ht+tva;
    var ttc=round05(ttcBrut);
    var arrondi=Math.round((ttc-ttcBrut)*100)/100;
    document.getElementById('t-sub').textContent=money(subtotal);
    document.getElementById('t-remise').textContent=remise?'− '+money(remise):money(0);
    document.getElementById('t-ht').textContent=money(ht);
    document.getElementById('t-tva').textContent=money(tva);
    var rndEls=document.querySelectorAll('.totals .rnd');
    rndEls.forEach(function(el){el.classList.toggle('hidden',arrondi===0);});
    document.getElementById('t-arrondi').textContent=(arrondi>0?'+ ':'− ')+money(Math.abs(arrondi));
    document.getElementById('t-ttc').textContent=money(ttc);
  }

  function normalizeMoney(el){
    if(!el.matches('.pu'))return;
    var n=parse(el.textContent);el.textContent=n?n.toFixed(2):'0.00';
  }

  var saveTimer;
  function save(){
    clearTimeout(saveTimer);
    saveTimer=setTimeout(function(){
      try{localStorage.setItem(KEY,sheet.innerHTML);}catch(e){}
    },400);
  }
  function restore(){
    try{var html=localStorage.getItem(KEY);if(html){sheet.innerHTML=html;return true;}}catch(e){}
    return false;
  }

  function setDefaultDates(){
    var today=new Date();var limit=new Date(today);limit.setDate(limit.getDate()+30);
    var d=sheet.querySelector('[data-field="date"]');var v=sheet.querySelector('[data-field="validite"]');
    if(d)d.textContent=dateFmt.format(today);
    if(v)v.textContent='30 jours, soit jusqu’au '+dateFmt.format(limit);
    var sig=sheet.querySelector('.sig p[contenteditable]');
    if(sig&&/^Bussy FR, le /.test(sig.textContent))sig.textContent='Bussy FR, le '+dateFmt.format(today);
  }

  sheet.addEventListener('input',function(e){recalc();save();});
  sheet.addEventListener('focusout',function(e){
    var el=e.target;
    if(el.matches&&el.matches('.pu')){normalizeMoney(el);recalc();save();}
  });
  sheet.addEventListener('keydown',function(e){
    var el=e.target;
    if(e.key==='Enter'&&el.matches&&el.matches('.qty,.pu,.unit,.pct,.doc-no,.refs dd')){e.preventDefault();el.blur();}
  });
  sheet.addEventListener('click',function(e){
    var add=e.target.closest('.add-line');
    if(add){
      var g=add.closest('tbody.group');var sub=g.querySelector('.group-sub');
      var tr=lineTemplate();g.insertBefore(tr,sub);recalc();save();
      tr.querySelector('.desc').focus();return;
    }
    var rm=e.target.closest('.rm button');
    if(rm){
      var g2=rm.closest('tbody.group');
      if(g2.querySelectorAll('tr.line').length>1){rm.closest('tr').remove();}
      else{var tr2=rm.closest('tr');tr2.querySelector('.desc').textContent='';tr2.querySelector('.qty').textContent='1';tr2.querySelector('.pu').textContent='0.00';}
      recalc();save();
    }
  });
  sheet.addEventListener('paste',function(e){
    if(!e.target.isContentEditable)return;
    e.preventDefault();
    var text=(e.clipboardData||window.clipboardData).getData('text/plain');
    document.execCommand('insertText',false,text);
  });

  document.getElementById('btn-print').addEventListener('click',function(){window.print();});
  document.getElementById('btn-reset').addEventListener('click',function(){
    if(!confirm('Repartir du modèle vierge ? Les modifications de ce devis seront perdues.'))return;
    try{localStorage.removeItem(KEY);}catch(e){}
    location.reload();
  });

  if(!restore())setDefaultDates();
  recalc();
})();
