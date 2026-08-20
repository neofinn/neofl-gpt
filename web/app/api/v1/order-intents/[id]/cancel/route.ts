import { NextRequest } from 'next/server';
import { bodyProxy } from '../../../../_lib/body';

export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return bodyProxy(request, `/order-intents/${encodeURIComponent(id)}/cancel`, 'POST');
}
