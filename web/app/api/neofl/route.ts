import { NextRequest, NextResponse } from 'next/server';

const gateway = process.env.NEOFL_GATEWAY_URL;
const token = process.env.NEOFL_GATEWAY_TOKEN;

async function proxy(path: string, init?: RequestInit) {
  if (!gateway) {
    return NextResponse.json({ error: 'NEOFL_GATEWAY_URL is not configured' }, { status: 503 });
  }
  const headers = new Headers(init?.headers);
  if (token) headers.set('Authorization', `Bearer ${token}`);
  headers.set('Content-Type', 'application/json');
  try {
    const response = await fetch(`${gateway.replace(/\/$/, '')}${path}`, { ...init, headers, cache: 'no-store' });
    const text = await response.text();
    return new NextResponse(text, { status: response.status, headers: { 'Content-Type': 'application/json' } });
  } catch {
    return NextResponse.json({ error: 'NeoFL gateway unavailable' }, { status: 502 });
  }
}

export async function GET(request: NextRequest) {
  const query = request.nextUrl.search;
  return proxy(`/state${query}`);
}

export async function POST(request: NextRequest) {
  const body = await request.text();
  return proxy('/input', { method: 'POST', body });
}
