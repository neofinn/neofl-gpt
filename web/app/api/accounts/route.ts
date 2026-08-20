import { NextRequest } from 'next/server';
import { bodyProxy } from '../_lib/body';

// Canonical account proxy: keep this route on the shared API helper path.
export async function GET(request: NextRequest) { return bodyProxy(request, '/accounts', 'GET'); }
export async function POST(request: NextRequest) { return bodyProxy(request, '/accounts', 'POST'); }
