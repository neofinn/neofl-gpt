import { NextRequest, NextResponse } from 'next/server';

// NeoFL Body proxy targets the existing execution gateway. MT5 supplies the
// binding token; the gateway address is an application-side constant.
const gateway = 'https://neofl-execution-gateway-1li631.v2.appdeploy.ai';

function upstreamUrl(upstreamPath: string) {
  const bodyPaths = ['/handshake', '/heartbeat', '/telemetry', '/market-state'];
  const prefix = bodyPaths.includes(upstreamPath) ? '/api/v1/body' : '/api/v1';
  return `${gateway}${prefix}${upstreamPath}`;
}

export async function bodyProxy(request: NextRequest, upstreamPath: string, method: 'GET' | 'POST' = request.method as 'GET' | 'POST') {
  // Accept the canonical header first, then the same binding token in the
  // request body/query for compatibility with MT5 WebRequest implementations.
  let rawBody: string | undefined;
  let bodyToken = '';
  if (method !== 'GET') {
    rawBody = await request.text();
    if (rawBody) {
      try {
        const parsed = JSON.parse(rawBody);
        bodyToken = typeof parsed?.binding_token === 'string' ? parsed.binding_token.trim() : '';
      } catch {
        bodyToken = '';
      }
    }
  }
  const binding = request.headers.get('x-neofl-binding-token')?.trim() || bodyToken || request.nextUrl.searchParams.get('binding_token')?.trim() || '';
  if (!binding) return NextResponse.json({ error: 'Binding token required' }, { status: 401 });

  const headers = new Headers();
  headers.set('Content-Type', request.headers.get('content-type') || 'application/json');
  headers.set('Accept', 'application/json');
  headers.set('X-NeoFL-Binding-Token', binding);

  const url = new URL(upstreamUrl(upstreamPath));
  request.nextUrl.searchParams.forEach((value, key) => url.searchParams.set(key, value));

  try {
    const response = await fetch(url.toString(), { method, headers, body: rawBody, cache: 'no-store' });
    const text = await response.text();
    return new NextResponse(text, {
      status: response.status,
      headers: {
        'Content-Type': response.headers.get('content-type') || 'application/json',
        'Cache-Control': 'no-store',
      },
    });
  } catch (error) {
    return NextResponse.json({ error: 'NeoFL execution gateway unavailable', detail: String(error) }, { status: 502 });
  }
}
