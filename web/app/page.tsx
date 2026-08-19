'use client';

import { useEffect, useState } from 'react';

const brains = ['Soul','Trader Brains','Index Brain','Option Brain','FX Relationship','Data Arbitrage','Experiment Brain','Knowledge Brain','Risk Brain'];
const events = [
  ['SOUL','Cross-examination active'],
  ['INDEX','Underlying confirmation updated'],
  ['OPTION','Scanning option surface'],
  ['EXPERIMENT','Running sandbox hypothesis'],
  ['DATA','Broker/reference latency monitored'],
];

type AgentResponse = { answer?: string; status?: string; routed_brains?: string[]; reasoning_state?: string; safety?: { execution_authorized?: boolean } };

export default function Home() {
  const [message, setMessage] = useState('');
  const [messages, setMessages] = useState<string[]>(['NeoFL Control Room connected.']);
  const [input, setInput] = useState('');
  const [analysisInput, setAnalysisInput] = useState('');
  const [lastResponse, setLastResponse] = useState<AgentResponse | null>(null);
  const [busy, setBusy] = useState(false);

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

  useEffect(() => { fetch('/api/neofl').catch(() => undefined); }, []);

  return <main className="shell">
    <header className="topbar"><div className="brand">NeoFL <span style={{color:'#7d8999'}}>Control Room</span></div><div className="status"><i className="dot"/>HOUSE ONLINE · ANALYSIS MODE</div></header>
    <section className="grid">
      <aside className="panel nav"><div className="eyebrow">House</div>{['Overview','Input / Analyze','Chat','Brains','Experiments','Learning','Risk','Execution','Memory'].map((x,i)=><button className={i===0?'active':''} key={x}>{x}</button>)}</aside>
      <section>
        <div className="panel hero"><div><div className="eyebrow">NeoFL Soul</div><div className="value">{busy ? 'Thinking…' : 'Ready to reason'}</div><div style={{color:'#9aa6b5'}}>Control Room input now routes into the Python agent loop. Execution remains disabled.</div></div><button className="primary" onClick={() => send(analysisInput)} disabled={!analysisInput.trim() || busy}>{busy ? 'Working…' : 'Analyze'}</button></div>
        <div className="cards">{[['World State','LIVE'],['Brains','9 ACTIVE'],['Experiments','SANDBOX'],['Risk Gate','ARMED']].map(([a,b])=><div className="metric" key={a}><div className="eyebrow">{a}</div><b>{b}</b></div>)}</div>
        <div className="panel" style={{marginTop:14}}><div className="eyebrow">Brain activity</div><div className="brain-list">{brains.map((b,i)=><div className="brain" key={b}><span>{b}</span><span style={{color:i===6?'#f3c86b':'#7ee2a8'}}>{i===6?'SANDBOX':'ACTIVE'}</span></div>)}</div></div>
        <div className="panel" style={{marginTop:14}}><div className="eyebrow">Input / output link</div><p style={{color:'#9aa6b5'}}>Feed a hypothesis, market question, scenario or trade idea. NeoFL will route it through the first Soul-facing agent loop.</p><textarea value={analysisInput} onChange={e=>setAnalysisInput(e.target.value)} placeholder="e.g. Analyze NAS100: index chart is bullish but underlying leaders are weakening…" style={{width:'100%',minHeight:110,background:'#080b10',border:'1px solid #273140',borderRadius:9,color:'#fff',padding:12}}/>{lastResponse&&<div style={{marginTop:12,color:'#9aa6b5',fontSize:12}}>State: {lastResponse.reasoning_state || '—'} · Execution authorized: {String(lastResponse.safety?.execution_authorized ?? false)}</div>}</div>
      </section>
      <aside className="panel chat"><div className="eyebrow">Talk to NeoFL</div><div className="messages">{messages.map((m,i)=><div className={'msg '+(i%2?'user':'')} key={`${m}-${i}`}>{m}</div>)}</div><div className="chatbox"><input value={input} onChange={e=>setInput(e.target.value)} onKeyDown={e=>e.key==='Enter'&&send()} placeholder="Ask NeoFL…" disabled={busy}/><button onClick={() => send()} disabled={busy}>Send</button></div>{message&&<div style={{fontSize:11,color:'#7d8999',marginTop:8}}>{message}</div>}<div style={{marginTop:18}} className="activity"><div className="eyebrow">Live activity</div>{events.map(([a,b])=><div className="event" key={a}><b>{a}</b><span>{b}</span></div>)}</div></aside>
    </section>
  </main>;
}
