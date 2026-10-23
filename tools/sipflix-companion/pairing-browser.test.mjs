import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const script=readFileSync(new URL('./pairing-browser.js',import.meta.url),'utf8');
const key=char=>char.repeat(43);
const flush=()=>new Promise(resolve=>setImmediate(resolve));
function harness(fetcher) {
 const handlers={},formHandlers={},timers=new Map();let next=0;
 const nodes={status:{textContent:''},submit:{disabled:false},username:{value:'tester'},password:{value:'secret'},form:{reset(){nodes.username.value='';nodes.password.value='';},addEventListener(name,callback){formHandlers[name]=callback;}}};
 const location={hash:`#${key('a')}.${key('b')}`,pathname:'/pair'};
 const context={document:{getElementById:id=>nodes[id]},location,history:{replaceState(){location.hash='';}},window:{addEventListener(name,callback){handlers[name]=callback;}},fetch:fetcher,AbortSignal:{timeout:()=>undefined},setTimeout(callback){timers.set(++next,callback);return next;},clearTimeout(id){timers.delete(id);}};
 vm.runInNewContext(script,context);
 return {nodes,timers,async scan(id,capability){location.hash=`#${id}.${capability}`;handlers.hashchange();await flush();},submit(){return formHandlers.submit({preventDefault(){}});}};
}
const response=(value,ok=true)=>({ok,json:async()=>value});
test('same-tab rescan reinitializes successful prior pairing and observes cancellation',async()=>{
 const paths=[];
 const h=harness(async path=>{paths.push(path);return response(path.includes(key('a'))?{state:'success',message:'First TV signed in'}:{state:'cancelled'});});
 await flush();assert.equal(h.nodes.status.textContent,'First TV signed in');assert.equal(h.nodes.submit.disabled,true);
 await h.scan(key('c'),key('d'));
 assert.ok(h.nodes.status.textContent.includes('cancelled'));assert.equal(paths.length,2);assert.ok(paths[1].includes(key('c')));
});
test('rescan clears old polling timer and old in-flight response cannot overwrite new session',async()=>{
 let release;const old=new Promise(resolve=>release=resolve);
 const h=harness(async path=>path.includes(key('a'))?old:response({state:'processing'}));
 await h.scan(key('c'),key('d'));assert.ok(h.nodes.status.textContent.includes('Waiting'));assert.equal(h.timers.size,1);
 release(response({state:'success',message:'OLD SUCCESS'}));await flush();assert.ok(!h.nodes.status.textContent.includes('OLD'));assert.equal(h.timers.size,1);
 await h.scan(key('e'),key('f'));assert.equal(h.timers.size,1);
});
test('stale submission failure cannot re-enable a cancelled newly scanned session',async()=>{
 let release;const old=new Promise(resolve=>release=resolve);
 const h=harness(async path=>path.endsWith('/submit')?old:response(path.includes(key('a'))?{state:'waiting'}:{state:'cancelled'}));
 await flush();h.nodes.username.value='tester';h.nodes.password.value='secret';const submitting=h.submit();
 await h.scan(key('c'),key('d'));release(response({error:'OLD FAILURE'},false));await submitting;
 assert.ok(h.nodes.status.textContent.includes('cancelled'));assert.equal(h.nodes.submit.disabled,true);
});
