import { NextRequest } from 'next/server';
import { bodyProxy } from '../../_lib/body';

export async function POST(request: NextRequest) { return bodyProxy(request, '/execution-report', 'POST'); }
export async function GET(request: NextRequest) { return bodyProxy(request, '/execution-report', 'GET'); }
