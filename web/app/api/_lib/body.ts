import { NextRequest, NextResponse } from 'next/server';

// NeoFL Body proxy targets the existing execution gateway. MT5 supplies only the
// binding token; the gateway address is an application-side constant.
const gateway = 'https://neofl-execution-gateway-1li631.v2.appdeploy.ai';

function upstreamUrl(upstreamPath: string) {
  const bodyPaths = ['/handshake', '/heartbeat', '/telemetry', '/market-state'];
  const prefix = bodyPaths.includes(upstreamPath) ? '/api/v1/body' : '/api/v1';
  return `${gateway}${prefix}${upstreamPath}`;
}

export async function bodyProxy(request: NextRequest, upstreamPath: string, method: 'GET' | 'POST' = request.method as 'GET' | 'POST') {
  const binding = request.headers.get('x-neofl-binding-token')?.trim() || '';
  if (!binding) return NextResponse.json({ error: 'Binding token required' }, { status: 401 });

  const headers = new Headers();
  headers.set('Content-Type', request.headers.get('content-type') || 'application/json');
  headers.set('Accept', 'application/json');
  headers.set('X-NeoFL-Binding-Token', binding);

  const url = new URL(upstreamUrl(upstreamPath));
  request.nextUrl.searchParams.forEach((value, key) => url.searchParams.set(key, value));

  let body: string | undefined;
  if (method !== 'GET') body = await request.text();

  try {
    const response = await fetch(url.toString(), { method, headers, body, cache: 'no-store' });
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
