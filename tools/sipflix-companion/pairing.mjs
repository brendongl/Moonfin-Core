import http from 'node:http';
import { createErrorHandler } from './errors.mjs';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const page = readFileSync(new URL('./pairing.html', import.meta.url));
const token = () => randomBytes(32).toString('base64url');
const equal = (a, b) => typeof a === 'string' && a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b));

// No persistent state, logging, credentials in URLs, or third-party dependencies.
export function createPairingServer({ now = Date.now, ttlMs = 300000, maxSessions = 500, maxRateKeys = 2000, errorHandler = createErrorHandler() } = {}) {
  const sessions = new Map();
  const rates = new Map();
  function sweep() {
    const time = now();
    for (const [id, s] of sessions) {
      if (s.expires <= time) sessions.delete(id);
      else if (s.state === 'processing' && time - s.processingAt > 60000) {
        s.state = 'failed'; s.message = 'The TV did not finish signing in. Try again on the TV.'; s.credentials = null;
      }
    }
    for (const [key, value] of rates) if (value.until <= time) rates.delete(key);
  }
  function rate(key, limit) {
    let value = rates.get(key);
    if (!value) {
      if (rates.size >= maxRateKeys) return false;
      value = { count: 0, until: now() + 60000 }; rates.set(key, value);
    }
    return ++value.count <= limit;
  }
  async function body(req) {
    let bytes = 0; const chunks = [];
    for await (const chunk of req) {
      bytes += chunk.length;
      if (bytes > 4096) throw Object.assign(new Error('Request too large'), { status: 413 });
      chunks.push(chunk);
    }
    try { return JSON.parse(Buffer.concat(chunks).toString() || '{}'); }
    catch { throw Object.assign(new Error('Invalid request'), { status: 400 }); }
  }
  const server = http.createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Content-Security-Policy', "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; connect-src 'self'; form-action 'none'; frame-ancestors 'none'; base-uri 'none'");
    const reply = (status, value) => { res.writeHead(status, {'Content-Type': 'application/json'}); res.end(JSON.stringify(value)); };
    try {
      sweep();
      const path = req.url?.split('?')[0];
      if (path === '/errors') { await errorHandler(req, res); return; }
      if (req.method === 'GET' && path === '/pair') { res.writeHead(200, {'Content-Type': 'text/html; charset=utf-8'}); res.end(page); return; }
      if (req.method === 'GET' && path === '/pair.js') { res.writeHead(200, {'Content-Type': 'text/javascript'}); res.end(readFileSync(new URL('./pairing-browser.js', import.meta.url))); return; }
      if (req.method === 'GET' && path === '/health') { reply(200, {ok:true}); return; }
      if (req.method !== 'POST') { reply(405, {error:'POST required'}); return; }
      // Only trust socket address; forwarded addresses require a separately audited proxy policy.
      if (!rate(`ip:${req.socket.remoteAddress}`, 1200)) { reply(429, {error:'Please wait before trying again'}); return; }
      if (path === '/v1/pair') {
        if (!rate(`create:${req.socket.remoteAddress}`, 20) || sessions.size >= maxSessions) { reply(429, {error:'Pairing busy. Try again shortly.'}); return; }
        await body(req);
        if (sessions.size >= maxSessions) { reply(429, {error:'Pairing busy. Try again shortly.'}); return; }
        const id = token(); const phone = token(); const tv = token();
        sessions.set(id, {phone,tv,expires:now()+ttlMs,state:'waiting',credentials:null,attempt:null});
        reply(201, {id,phone,tv,expiresIn:ttlMs/1000}); return;
      }
      const match = /^\/v1\/pair\/([A-Za-z0-9_-]{43})\/(phone|tv)\/(submit|status|poll|ack|cancel)$/.exec(path ?? '');
      if (!match) { reply(404,{error:'Not found'}); return; }
      const [,id,role,action] = match; const s = sessions.get(id);
      if (!s) { reply(410,{error:'Pairing expired. Open phone sign-in again on the TV.'}); return; }
      const capability = req.headers.authorization?.replace(/^Bearer /,'');
      if (!equal(capability,s[role])) { reply(403,{error:'Invalid pairing link'}); return; }
      if (!rate(`session:${id}`, 180)) { reply(429,{error:'Please wait'}); return; }
      const data = await body(req);
      if (role === 'phone' && action === 'submit') {
        if (s.state !== 'waiting') { reply(409,{error:'Already submitted. Check the TV or open a new QR code.'}); return; }
        if (typeof data.username !== 'string' || !data.username.trim() || data.username.length > 256 || typeof data.password !== 'string' || data.password.length > 1024) { reply(400,{error:'Enter a valid username and password'}); return; }
        s.credentials = {username:data.username.trim(),password:data.password}; s.attempt=token(); s.state='submitted';
        reply(202,{state:s.state}); return;
      }
      if (role === 'tv' && action === 'poll') {
        if (s.state === 'submitted') {
          const credentials = s.credentials; s.credentials=null; s.state='processing'; s.processingAt=now();
          reply(200,{state:s.state,attempt:s.attempt,credentials}); return;
        }
        reply(200,{state:s.state}); return;
      }
      if (role === 'tv' && action === 'ack') {
        if (s.state !== 'processing' || !equal(data.attempt,s.attempt) || typeof data.success !== 'boolean') { reply(409,{error:'No matching sign-in in progress'}); return; }
        s.state=data.success ? 'success' : 'failed';
        // Never echo arbitrary TV/server error text: it can contain tokens or credentials.
        s.message=data.success ? 'Signed in on your TV.' : 'Sign-in did not finish. Check your details and reopen phone sign-in on the TV.';
        reply(200,{state:s.state}); return;
      }
      if (role === 'tv' && action === 'cancel') {
        if (s.state !== 'success') {s.state='cancelled';s.credentials=null;}
        reply(200,{state:s.state}); return;
      }
      if (role === 'phone' && action === 'status') { reply(200,{state:s.state,message:s.message}); return; }
      reply(403,{error:'Action not allowed'});
    } catch (error) {
      if (!res.headersSent) reply(error.status ?? 400,{error:error.status === 413 ? 'Request too large' : 'Invalid request'});
      else res.end();
    }
  });
  server.requestTimeout=10000; server.headersTimeout=10000; server.timeout=15000; server.maxConnections=100;
  return server;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const server = createPairingServer();
  server.listen(Number(process.env.PORT ?? 8787),process.env.HOST ?? '127.0.0.1');
}
