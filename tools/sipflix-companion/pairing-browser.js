'use strict';
const form = document.getElementById('form');
const button = document.getElementById('submit');
const status = document.getElementById('status');
let current = null;
let timer = null;

async function api(session, action, data = {}) {
  const response = await fetch(`/v1/pair/${session.id}/phone/${action}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session.capability}` },
    body: JSON.stringify(data), signal: AbortSignal.timeout(10000),
  });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || 'Cannot reach sign-in service');
  return result;
}

async function poll(session) {
  if (current !== session || session.terminal) return;
  try {
    const result = await api(session, 'status');
    if (current !== session) return;
    if (['success', 'failed', 'cancelled'].includes(result.state)) {
      session.terminal = true;
      button.disabled = true;
      form.reset();
      status.textContent = result.message || 'Sign-in was cancelled. Open a new QR code on the TV.';
      return;
    }
    if (result.state === 'submitted' || result.state === 'processing') {
      button.disabled = true;
      status.textContent = 'Waiting for your TV to finish signing in…';
    }
  } catch (error) {
    if (current !== session) return;
    session.terminal = true;
    button.disabled = true;
    form.reset();
    status.textContent = error.message;
    return;
  }
  if (current === session) timer = setTimeout(() => poll(session), 2000);
}

function initializePairing() {
  // Scanning a new QR in this tab may be hash-only navigation. Replacing history
  // below does not reload the script; explicitly retire old timers/responses.
  clearTimeout(timer);
  timer = null;
  const [id, capability] = location.hash.slice(1).split('.');
  history.replaceState(null, '', location.pathname);
  const session = { id, capability, terminal: false };
  current = session;
  form.reset();
  button.disabled = false;
  status.textContent = '';
  if (!/^[A-Za-z0-9_-]{43}$/.test(id ?? '') || !/^[A-Za-z0-9_-]{43}$/.test(capability ?? '')) {
    session.terminal = true;
    button.disabled = true;
    status.textContent = 'Scan a new QR code from your TV.';
    return;
  }
  void poll(session);
}

form.addEventListener('submit', async event => {
  event.preventDefault();
  const session = current;
  if (!session || session.terminal || button.disabled) return;
  button.disabled = true;
  try {
    await api(session, 'submit', {
      username: document.getElementById('username').value,
      password: document.getElementById('password').value,
    });
    if (current !== session || session.terminal) return;
    form.reset();
    status.textContent = 'Details sent. Waiting for the TV…';
  } catch (error) {
    if (current !== session || session.terminal) return;
    status.textContent = error.message;
    button.disabled = false;
  }
});
window.addEventListener('hashchange', initializePairing);
initializePairing();
