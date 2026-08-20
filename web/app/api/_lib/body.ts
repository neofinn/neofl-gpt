import { NextRequest, NextResponse } from 'next/server';

// NeoFL Body proxy targets the existing execution gateway. MT5 supplies the
// binding token; the gateway address is an application-side constant.
const gateway = 'https://neofl-execution-gateway-1li631.v2.appdeploy.ai';

function upstreamTarget(upstreamPath: string, incomingMethod: string) {
  const bodyPaths = ['/handshake', '/heartbeat', '/telemetry', '/market-state'];
  if (incomingMethod === 'GET' && upstreamPath === '/execution/next') return '/api/v1/mt5/bridge';
  if (incomingMethod === 'GET' && upstreamPath === '/execution-report') return '/api/v1/execution-report';
  const prefix = bodyPaths.includes(upstreamPath) ? '/api/v1/body' : '/api/v1';
  return `${prefix}${upstreamPath}`;
}

export async function bodyProxy(request: NextRequest, upstreamPath: string, method: 'GET' | 'POST' = request.method as 'GET' | 'POST') {
  let rawBody: string | undefined;
  let parsedBody: Record<string, unknown> = {};
  if (method !== 'GET') {
    rawBody = await request.text();
    if (rawBody) {
      try {
        const parsed = JSON.parse(rawBody);
        if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) parsedBody = parsed;
      } catch {}
    }
  } else {
    request.nextUrl.searchParams.forEach((value, key) => { parsedBody[key] = value; });
  }

  const binding = request.headers.get('x-neofl-binding-token')?.trim() || (typeof parsedBody.binding_token === 'string' ? parsedBody.binding_token.trim() : '');
  if (!binding) return NextResponse.json({ error: 'Binding token required' }, { status: 401 });

  const headers = new Headers();
  headers.set('Content-Type', 'application/json');
  headers.set('Accept', 'application/json');
  headers.set('X-NeoFL-Binding-Token', binding);

  const incomingGet = method === 'GET';
  let upstreamMethod: 'GET' | 'POST' = method;
  let body = rawBody;
  if (incomingGet && ['/handshake', '/heartbeat', '/telemetry', '/market-state', '/execution-report', '/execution/next'].includes(upstreamPath)) {
    upstreamMethod = 'POST';
    if (upstreamPath === '/execution/next') parsedBody.operation = 'execution_next';
    body = JSON.stringify(parsedBody);
  }

  const url = new URL(`${gateway}${upstreamTarget(upstreamPath, method)}`);
  if (!incomingGet || upstreamPath === '/execution/next' || upstreamPath === '/execution-report') {
    // Query parameters are represented in the JSON body for normalized POST transport.
  } else {
    request.nextUrl.searchParams.forEach((value, key) => url.searchParams.set(key, value));
  }

  try {
    const response = await fetch(url.toString(), { method: upstreamMethod, headers, body, cache: 'no-store' });
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
