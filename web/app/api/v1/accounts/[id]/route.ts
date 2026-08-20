import { NextRequest } from 'next/server';
import { bodyProxy } from '../../../_lib/body';

export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return bodyProxy(request, `/accounts/${encodeURIComponent(id)}`, 'GET');
}
