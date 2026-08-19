'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';

const brains = ['Soul','Trader Brains','Index Brain','Option Brain','FX Relationship','Data Arbitrage','Experiment Brain','Knowledge Brain','Risk Brain'];
const events = [
  ['SOUL','Cross-examination active'],
  ['INDEX','Underlying confirmation updated'],
  ['OPTION','Scanning option surface'],
  ['EXPERIMENT','Running sandbox hypothesis'],
  ['DATA','Broker/reference latency monitored'],
];

type AgentResponse = { answer?: string; status?: string; routed_brains?: string[]; reasoning_state?: string; safety?: { execution_authorized?: boolean } };
type Trade = {
  id: string;
  timestamp: string;
  account_number: string;
  broker?: string;
  environment?: string;
  adapter?: string;
  status: string;
  bucket: 'RUNNING' | 'CLOSED' | 'REJECTED';
  intent_id?: string;
  trade: { strategy?: string; symbol?: string; direction?: string; order_type?: string; quantity?: number; entry?: number; stop?: number; target?: number; time_in_force?: string; thesis_id?: string };
  filled_quantity?: number;
  average_fill_price?: number;
  broker_order_id?: string;
  unrealized_pnl?: number | null;
  realized_pnl?: number | null;
  rejection_code?: string;
  rejection_reason?: string;
};

function money(value: number | null | undefined) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) return '—';
  return Number(value).toFixed(2);
}

function timeLabel(value: string) {
  if (!value) return '—';
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? value : d.toLocaleString();
}

function TradeCard({ trade }: { trade: Trade }) {
  const t = trade.trade || {};
  const pnl = trade.bucket === 'RUNNING' ? trade.unrealized_pnl : trade.realized_pnl;
  return <div className="trade-card">
    <div className="trade-top">
      <div>
        <div className="trade-status">{trade.bucket} · {trade.status}</div>
        <div className="trade-title">{t.symbol || 'UNKNOWN SYMBOL'} <span>{t.direction || '—'}</span></div>
      </div>
      <div className="trade-pnl"><small>{trade.bucket === 'RUNNING' ? 'UNREALISED PNL' : 'REALISED PNL'}</small><strong>{money(pnl)}</strong></div>
    </div>
    <div className="trade-grid">
      <div><small>ACCOUNT</small><b>{trade.account_number}</b></div>
      <div><small>STRATEGY</small><b>{t.strategy || '—'}</b></div>
      <div><small>QUANTITY</small><b>{t.quantity ?? trade.filled_quantity ?? '—'}</b></div>
      <div><small>ORDER</small><b>{t.order_type || 'MARKET'}</b></div>
      <div><small>ENTRY</small><b>{t.entry ?? '—'}</b></div>
      <div><small>STOP</small><b>{t.stop ?? '—'}</b></div>
      <div><small>TARGET</small><b>{t.target ?? '—'}</b></div>
      <div><small>FILL</small><b>{trade.average_fill_price ?? '—'}</b></div>
    </div>
    <div className="trade-meta">{trade.broker || 'MT5'} · {trade.environment || '—'} · {timeLabel(trade.timestamp)}{trade.broker_order_id ? ` · Ticket ${trade.broker_order_id}` : ''}</div>
    {trade.bucket === 'REJECTED' && <div className="reject-reason"><b>REJECTION REASON</b><span>{trade.rejection_reason || trade.rejection_code || 'Unknown rejection reason'}</span></div>}
  </div>;
}

