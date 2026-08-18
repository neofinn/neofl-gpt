'use client';

import { useState } from 'react';

const brains = ['Soul','Trader Brains','Index Brain','Option Brain','FX Relationship','Data Arbitrage','Experiment Brain','Knowledge Brain','Risk Brain'];
const events = [
  ['SOUL','Cross-examination active'],
  ['INDEX','Underlying confirmation updated'],
  ['OPTION','Scanning option surface'],
  ['EXPERIMENT','Running sandbox hypothesis'],
  ['DATA','Broker/reference latency monitored'],
];

export default function Home() {
  const [message, setMessage] = useState('');
  const [messages, setMessages] = useState<string[]>(['NeoFL online. Ask me to analyze a market, inspect a brain, run an experiment, or explain a decision.']);
  const [input, setInput] = useState('');
  const send = () => { if (!input.trim()) return; setMessages([...messages, input.trim()]); setInput(''); setMessage('Request queued for NeoFL Gateway'); };
  return <main className="shell">
    <header className="topbar"><div className="brand">NeoFL <span style={{color:'#7d8999'}}>Control Room</span></div><div className="status"><i className="dot"/>HOUSE ONLINE · RESEARCH MODE</div></header>
    <section className="grid">
      <aside className="panel nav"><div className="eyebrow">House</div>{['Overview','Input / Analyze','Chat','Brains','Experiments','Learning','Risk','Execution','Memory'].map((x,i)=><button className={i===0?'active':''} key={x}>{x}</button>)}</aside>
      <section>
        <div className="panel hero"><div><div className="eyebrow">NeoFL Soul</div><div className="value">Observing the market</div><div style={{color:'#9aa6b5'}}>Specialist brains are feeding evidence into the Soul.</div></div><button className="primary">Analyze</button></div>
        <div className="cards">{[['World State','LIVE'],['Brains','9 ACTIVE'],['Experiments','3 RUNNING'],['Risk Gate','ARMED']].map(([a,b])=><div className="metric" key={a}><div className="eyebrow">{a}</div><b>{b}</b></div>)}</div>
        <div className="panel" style={{marginTop:14}}><div className="eyebrow">Brain activity</div><div className="brain-list">{brains.map((b,i)=><div className="brain" key={b}><span>{b}</span><span style={{color:i===6?'#f3c86b':'#7ee2a8'}}>{i===6?'EXPERIMENTING':'ACTIVE'}</span></div>)}</div></div>
        <div className="panel" style={{marginTop:14}}><div className="eyebrow">Input / output link</div><p style={{color:'#9aa6b5'}}>Feed structured market data, hypotheses, scenarios or analysis requests through the Gateway. Results and events will stream back into this room.</p><textarea placeholder="Paste a market input, hypothesis, strategy, option chain snapshot, or research question…" style={{width:'100%',minHeight:100,background:'#080b10',border:'1px solid #273140',borderRadius:9,color:'#fff',padding:12}}/></div>
      </section>
      <aside className="panel chat"><div className="eyebrow">Talk to NeoFL</div><div className="messages">{messages.map((m,i)=><div className={'msg '+(i?'user':'')} key={i}>{m}</div>)}</div><div className="chatbox"><input value={input} onChange={e=>setInput(e.target.value)} onKeyDown={e=>e.key==='Enter'&&send()} placeholder="Ask NeoFL…"/><button onClick={send}>Send</button></div>{message&&<div style={{fontSize:11,color:'#7d8999',marginTop:8}}>{message}</div>}<div style={{marginTop:18}} className="activity"><div className="eyebrow">Live activity</div>{events.map(([a,b])=><div className="event" key={a}><b>{a}</b><span>{b}</span></div>)}</div></aside>
    </section>
  </main>;
}
