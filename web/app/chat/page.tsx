'use client';

import { useState } from 'react';

export default function ChatPage() {
  const [input, setInput] = useState('');
  const [busy, setBusy] = useState(false);
  const [messages, setMessages] = useState<{role:'user'|'neo',text:string}[]>([
    { role: 'neo', text: 'NeoFL Main Chat Room is online. Ask a market question, research task, hypothesis, or strategy question.' },
  ]);

  async function send() {
    const text = input.trim();
    if (!text || busy) return;
    setInput('');
    setMessages(m => [...m, { role: 'user', text }]);
    setBusy(true);
    try {
      const res = await fetch('/api/neofl', { method: 'POST', body: JSON.stringify({ text, mode: 'analyze' }) });
      const data = await res.json();
      setMessages(m => [...m, { role: 'neo', text: data.answer || data.reasoning_state || data.error || 'NeoFL returned no response.' }]);
    } catch {
      setMessages(m => [...m, { role: 'neo', text: 'NeoFL gateway is unavailable.' }]);
    } finally {
      setBusy(false);
    }
  }

  return <main className="shell">
    <header className="topbar">
      <div className="brand">NeoFL <span style={{color:'#7d8999'}}>Main Chat Room</span></div>
      <a href="/" style={{color:'#9aa6b5',textDecoration:'none'}}>← Control Room</a>
    </header>
    <section className="panel" style={{maxWidth:1100,margin:'18px auto 0',minHeight:'calc(100vh - 120px)',display:'flex',flexDirection:'column'}}>
      <div className="eyebrow">Soul · Agentic Interface</div>
      <h1 style={{margin:'8px 0 4px'}}>Talk to NeoFL</h1>
      <p style={{color:'#7d8999',marginTop:0}}>The full conversation room is restored. NeoFL routes each request through the Agentic Soul loop and remains execution-gated.</p>
      <div style={{flex:1,overflowY:'auto',display:'grid',alignContent:'start',gap:12,padding:'20px 0'}}>
        {messages.map((m,i) => <div key={i} style={{maxWidth:'82%',justifySelf:m.role==='user'?'end':'start',background:m.role==='user'?'#17241f':'#131923',border:'1px solid #1d2530',borderRadius:12,padding:'12px 14px',lineHeight:1.5}}>{m.text}</div>)}
      </div>
      <div style={{display:'flex',gap:10,borderTop:'1px solid #1d2530',paddingTop:14}}>
        <textarea value={input} onChange={e=>setInput(e.target.value)} onKeyDown={e=>{if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();send();}}} placeholder="Ask NeoFL anything…" disabled={busy} style={{flex:1,minHeight:64,resize:'vertical',background:'#080b10',border:'1px solid #273140',borderRadius:10,color:'#fff',padding:12}} />
        <button className="primary" onClick={send} disabled={busy||!input.trim()}>{busy?'Thinking…':'Send'}</button>
      </div>
    </section>
  </main>;
}