export default function Home() {
  const [message, setMessage] = useState('');
  const [messages, setMessages] = useState<string[]>(['NeoFL Control Room connected.']);
  const [input, setInput] = useState('');
  const [analysisInput, setAnalysisInput] = useState('');
  const [lastResponse, setLastResponse] = useState<AgentResponse | null>(null);
  const [busy, setBusy] = useState(false);
  const [trades, setTrades] = useState<Trade[]>([]);
  const [tradeTab, setTradeTab] = useState<'RUNNING' | 'CLOSED' | 'REJECTED'>('RUNNING');
  const [tradeError, setTradeError] = useState('');

  const loadTrades = useCallback(async () => {
    try {
      const res = await fetch('/api/trades?limit=100', { cache: 'no-store' });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Unable to load trade reports');
      setTrades(Array.isArray(data) ? data : []);
      setTradeError('');
    } catch (err) {
      setTradeError(err instanceof Error ? err.message : 'Unable to load trade reports');
    }
  }, []);

  const send = async (text = input) => {
    const value = text.trim();
    if (!value || busy) return;
    setBusy(true);
    setInput('');
    setMessages(prev => [...prev, value]);
    try {
      const res = await fetch('/api/neofl', { method: 'POST', body: JSON.stringify({ text: value, mode: 'analyze' }) });
      const data: AgentResponse = await res.json();
      setLastResponse(data);
      setMessages(prev => [...prev, data.answer || data.reasoning_state || 'NeoFL returned no answer.']);
      setMessage(data.status === 'accepted' ? `Routed: ${(data.routed_brains || []).join(', ')}` : 'Gateway returned an error');
    } catch {
      setMessages(prev => [...prev, 'NeoFL gateway is unavailable.']);
      setMessage('Gateway unavailable');
    } finally {
      setBusy(false);
    }
  };

  useEffect(() => {
    fetch('/api/neofl').catch(() => undefined);
    loadTrades();
    const timer = window.setInterval(loadTrades, 5000);
    return () => window.clearInterval(timer);
  }, [loadTrades]);

  const visibleTrades = useMemo(() => trades.filter(t => t.bucket === tradeTab), [trades, tradeTab]);
  const counts = useMemo(() => ({
    RUNNING: trades.filter(t => t.bucket === 'RUNNING').length,
    CLOSED: trades.filter(t => t.bucket === 'CLOSED').length,
    REJECTED: trades.filter(t => t.bucket === 'REJECTED').length,
  }), [trades]);

  return <main className="shell">
    <header className="topbar"><div className="brand">NeoFL <span style={{color:'#7d8999'}}>Control Room</span></div><div className="status"><i className="dot"/>HOUSE ONLINE · EXECUTION OBSERVER</div></header>
    <section className="grid">
      <aside className="panel nav"><div className="eyebrow">House</div>{['Overview','Input / Analyze','Chat','Brains','Experiments','Learning','Risk','Execution','Memory'].map((x,i)=><button className={i===0?'active':''} key={x}>{x}</button>)}</aside>
      <section>
        <div className="panel hero"><div><div className="eyebrow">NeoFL Soul</div><div className="value">{busy ? 'Thinking…' : 'Ready to reason'}</div><div style={{color:'#9aa6b5'}}>Control Room input routes into the Python agent loop. Execution remains separately gated by the MT5 body.</div></div><button className="primary" onClick={() => send(analysisInput)} disabled={!analysisInput.trim() || busy}>{busy ? 'Working…' : 'Analyze'}</button></div>

        <div className="panel reports" style={{marginTop:14}}>
          <div className="reports-head"><div><div className="eyebrow">Execution</div><h2>Executed trade reports</h2><p>Every signal keeps its account, exact trade data, outcome and rejection reason.</p></div><button className="refresh" onClick={loadTrades}>Refresh</button></div>
          <div className="trade-tabs">{(['RUNNING','CLOSED','REJECTED'] as const).map(tab => <button key={tab} className={tradeTab===tab?'selected':''} onClick={() => setTradeTab(tab)}>{tab} <span>{counts[tab]}</span></button>)}</div>
          {tradeError && <div className="error-box">{tradeError}</div>}
          {!tradeError && visibleTrades.length === 0 && <div className="empty">No {tradeTab.toLowerCase()} trades.</div>}
          <div className="trade-list">{visibleTrades.map(trade => <TradeCard trade={trade} key={trade.id} />)}</div>
        </div>

        <div className="cards">{[['World State','LIVE'],['Brains','9 ACTIVE'],['Experiments','SANDBOX'],['Risk Gate','ARMED']].map(([a,b])=><div className="metric" key={a}><div className="eyebrow">{a}</div><b>{b}</b></div>)}</div>
        <div className="panel" style={{marginTop:14}}><div className="eyebrow">Brain activity</div><div className="brain-list">{brains.map((b,i)=><div className="brain" key={b}><span>{b}</span><span style={{color:i===6?'#f3c86b':'#7ee2a8'}}>{i===6?'SANDBOX':'ACTIVE'}</span></div>)}</div></div>
        <div className="panel" style={{marginTop:14}}><div className="eyebrow">Input / output link</div><p style={{color:'#9aa6b5'}}>Feed a hypothesis, market question, scenario or trade idea. NeoFL will route it through the first Soul-facing agent loop.</p><textarea value={analysisInput} onChange={e=>setAnalysisInput(e.target.value)} placeholder="e.g. Analyze NAS100: index chart is bullish but underlying leaders are weakening…" style={{width:'100%',minHeight:110,background:'#080b10',border:'1px solid #273140',borderRadius:9,color:'#fff',padding:12}}/>{lastResponse&&<div style={{marginTop:12,color:'#9aa6b5',fontSize:12}}>State: {lastResponse.reasoning_state || '—'} · Execution authorized: {String(lastResponse.safety?.execution_authorized ?? false)}</div>}</div>
      </section>
      <aside className="panel chat"><div className="eyebrow">Talk to NeoFL</div><div className="messages">{messages.map((m,i)=><div className={'msg '+(i%2?'user':'')} key={`${m}-${i}`}>{m}</div>)}</div><div className="chatbox"><input value={input} onChange={e=>setInput(e.target.value)} onKeyDown={e=>e.key==='Enter'&&send()} placeholder="Ask NeoFL…" disabled={busy}/><button onClick={() => send()} disabled={busy}>Send</button></div>{message&&<div style={{fontSize:11,color:'#7d8999',marginTop:8}}>{message}</div>}<div style={{marginTop:18}} className="activity"><div className="eyebrow">Live activity</div>{events.map(([a,b])=><div className="event" key={a}><b>{a}</b><span>{b}</span></div>)}</div></aside>
    </section>
  </main>;
}
