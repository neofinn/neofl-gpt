import { NextRequest } from 'next/server';
import { bodyProxy } from '../../../_lib/body';

export async function GET(request: NextRequest) { return bodyProxy(request, '/execution/next', 'GET'); }
