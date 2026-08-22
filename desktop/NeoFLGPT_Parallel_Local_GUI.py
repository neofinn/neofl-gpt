import json, os, sqlite3, threading, time
from pathlib import Path
import tkinter as tk
from tkinter import scrolledtext
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'python'))
from neofl_gateway.local_brain import LocalBrain, LocalBrainError
APP=Path(os.getenv('APPDATA','.'))/'NeoFLGPTParallel'; APP.mkdir(parents=True,exist_ok=True)
DB=APP/'memory.db'
SYSTEM='''You are NeoFLGPT Parallel, the local NeoFL agentic Brain. Use evidence, plan, investigate, reason, challenge, re-plan, remember and decide. Never invent live market data. Coding and tools are available when configured. Broker execution remains behind the authenticated execution fabric.'''
def mem_setup():
 c=sqlite3.connect(DB); c.execute('CREATE TABLE IF NOT EXISTS memory(ts REAL,role TEXT,text TEXT)'); c.commit(); c.close()
def remember(role,text):
 mem_setup(); c=sqlite3.connect(DB); c.execute('INSERT INTO memory VALUES(?,?,?)',(time.time(),role,text)); c.commit(); c.close()
def memories():
 mem_setup(); c=sqlite3.connect(DB); r=c.execute('SELECT role,text FROM memory ORDER BY ts DESC LIMIT 40').fetchall(); c.close(); return r
class App:
 def __init__(self):
  self.brain=LocalBrain(); self.messages=[{'role':'system','content':SYSTEM}]
  self.w=tk.Tk(); self.w.title('NeoFLGPT Parallel — Local Brain'); self.w.geometry('1000x720')
  self.status=tk.Label(self.w,text=self.status_text(),anchor='w'); self.status.pack(fill='x',padx=10,pady=8)
  self.out=scrolledtext.ScrolledText(self.w,wrap=tk.WORD,font=('Segoe UI',11)); self.out.pack(fill='both',expand=True,padx=10)
  row=tk.Frame(self.w); row.pack(fill='x',padx=10,pady=10)
  self.entry=tk.Entry(row,font=('Segoe UI',12)); self.entry.pack(side='left',fill='x',expand=True); self.entry.bind('<Return>',lambda e:self.send())
  tk.Button(row,text='Send',command=self.send,width=12).pack(side='right',padx=(8,0))
  self.out.insert('end','NeoFLGPT Parallel local chat\n\n')
  self.w.after(5000,self.refresh)
 def status_text(self):
  s=self.brain.status(); return f"BRAIN: NeoFLGPT Parallel | MODE: LOCAL | MODEL: {s.get('model')} | INSTALLED: {s.get('model_installed',False)} | BACKEND: {s.get('backend')}"
 def refresh(self): self.status.config(text=self.status_text()); self.w.after(5000,self.refresh)
 def send(self):
  q=self.entry.get().strip(); self.entry.delete(0,'end')
  if not q:return
  self.out.insert('end',f'YOU: {q}\n'); self.out.see('end')
  self.messages.append({'role':'user','content':q}); remember('user',q)
  self.messages[0]['content']=SYSTEM+'\nPrior local memory:\n'+json.dumps(memories()[-20:])
  def run():
   try:a=self.brain.chat(self.messages)
   except LocalBrainError as e:a='LOCAL BRAIN ERROR: '+str(e)
   self.messages.append({'role':'assistant','content':a}); remember('assistant',a)
   self.w.after(0,lambda:(self.out.insert('end',f'NeoFLGPT PARALLEL: {a}\n\n'),self.out.see('end')))
  threading.Thread(target=run,daemon=True).start()
 def run(self): self.w.mainloop()
if __name__=='__main__': App().run()
