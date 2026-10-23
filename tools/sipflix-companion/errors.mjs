import {createHash} from 'node:crypto';

const fields = new Set(['deviceName','androidId','server','route','appVersion','category','message','code','timestamp']);
const limits = {deviceName:128,androidId:128,server:128,route:256,appVersion:64,category:64,message:1500,code:64};

export function redact(value) {
  return value
    .replace(/\b(?:authorization|cookie|set-cookie|x-emby-token|x-mediabrowser-token)\s*:\s*[^\r\n]*/gi,'[redacted-header]')
    // Some stream URLs carry credentials in path segments; drop the entire URL.
    .replace(/https?:\/\/[^\s<>"']+/gi, '[redacted-url]')
    .replace(/\bBearer\s+[^\s,;"']+/gi,'Bearer [redacted]')
    .replace(/\bBasic\s+[A-Za-z0-9+/=]+/gi,'Basic [redacted]')
    .replace(/(["']?(?:password|passwd|pwd|pw|token|access[_-]?token|api[_-]?key|authorization|x-emby-token|x-mediabrowser-token|cookie|set-cookie)["']?\s*[:=]\s*)(?:"[^"\r\n]*"|'[^'\r\n]*'|[^\s,;&}\]]+)/gi,'$1[redacted]')
    // Standalone query strings can occur outside a complete URL.
    .replace(/\?[^\s<>"']+/g,'?[redacted]')
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g,'');
}

export function normalizeReport(input, now = Date.now()) {
  if (!input || typeof input !== 'object' || Array.isArray(input) || Object.keys(input).some(key=>!fields.has(key))) throw new Error('Invalid fields');
  const result={};
  for (const [key,max] of Object.entries(limits)) {
    const value=input[key]; if (value === undefined) continue;
    if (typeof value !== 'string' || value.length > max) throw new Error('Invalid field');
    result[key]=redact(value);
  }
  if (!result.category?.trim() || !result.message?.trim()) throw new Error('Category and message required');
  if (input.timestamp !== undefined && (typeof input.timestamp !== 'string' || input.timestamp.length>40 || !Number.isFinite(Date.parse(input.timestamp)))) throw new Error('Invalid timestamp');
  result.timestamp=input.timestamp ? new Date(input.timestamp).toISOString() : new Date(now).toISOString();
  return result;
}

export function airtableSinkFromEnv(env = process.env) {
  const pat=env.AIRTABLE_PAT, base=env.AIRTABLE_BASE_ID ?? 'appHOEeOFIlh9pEH0', table=env.AIRTABLE_TABLE_ID;
  if (!pat || !/^app[A-Za-z0-9]+$/.test(base) || !/^tbl[A-Za-z0-9]+$/.test(table ?? '')) return null;
  return async (fields, signal) => {
    const response=await fetch(`https://api.airtable.com/v0/${base}/${table}`,{
      method:'POST', headers:{Authorization:`Bearer ${pat}`,'Content-Type':'application/json'},
      body:JSON.stringify({records:[{fields}]}), signal,
    });
    // No raw Airtable error text is exposed or logged.
    if (!response.ok) { await response.body?.cancel(); throw new Error('Diagnostic storage unavailable'); }
    const data=await response.json();
    if (!data.records?.[0]?.id) throw new Error('Diagnostic storage did not confirm a record');
  };
}

export function createErrorHandler({sink=airtableSinkFromEnv(),now=Date.now,maxDedupe=2000,maxRateKeys=1000,timeoutMs=8000}={}) {
  const dedupe=new Map(), rates=new Map(); let active=0;
  function allow(key,max) {
    let rate=rates.get(key);
    if (!rate) {
      if (rates.size>=maxRateKeys) return false;
      rate={count:0,until:now()+60000};rates.set(key,rate);
    }
    return ++rate.count<=max;
  }
  return async (req,res) => {
    const reply=(status,body)=>{res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(body));};
    if (req.method !== 'POST') {reply(405,{error:'POST required'});return;}
    for(const [key,item] of rates)if(item.until<=now())rates.delete(key);
    for(const [key,item] of dedupe)if(item.until<=now()&&!item.pending)dedupe.delete(key);
    if(!allow('global',120)||!allow(req.socket.remoteAddress,30)){reply(429,{error:'Diagnostic report limit reached'});return;}
    if(!sink||active>=4){reply(503,{error:'Diagnostic storage unavailable'});return;}
    let report;
    try {
      let size=0;const chunks=[];
      for await(const chunk of req){size+=chunk.length;if(size>8192){reply(413,{error:'Report too large'});return;}chunks.push(chunk);}
      report=normalizeReport(JSON.parse(Buffer.concat(chunks).toString()),now());
    }catch{reply(400,{error:'Invalid diagnostic report'});return;}
    // Ignore timestamp for dedupe; repeated instances within ten minutes share a record.
    const stable=Object.fromEntries(Object.entries(report).filter(([key])=>key!=='timestamp').sort(([a],[b])=>a.localeCompare(b)));
    const key=createHash('sha256').update(JSON.stringify(stable)).digest('hex');
    const previous=dedupe.get(key);
    if(previous){reply(previous.pending?429:202,previous.pending?{error:'Report already pending'}:{accepted:true,duplicate:true});return;}
    if(dedupe.size>=maxDedupe){reply(429,{error:'Diagnostic report capacity reached'});return;}
    const item={pending:true,until:now()+600000};dedupe.set(key,item);active++;
    const controller=new AbortController();let timer;
    try {
      await Promise.race([
        Promise.resolve().then(()=>sink(report,controller.signal)),
        new Promise((_,reject)=>{timer=setTimeout(()=>{controller.abort();reject(new Error('Storage timed out'));},timeoutMs);}),
      ]);
      item.pending=false;
      reply(202,{accepted:true,duplicate:false});
    }catch{
      dedupe.delete(key);reply(503,{error:'Diagnostic storage unavailable'});
    }finally{clearTimeout(timer);active--;}
  };
}
