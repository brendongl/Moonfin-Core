import test from 'node:test';
import assert from 'node:assert/strict';
import {createPairingServer} from './pairing.mjs';
import {createErrorHandler,normalizeReport,redact,airtableSinkFromEnv} from './errors.mjs';
const report={deviceName:'Tester',androidId:'id',server:'Delta',route:'https://user:pass@server/path?api_key=secret',appVersion:'test',category:'network',message:'HTTP 503 Authorization: Bearer secret password="hidden" https://host/path?token=secret',code:'503',timestamp:'2026-10-23T00:00:00Z'};
async function fixture(t,options) {
 const server=createPairingServer({errorHandler:createErrorHandler(options)});await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 t.after(()=>new Promise(resolve=>{server.closeAllConnections();server.close(resolve);}));
 return async data=>{const res=await fetch(`http://127.0.0.1:${server.address().port}/errors`,{method:'POST',body:JSON.stringify(data)});return {code:res.status,...await res.json()};};
}
test('strict schema, URL/header/password redaction and missing configuration',()=>{
 const value=normalizeReport(report);assert.equal(value.route,'[redacted-url]');assert.ok(!JSON.stringify(value).includes('secret'));assert.ok(!JSON.stringify(value).includes('hidden'));
 assert.throws(()=>normalizeReport({...report,password:'no'}));assert.throws(()=>normalizeReport({...report,message:5}));assert.throws(()=>normalizeReport({...report,timestamp:'bad'}));assert.throws(()=>normalizeReport({...report,message:'x'.repeat(1501)}));
 const quoted=redact(JSON.stringify({Authorization:'Bearer json-secret',Cookie:'session=cookie-secret; second=other-secret',Pw:'pw-secret'}));
 assert.ok(!quoted.includes('json-secret'));assert.ok(!quoted.includes('cookie-secret'));assert.ok(!quoted.includes('other-secret'));assert.ok(!quoted.includes('pw-secret'));
 assert.ok(!redact('stream https://host/seed/path-secret/file').includes('path-secret'));
 assert.equal(airtableSinkFromEnv({}),null);assert.ok(!redact('Cookie=session-secret token=topsecret ?password=foo').includes('topsecret'));
});
test('accepted only after sink confirms; dedupe ignores timestamps and never stores credentials',async t=>{
 const records=[];const send=await fixture(t,{sink:async value=>records.push(value)});
 assert.equal((await send(report)).code,202);const duplicate=await send({...report,timestamp:'2026-10-23T00:01:00Z'});assert.equal(duplicate.duplicate,true);assert.equal(records.length,1);assert.ok(!JSON.stringify(records).includes('secret'));
 assert.equal((await send({...report,arbitrary:'no'})).code,400);assert.equal((await send({...report,message:'a'.repeat(9000)})).code,413);
});
test('sink failure and timeout are 503 and retriable, never acknowledged or cached',async t=>{
 let failing=true,calls=0;const send=await fixture(t,{sink:async()=>{calls++;if(failing)throw new Error('PAT MUST NOT LEAK');}});
 const failure=await send(report);assert.equal(failure.code,503);assert.ok(!JSON.stringify(failure).includes('PAT'));failing=false;assert.equal((await send(report)).code,202);assert.equal(calls,2);
 const timeout=await fixture(t,{sink:()=>new Promise(()=>{}),timeoutMs:5});assert.equal((await timeout(report)).code,503);
 const disabled=await fixture(t,{sink:null});assert.equal((await disabled(report)).code,503);
});
test('per-IP rate and bounded dedupe capacity return 429',async t=>{
 const send=await fixture(t,{sink:async()=>{},maxDedupe:1});assert.equal((await send(report)).code,202);assert.equal((await send({...report,message:'different'})).code,429);
 for(let i=0;i<28;i++)await send(report);assert.equal((await send(report)).code,429);
});
test('concurrent duplicate stays pending until successful write',async t=>{
 let finish;const pending=new Promise(resolve=>finish=resolve);const send=await fixture(t,{sink:()=>pending});
 const first=send(report);await new Promise(resolve=>setTimeout(resolve,15));assert.equal((await send(report)).code,429);finish();assert.equal((await first).code,202);
});
