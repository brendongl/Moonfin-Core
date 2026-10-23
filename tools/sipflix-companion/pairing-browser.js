'use strict';
const [id, capability] = location.hash.slice(1).split('.');
history.replaceState(null, '', location.pathname);
const form=document.getElementById('form'), button=document.getElementById('submit'), status=document.getElementById('status');
let terminal=false;
async function api(action,data={}) {
  const response=await fetch(`/v1/pair/${id}/phone/${action}`,{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${capability}`},body:JSON.stringify(data),signal:AbortSignal.timeout(10000)});
  const result=await response.json(); if(!response.ok) throw new Error(result.error || 'Cannot reach sign-in service'); return result;
}
async function poll(){
  if(terminal)return;
  try{
    const result=await api('status');
    if(['success','failed','cancelled'].includes(result.state)){
      terminal=true;button.disabled=true;form.reset();
      status.textContent=result.message || 'Sign-in was cancelled. Open a new QR code on the TV.';return;
    }
    if(result.state==='submitted'||result.state==='processing'){button.disabled=true;status.textContent='Waiting for your TV to finish signing in…';}
  }catch(error){terminal=true;button.disabled=true;form.reset();status.textContent=error.message;return;}
  setTimeout(poll,2000);
}
form.addEventListener('submit',async event=>{
 event.preventDefault();if(terminal)return;button.disabled=true;
 try{await api('submit',{username:document.getElementById('username').value,password:document.getElementById('password').value});form.reset();status.textContent='Details sent. Waiting for the TV…';}
 catch(error){status.textContent=error.message;button.disabled=false;}
});
if(!/^[A-Za-z0-9_-]{43}$/.test(id ?? '')||!/^[A-Za-z0-9_-]{43}$/.test(capability ?? '')){terminal=true;button.disabled=true;status.textContent='Scan a new QR code from your TV.';}else poll();
