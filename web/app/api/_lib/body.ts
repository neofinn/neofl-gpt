import { NextRequest, NextResponse } from 'next/server';

type Method = 'GET' | 'POST';
const json = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: { 'Cache-Control': 'no-store' } });
function requireBinding(request: NextRequest) {
  const binding = request.headers.get('x-neofl-binding-token')?.trim();
  if (!binding) return { error: json({ error: 'Binding token required' }, 401) };
  return { binding };
}
async function readBody(request: NextRequest) {
  if (request.method === 'GET') return undefined;
  const text = await request.text();
  if (!text) return undefined;
  try { return JSON.parse(text); } catch { return text; }
}
export async function bodyProxy(request: NextRequest, upstreamPath: string, method: Method = request.method as Method) {
  const auth = requireBinding(request);
  if ('error' in auth) return auth.error;
  const payload = await readBody(request);
  const accountNumber = request.nextUrl.searchParams.get('account_number') || null;
  const server = request.nextUrl.searchParams.get('server') || null;
  const connector = request.nextUrl.searchParams.get('connector') || 'MT5';
  const environment = request.nextUrl.searchParams.get('environment') || 'DEMO';
  switch (upstreamPath) {
    case '/handshake': return json({ ok: true, status: 'CONNECTED', connector, environment, account_number: accountNumber, server, binding_authenticated: true, heartbeat_interval_seconds: 10, telemetry_interval_seconds: 5, execution_enabled: false, message: 'NeoFL Body API connected; execution remains fail-closed until the account is authorized.' });
    case '/heartbeat': return json({ ok: true, status: 'ALIVE', account_number: accountNumber, server, binding_authenticated: true, timestamp: new Date().toISOString() });
    case '/telemetry':
    case '/market-state': return json({ ok: true, accepted: true, account_number: accountNumber, server, received_at: new Date().toISOString() });
    case '/execution/next': return json({ ok: true, intent: null, execution_enabled: false, message: 'No executable OrderIntent available.' });
    case '/execution-report': return json({ ok: true, accepted: true, report: payload ?? null });
    case '/accounts': return json({ ok: true, account: accountNumber ? { account_number: accountNumber, server, connector, environment } : null });
    case '/order-intents': return json({ ok: true, accepted: true, execution_enabled: false, intent: payload ?? null, message: 'OrderIntent accepted into Body boundary but execution is fail-closed until account authorization is active.' }, 202);
    default: return json({ error: 'Unsupported Body route', path: upstreamPath, method }, 404);
  }
}
