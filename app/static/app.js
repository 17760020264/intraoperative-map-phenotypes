const $ = (s) => document.querySelector(s);
const $$ = (s) => document.querySelectorAll(s);
let selectedFile = null;
let drawPoints = [];

$$('.tab').forEach(btn => btn.addEventListener('click', () => {
  $$('.tab').forEach(x => x.classList.remove('active'));
  $$('.panel').forEach(x => x.classList.remove('active'));
  btn.classList.add('active');
  $(`#${btn.dataset.tab}Panel`).classList.add('active');
  if (btn.dataset.tab === 'draw') drawCanvas();
}));

$('#chooseFile').onclick = () => $('#fileInput').click();
$('#fileInput').onchange = e => setFile(e.target.files[0]);
function setFile(file){ selectedFile=file; $('#fileName').textContent=file ? `已选择：${file.name}` : ''; }
['dragenter','dragover'].forEach(evt => $('#dropzone').addEventListener(evt,e=>{e.preventDefault();$('#dropzone').classList.add('dragover')}));
['dragleave','drop'].forEach(evt => $('#dropzone').addEventListener(evt,e=>{e.preventDefault();$('#dropzone').classList.remove('dragover')}));
$('#dropzone').addEventListener('drop',e=>setFile(e.dataTransfer.files[0]));

function parsePaste(text){
  const time=[], map=[];
  text.trim().split(/\r?\n/).forEach((line,idx)=>{
    const cells=line.trim().split(/[\t,;，\s]+/);
    if(cells.length<2) return;
    const m=Number(cells[cells.length-1]);
    const t=Number(cells[0]);
    if(Number.isFinite(t)&&Number.isFinite(m)){time.push(t);map.push(m)}
    else if(idx>0){ /* tolerate a header */ }
  });
  return {time,map,source:'paste'};
}

$('#loadExample').onclick=()=>{$('#pasteData').value='0,95\n10,88\n20,75\n30,62\n40,58\n50,65\n60,78\n75,86\n90,92\n105,80\n120,88'};
$('#analyzePaste').onclick=()=>runJSON(parsePaste($('#pasteData').value));
$('#analyzeFile').onclick=async()=>{
  if(!selectedFile) return alert('请先选择CSV或Excel文件。');
  showLoading(true);
  const form=new FormData(); form.append('file',selectedFile);
  try{const res=await fetch('/api/classify-file',{method:'POST',body:form}); await handleResponse(res)}catch(e){showError(e)}finally{showLoading(false)}
};

async function runJSON(payload){
  showLoading(true);
  try{const res=await fetch('/api/classify',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});await handleResponse(res)}catch(e){showError(e)}finally{showLoading(false)}
}
async function handleResponse(res){const data=await res.json();if(!res.ok)throw new Error(data.detail||'分析失败');renderResult(data)}
function showError(e){alert(e.message||'分析失败，请检查输入格式。')}
function showLoading(v){$('#loading').classList.toggle('hidden',!v)}

function renderResult(d){
  $('#results').classList.remove('hidden');
  $('#phenotypeName').textContent=d.phenotype;
  $('#phenotypeName').style.color=d.color;
  $('#classificationCard').style.borderTopColor=d.color;
  $('#confidenceLabel').textContent=d.confidence_label;
  $('#similarityBars').innerHTML=d.similarities.map(x=>`<div class="sim-row"><div class="sim-label"><span>${x.phenotype}</span><span>${x.value}% · d=${x.distance}</span></div><div class="bar"><i style="width:${x.value}%;background:${x.color}"></i></div></div>`).join('');
  $('#warningBox').innerHTML=d.warnings.map(x=>`<div class="notice">${x}</div>`).join('');
  $('#traceAudit').textContent=`${d.audit.valid_records} points · ${d.audit.duration_min} min · max gap ${d.audit.maximum_gap_min} min`;
  drawTrace($('#resultCanvas'),d.trace.time,d.trace.map,d.color);
  const wanted=['Baseline MAP','Mean MAP','Minimum MAP','Maximum MAP','Time-weighted MAP','MAP SD','Time MAP <65, min'];
  $('#metricsGrid').innerHTML=wanted.map(k=>`<div class="metric"><b>${d.summary[k] ?? '—'}</b><span>${k}</span></div>`).join('');
  $('#riskTables').innerHTML=Object.entries(d.observed_risks).map(([center,rows])=>`<div class="risk-center"><h4>${center}</h4><table class="risk-table"><tbody>${Object.entries(rows).map(([k,v])=>`<tr><td>${k}</td><td>${v.toFixed(2)}%</td></tr>`).join('')}</tbody></table></div>`).join('');
  $('#featureTable').innerHTML='<thead><tr><th>Feature</th><th>Domain</th><th>Raw</th><th>Robust z</th></tr></thead><tbody>'+d.features.map(x=>`<tr><td>${x.feature}</td><td>${x.domain}</td><td>${x.raw}</td><td>${x.standardized}</td></tr>`).join('')+'</tbody>';
  $('#results').scrollIntoView({behavior:'smooth'});
}

