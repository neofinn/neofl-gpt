'use client';

import { useEffect, useState } from 'react';

type Deployment = { name: string; branch: string; build: string; endpoint: string; enabled: boolean };
type Routing = { default: string; deployments: Record<string, Deployment>; accounts: Record<string, { account_id: string; deployment: string; updated_at: number }> };

type Account = { brain?: string; branch?: string; build?: string; communication?: string; mcp?: { status?: string; endpoint?: string }; equity?: number; last_heartbeat?: number };

export default function BrainRoutingAdmin() {
  const [routing, setRouting] = useState<Routing | null>(null);
  const [accounts, setAccounts] = useState<Record<string, Account>>({});
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function load() {
    try {
      const [r, s] = await Promise.all([fetch('/api/brain-routing', { cache: 'no-store' }), fetch('/api/mt5-status', { cache: 'no-store' })]);
      const rd = await r.json(); const sd = await s.json();
      if (!r.ok) throw new Error(rd.error || 'Routing unavailable');
      setRouting(rd); setAccounts(sd.accounts || {}); setError('');
    } catch (e) { setError(e instanceof Error ? e.message : 'Gateway unavailable'); }
  }

  async function route(body: Record<string, unknown>) {
    setBusy(true);
    try {
      const res = await fetch('/api/brain-routing', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Routing change failed');
      await load();
    } catch (e) { setError(e instanceof Error ? e.message : 'Routing change failed'); }
    finally { setBusy(false); }
  }

  useEffect(() => { load(); const t = window.setInterval(load, 3000); return () => window.clearInterval(t); }, []);

  const deploymentNames = routing ? Object.keys(routing.deployments) : [];
  return <main style={{minHeight:'100vh',background:'#0b1020',color:'#eef2ff',padding:24,fontFamily:'system-ui'}}>
    <div style={{maxWidth:1100,margin:'0 auto'}}>
      <div style={{display:'flex',justifyContent:'space-between',alignItems:'center'}}><div><h1 style={{margin:0}}>NeoFL Brain Router</h1><p style={{color:'#94a3b8'}}>Global deployment plus account-level overrides</p></div><span style={{border:'1px solid #334155',padding:'8px 12px',borderRadius:9}}>Gateway {routing ? 'ONLINE' : 'CONNECTING'}</span></div>
      {error && <div style={{margin:'16px 0',padding:12,border:'1px solid #7f1d1d',borderRadius:10,color:'#fda4af'}}>{error}</div>}
      <section style={{marginTop:18,padding:18,border:'1px solid #334155',borderRadius:14,background:'#111827'}}>
        <h2>System-wide Brain</h2><p style={{color:'#94a3b8'}}>Accounts without an override inherit this selection.</p>
        <div style={{display:'flex',gap:10,flexWrap:'wrap'}}>{deploymentNames.map(name => <button key={name} disabled={busy} onClick={() => route({scope:'global',brain:name})} style={{padding:'10px 16px',borderRadius:9,border:'1px solid #475569',background:routing?.default===name?'#e2e8f0':'#0f172a',color:routing?.default===name?'#0f172a':'#fff'}}>{name}<br/><small>{routing?.deployments[name].branch}</small></button>)}</div>
        <div style={{marginTop:14,fontFamily:'monospace'}}>DEFAULT: {routing?.default || '—'}</div>
      </section>
      <section style={{marginTop:18}}><h2>Account routing</h2><div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(320px,1fr))',gap:14}}>{Object.entries(accounts).map(([id,a]) => <article key={id} style={{padding:18,border:'1px solid #334155',borderRadius:14,background:'#111827'}}>
        <div style={{display:'flex',justifyContent:'space-between'}}><b>{id}</b><span style={{color:a.communication==='ONLINE'?'#6ee7b7':'#fb7185'}}>{a.communication || 'UNKNOWN'}</span></div>
        <p>Brain: <b>{a.brain || routing?.default || '—'}</b></p><p>Branch: <code>{a.branch || '—'}</code></p><p>Build: <code>{a.build || '—'}</code></p><p>MT5: {a.communication || '—'} · MCP: {a.mcp?.status || 'UNKNOWN'}</p>
        <div style={{display:'flex',gap:8,flexWrap:'wrap'}}>{deploymentNames.map(name => <button key={name} disabled={busy} onClick={() => route({scope:'account',account_id:id,brain:name})} style={{padding:'8px 12px',borderRadius:8,border:'1px solid #475569',background:a.brain===name?'#334155':'#0f172a',color:'#fff'}}>{name}</button>)}<button disabled={busy} onClick={() => route({scope:'account-global',account_id:id})} style={{padding:'8px 12px',borderRadius:8,border:'1px solid #475569',background:'#0f172a',color:'#fff'}}>Use Global</button></div>
      </article>)}</div></section>
      <section style={{marginTop:18,padding:18,border:'1px solid #334155',borderRadius:14,background:'#111827'}}><h2>Routing rule</h2><p style={{color:'#94a3b8',lineHeight:1.6}}>GLOBAL applies to every account by default. An ACCOUNT override takes precedence. “Use Global” removes the account override. MT5 never selects a branch; the gateway resolves the Brain and reports the resolved branch/build on telemetry and execution events.</p></section>
    </div>
  </main>;
}
