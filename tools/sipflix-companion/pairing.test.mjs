import test from 'node:test';
import assert from 'node:assert/strict';
import {createPairingServer} from './pairing.mjs';

async function fixture(t,options={}) {
 const server=createPairingServer(options);await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 t.after(()=>new Promise(resolve=>{server.closeAllConnections();server.close(resolve);}));
 const base=`http://127.0.0.1:${server.address().port}`;
 async function request(path,data={},key){const response=await fetch(base+path,{method:'POST',headers:{'Content-Type':'application/json',...(key?{Authorization:`Bearer ${key}`}:{})},body:JSON.stringify(data)});return {code:response.status,...await response.json()};}
 const create=()=>request('/v1/pair');
 const call=(s,role,action,data={},key=s[role])=>request(`/v1/pair/${s.id}/${role}/${action}`,data,key);
 return {create,call,base,request};
}
test('phone submission is not success; TV consumes once and acknowledges attempt',async t=>{
 const {create,call}=await fixture(t);const s=await create();assert.equal(s.code,201);assert.notEqual(s.phone,s.tv);
 assert.equal((await call(s,'tv','ack',{success:true,attempt:'x'})).code,409);
 assert.equal((await call(s,'phone','submit',{username:'tester',password:'secret'})).code,202);
 assert.equal((await call(s,'phone','submit',{username:'other',password:'other'})).code,409);
 const status=await call(s,'phone','status');assert.equal(status.state,'submitted');assert.equal(status.credentials,undefined);
 assert.equal((await call(s,'phone','poll')).code,403);
 assert.equal((await call(s,'tv','poll',{},s.phone)).code,403);
 const first=await call(s,'tv','poll');assert.deepEqual(first.credentials,{username:'tester',password:'secret'});
 assert.equal((await call(s,'tv','poll')).credentials,undefined);
 assert.equal((await call(s,'phone','status')).state,'processing');
 assert.equal((await call(s,'tv','ack',{success:true,attempt:'wrong'})).code,409);
 assert.equal((await call(s,'phone','ack',{success:true,attempt:first.attempt})).code,403);
 assert.equal((await call(s,'tv','ack',{success:true,attempt:first.attempt})).state,'success');
 assert.equal((await call(s,'phone','status')).state,'success');
 assert.equal((await call(s,'tv','cancel')).state,'success');
});
test('failed/cancelled/expired and processing timeout never produce success',async t=>{
 let clock=1000;const {create,call}=await fixture(t,{now:()=>clock});
 const failed=await create();await call(failed,'phone','submit',{username:'u',password:'p'});const consumed=await call(failed,'tv','poll');
 await call(failed,'tv','ack',{success:false,attempt:consumed.attempt,error:'sensitive'});
 const status=await call(failed,'phone','status');assert.equal(status.state,'failed');assert.ok(!JSON.stringify(status).includes('sensitive'));
 const cancelled=await create();await call(cancelled,'phone','submit',{username:'u',password:'p'});await call(cancelled,'tv','cancel');assert.equal((await call(cancelled,'tv','poll')).credentials,undefined);assert.equal((await call(cancelled,'phone','status')).state,'cancelled');
 const timed=await create();await call(timed,'phone','submit',{username:'u',password:'p'});const work=await call(timed,'tv','poll');clock+=61000;assert.equal((await call(timed,'phone','status')).state,'failed');assert.equal((await call(timed,'tv','ack',{success:true,attempt:work.attempt})).code,409);
 clock+=300000;assert.equal((await call(timed,'phone','status')).code,410);
});
test('bounded capacity, bodies, rate limits and cross-session capabilities',async t=>{
 const {create,call,request}=await fixture(t,{maxSessions:2});const a=await create(),b=await create();assert.equal((await create()).code,429);
 assert.equal((await call(a,'tv','poll',{},b.tv)).code,403);
 assert.equal((await call(a,'phone','submit',{username:'x',password:'x'.repeat(5000)})).code,413);
 assert.equal((await call(a,'phone','submit',{username:'x',password:42})).code,400);
 for(let i=0;i<180;i++)await call(b,'phone','status');assert.equal((await call(b,'phone','status')).code,429);
 assert.equal((await request('/v1/pair/not-a-session/tv/poll')).code,404);
});
test('page uses fragment capability, no third-party script, no cache and no CORS',async t=>{
 const {base}=await fixture(t);const res=await fetch(base+'/pair');assert.equal(res.headers.get('cache-control'),'no-store');assert.equal(res.headers.get('access-control-allow-origin'),null);assert.ok(res.headers.get('content-security-policy').includes("frame-ancestors 'none'"));
 const html=await res.text();assert.ok(html.includes('https://wa.me/84387592427'));assert.ok(html.includes('src="/pair.js"'));const js=await (await fetch(base+'/pair.js')).text();assert.ok(js.includes('location.hash'));assert.ok(js.includes('history.replaceState'));
});