$('#printResult').onclick=()=>window.print();

const canvas=$('#mapCanvas'),ctx=canvas.getContext('2d');
function coordsToData(x,y){const p=55,w=canvas.width-p-25,h=canvas.height-p-25;return {t:Math.max(0,Math.min(1,(x-p)/w))*Number($('#drawDuration').value),m:160-Math.max(0,Math.min(1,(y-20)/h))*120}}
function dataToCoords(t,m){const p=55,w=canvas.width-p-25,h=canvas.height-p-25;return {x:p+t/Number($('#drawDuration').value)*w,y:20+(160-m)/120*h}}
function drawCanvas(){
  const w=canvas.width,h=canvas.height,p=55;ctx.clearRect(0,0,w,h);ctx.fillStyle='#fff';ctx.fillRect(0,0,w,h);
  ctx.font='13px system-ui';ctx.textAlign='right';ctx.textBaseline='middle';
  for(let m=40;m<=160;m+=10){const y=dataToCoords(0,m).y;ctx.strokeStyle=m===65?'#d95b64':m===120?'#2f8f83':'#e8ece9';ctx.lineWidth=(m===65||m===120)?2:1;ctx.beginPath();ctx.moveTo(p,y);ctx.lineTo(w-25,y);ctx.stroke();ctx.fillStyle='#65757a';ctx.fillText(m,p-9,y)}
  ctx.textAlign='center';ctx.textBaseline='top';for(let f=0;f<=1.001;f+=.1){const t=Math.round(Number($('#drawDuration').value)*f),x=dataToCoords(t,100).x;ctx.strokeStyle='#edf0ed';ctx.beginPath();ctx.moveTo(x,20);ctx.lineTo(x,h-p);ctx.stroke();ctx.fillStyle='#65757a';ctx.fillText(t,x,h-p+8)}
  ctx.fillStyle='#17252c';ctx.fillText('Time, min',w/2,h-20);ctx.save();ctx.translate(15,h/2);ctx.rotate(-Math.PI/2);ctx.fillText('MAP, mmHg',0,0);ctx.restore();
  if(drawPoints.length){ctx.strokeStyle='#183d49';ctx.lineWidth=4;ctx.lineJoin='round';ctx.lineCap='round';ctx.beginPath();drawPoints.forEach((q,i)=>{const c=dataToCoords(q.t,q.m);i?ctx.lineTo(c.x,c.y):ctx.moveTo(c.x,c.y)});ctx.stroke()}
}
function pointerPos(e){const r=canvas.getBoundingClientRect();return{x:(e.clientX-r.left)*canvas.width/r.width,y:(e.clientY-r.top)*canvas.height/r.height}}
let drawing=false;
canvas.addEventListener('pointerdown',e=>{drawing=true;canvas.setPointerCapture(e.pointerId);const p=coordsToData(...Object.values(pointerPos(e)));drawPoints=[p];drawCanvas()});
canvas.addEventListener('pointermove',e=>{if(!drawing)return;const c=pointerPos(e),p=coordsToData(c.x,c.y);if(!drawPoints.length||p.t>drawPoints.at(-1).t+.3)drawPoints.push(p);drawCanvas()});
canvas.addEventListener('pointerup',()=>drawing=false);canvas.addEventListener('pointercancel',()=>drawing=false);
$('#drawDuration').onchange=drawCanvas;$('#clearCanvas').onclick=()=>{drawPoints=[];drawCanvas()};
$('#analyzeDraw').onclick=()=>{if(drawPoints.length<2)return alert('请从左至右绘制一条MAP曲线。');const pts=[...drawPoints].sort((a,b)=>a.t-b.t);runJSON({time:pts.map(x=>x.t),map:pts.map(x=>x.m),source:'draw'})};

function drawTrace(c,time,map,color){
  const x=c.getContext('2d'),w=c.width,h=c.height,p=50;x.clearRect(0,0,w,h);x.fillStyle='#fff';x.fillRect(0,0,w,h);
  const maxT=Math.max(...time),toX=t=>p+t/maxT*(w-p-20),toY=m=>20+(160-m)/120*(h-p-20);
  for(let m=40;m<=160;m+=20){const y=toY(m);x.strokeStyle=m===60||m===120?'#cad5d2':'#edf0ed';x.beginPath();x.moveTo(p,y);x.lineTo(w-20,y);x.stroke();x.fillStyle='#65757a';x.textAlign='right';x.font='12px system-ui';x.fillText(m,p-8,y+4)}
  x.strokeStyle=color;x.lineWidth=3;x.lineJoin='round';x.beginPath();time.forEach((t,i)=>i?x.lineTo(toX(t),toY(map[i])):x.moveTo(toX(t),toY(map[i])));x.stroke();x.fillStyle='#65757a';x.textAlign='center';x.fillText('Time, min',w/2,h-10)
}
window.addEventListener('load',drawCanvas);

