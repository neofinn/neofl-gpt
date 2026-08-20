import { NextRequest, NextResponse } from 'next/server';

const gateway = process.env.NEOFL_GATEWAY_URL;
const gatewayToken = process.env.NEOFL_GATEWAY_TOKEN;

export async function bodyProxy(request: NextRequest, upstreamPath: string, method: 'GET' | 'POST' = request.method as 'GET' | 'POST') {
  if (!gateway) return NextResponse.json({ error: 'NEOFL_GATEWAY_URL is not configured' }, { status: 503 });

  const binding = request.headers.get('x-neofl-binding-token') || '';
  if (!binding) return NextResponse.json({ error: 'Binding token required' }, { status: 401 });

  const headers = new Headers();
  headers.set('Content-Type', request.headers.get('content-type') || 'application/json');
  headers.set('X-NeoFL-Binding-Token', binding);
  if (gatewayToken) headers.set('Authorization', `Bearer ${gatewayToken}`);

  const url = new URL(`${gateway.replace(/\/$/, '')}${upstreamPath}`);
  request.nextUrl.searchParams.forEach((value, key) => url.searchParams.set(key, value));

  let body: string | undefined;
  if (method !== 'GET') body = await request.text();

  try {
    const response = await fetch(url.toString(), {
      method,
      headers,
      body,
      cache: 'no-store',
    });
    const text = await response.text();
    return new NextResponse(text, {
      status: response.status,
      headers: { 'Content-Type': response.headers.get('content-type') || 'application/json', 'Cache-Control': 'no-store' },
    });
  } catch {
    return NextResponse.json({ error: 'NeoFL gateway unavailable' }, { status: 502 });
  }
}
