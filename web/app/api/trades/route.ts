import { NextRequest, NextResponse } from 'next/server';

const gateway = process.env.NEOFL_GATEWAY_URL;
const token = process.env.NEOFL_GATEWAY_TOKEN;

export async function GET(request: NextRequest) {
  if (!gateway) {
    return NextResponse.json({ error: 'NEOFL_GATEWAY_URL is not configured' }, { status: 503 });
  }

  const limit = request.nextUrl.searchParams.get('limit') || '100';
  const headers = new Headers({ 'Content-Type': 'application/json' });
  if (token) headers.set('Authorization', `Bearer ${token}`);

  try {
    const response = await fetch(`${gateway.replace(/\/$/, '')}/execution-reports?limit=${encodeURIComponent(limit)}`, {
      headers,
      cache: 'no-store',
    });
    const text = await response.text();
    return new NextResponse(text, {
      status: response.status,
      headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
    });
  } catch {
    return NextResponse.json({ error: 'NeoFL gateway unavailable' }, { status: 502 });
  }
}
