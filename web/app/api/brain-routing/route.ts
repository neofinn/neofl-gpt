import { NextRequest, NextResponse } from 'next/server';

const gateway = process.env.NEOFL_GATEWAY_URL;
const token = process.env.NEOFL_GATEWAY_TOKEN;

async function proxy(path: string, init?: RequestInit) {
  if (!gateway) return NextResponse.json({ error: 'NEOFL_GATEWAY_URL is not configured' }, { status: 503 });
  const headers = new Headers(init?.headers);
  if (token) headers.set('Authorization', `Bearer ${token}`);
  headers.set('Content-Type', 'application/json');
  try {
    const response = await fetch(`${gateway.replace(/\/$/, '')}${path}`, { ...init, headers, cache: 'no-store' });
    const text = await response.text();
    return new NextResponse(text, { status: response.status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
  } catch {
    return NextResponse.json({ error: 'NeoFL gateway unavailable' }, { status: 502 });
  }
}

export async function GET() { return proxy('/admin/brain-routing'); }

export async function POST(request: NextRequest) {
  const body = await request.text();
  const parsed = JSON.parse(body || '{}');
  const scope = parsed.scope || 'account';
  if (scope === 'global') return proxy('/admin/brain/global-switch', { method: 'POST', body });
  if (scope === 'account-global') return proxy('/admin/brain/use-global', { method: 'POST', body });
  return proxy('/admin/brain/switch', { method: 'POST', body });
}
