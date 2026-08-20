import { NextRequest, NextResponse } from 'next/server';

// NeoFL Body always targets the existing execution gateway. The MT5 binding token
// remains the only user-supplied credential; no gateway URL is required in MT5.
const gateway = 'https://neofl-execution-gateway-1li631.v2.appdeploy.ai';

export async function bodyProxy(request: NextRequest, upstreamPath: string, method: 'GET' | 'POST' = request.method as 'GET' | 'POST') {
  const binding = request.headers.get('x-neofl-binding-token')?.trim() || '';
  if (!binding) return NextResponse.json({ error: 'Binding token required' }, { status: 401 });

  const headers = new Headers();
  headers.set('Content-Type', request.headers.get('content-type') || 'application/json');
  headers.set('X-NeoFL-Binding-Token', binding);

  const url = new URL(`${gateway}${upstreamPath}`);
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
