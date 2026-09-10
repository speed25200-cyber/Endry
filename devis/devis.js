/* Devis Endry SA — numérotation, calculs et impression. */
(function(){
  'use strict';
  var KEY='endry-devis-v1:'+location.pathname;
  var sheet=document.getElementById('devis');
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

  function q(root,sel){return root.querySelector(sel);}
  function pct(root,sel,dflt){var el=q(root,sel);return el?parse(el.textContent):dflt;}

  function recalcPart(part){
    var table=q(part,'table.lines');if(!table)return null;
    var groups=table.querySelectorAll('tbody.group');var subtotal=0;var recapGroups=[];
    groups.forEach(function(g,gi){
      var num=String(gi+1).padStart(2,'0');
      var gNum=q(g,'.g-num');if(gNum)gNum.textContent=num;
      var name=q(g,'.g-name');var ref=q(g,'.g-ref');
      if(name&&ref)ref.textContent=name.textContent.trim();
      var sum=0;
      g.querySelectorAll('tr.line').forEach(function(tr,li){
        var qty=parse(q(tr,'.qty').textContent);
        var p=parse(q(tr,'.pu').textContent);
        var t=qty*p;sum+=t;
        q(tr,'.pos').textContent=(gi+1)+'.'+(li+1);
        q(tr,'.tot').textContent=money(t);
      });
      var gt=q(g,'.g-total');if(gt)gt.textContent=money(sum);
      subtotal+=sum;recapGroups.push({num:num,name:name?name.textContent.trim():'',total:sum});
    });
    var remisePct=pct(part,'.t-remise-pct',0);
    var tvaPct=pct(part,'.t-tva-pct',8.1);
    var remise=subtotal*remisePct/100;
    var ht=subtotal-remise;
    var tva=ht*tvaPct/100;
    var ttcBrut=ht+tva;
    var ttc=round05(ttcBrut);
    var arrondi=Math.round((ttc-ttcBrut)*100)/100;
    var set=function(sel,val){var el=q(part,sel);if(el)el.textContent=val;};
    set('.t-sub',money(subtotal));
    set('.t-remise',remise?'− '+money(remise):money(0));
    set('.t-ht',money(ht));
    set('.t-tva',money(tva));
    part.querySelectorAll('.totals .rnd').forEach(function(el){el.classList.toggle('hidden',arrondi===0);});
    set('.t-arrondi',(arrondi>0?'+ ':'− ')+money(Math.abs(arrondi)));
    set('.t-ttc',money(ttc));
    return {name:part.getAttribute('data-part')||'',groups:recapGroups,remisePct:remisePct,remise:remise,ht:ht,tvaPct:tvaPct,tva:tva,arrondi:arrondi,ttc:ttc};
  }

  function recalc(){
    var parts=sheet.querySelectorAll('.part');if(!parts.length)parts=[sheet];
    var results=[];
    parts.forEach(function(p){var r=recalcPart(p);if(r)results.push(r);});
    var multi=results.length>1;
    document.querySelectorAll('.ttc-mirror').forEach(function(el){
      if(!multi){el.textContent=results.length?'CHF '+money(results[0].ttc):'';return;}
      el.innerHTML=results.map(function(r){return '<span class="nowrap">'+r.name+' CHF '+money(r.ttc)+'</span>';}).join('<br>');
    });
    var recap=document.getElementById('recap-body');
    if(recap){
      var rows='';
      results.forEach(function(r){
        if(multi)rows+='<tr class="r-part"><td colspan="3">'+r.name+'</td></tr>';
        r.groups.forEach(function(g){rows+='<tr><td>'+g.num+'</td><td>'+g.name+'</td><td>'+money(g.total)+'</td></tr>';});
        if(r.remise)rows+='<tr class="r-sum"><td></td><td>Remise '+r.remisePct+' %</td><td>− '+money(r.remise)+'</td></tr>';
        rows+='<tr class="r-sum"><td></td><td>Total HT</td><td>'+money(r.ht)+'</td></tr>';
        rows+='<tr class="r-sum"><td></td><td>TVA '+r.tvaPct+' %</td><td>'+money(r.tva)+'</td></tr>';
        if(r.arrondi!==0)rows+='<tr class="r-sum"><td></td><td>Arrondi</td><td>'+(r.arrondi>0?'+ ':'− ')+money(Math.abs(r.arrondi))+'</td></tr>';
        rows+='<tr class="r-ttc"><td></td><td>Total TTC'+(multi?' '+r.name.toLowerCase():'')+', CHF</td><td>'+money(r.ttc)+'</td></tr>';
      });
      recap.innerHTML=rows;
    }
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
