from __future__ import annotations
import json, os, sqlite3, threading, time
from pathlib import Path
import tkinter as tk
from tkinter import ttk, scrolledtext, filedialog, messagebox

from neofl_gateway.local_brain import LocalBrain, LocalBrainError

APP=Path(os.getenv('APPDATA','.') )/'NeoFLGPTParallel'
APP.mkdir(parents=True, exist_ok=True)
CFG=APP/'config.json'; DB=APP/'memory.db'
DEFAULT={'backend':'ollama','model':'neoflgpt-parallel','ollama_url':'http://127.0.0.1:11434','gguf_path':''}
if not CFG.exists(): CFG.write_text(json.dumps(DEFAULT,indent=2))

def cfg():
    try:return {**DEFAULT,**json.loads(CFG.read_text())}
    except Exception:return DEFAULT.copy()

def db_init():
    c=sqlite3.connect(DB);c.execute('CREATE TABLE IF NOT EXISTS memory(ts REAL, role TEXT, text TEXT)');c.commit();c.close()
def save(role,text):
    db_init();c=sqlite3.connect(DB);c.execute('INSERT INTO memory VALUES(?,?,?)',(time.time(),role,text));c.commit();c.close()
def load_memory():
    db_init();c=sqlite3.connect(DB);r=c.execute('SELECT role,text FROM memory ORDER BY ts DESC LIMIT 50').fetchall();c.close();return r

SYSTEM='''You are NeoFLGPT Parallel, the local NeoFL agentic Brain. Observe evidence, reason, plan, challenge assumptions, re-plan when evidence is missing, use memory, and clearly distinguish facts from inference. Never invent live market/account data. Coding and tool use must be explicit. Broker execution remains behind authenticated execution controls.'''

class App(tk.Tk):
    def __init__(self):
        super().__init__();self.title('NeoFLGPT Parallel');self.geometry('1100x760');self.minsize(850,600)
        self.brain=LocalBrain(**{k:v for k,v in cfg().items() if k in {'backend','model','ollama_url','gguf_path'}})
        self.messages=[{'role':'system','content':SYSTEM}]
        self._ui();self.refresh_status()
    def _ui(self):
        top=ttk.Frame(self,padding=10);top.pack(fill='x')
        ttk.Label(top,text='NeoFLGPT Parallel',font=('Segoe UI',18,'bold')).pack(side='left')
        self.status=ttk.Label(top,text='Checking local Brain…');self.status.pack(side='right')
        self.chat=scrolledtext.ScrolledText(self,wrap=tk.WORD,font=('Segoe UI',11),state='disabled');self.chat.pack(fill='both',expand=True,padx=10,pady=(0,8))
        bottom=ttk.Frame(self,padding=10);bottom.pack(fill='x')
        self.entry=ttk.Entry(bottom);self.entry.pack(side='left',fill='x',expand=True);self.entry.bind('<Return>',lambda e:self.send())
        ttk.Button(bottom,text='Send',command=self.send).pack(side='left',padx=(8,0))
        ttk.Button(bottom,text='Brain Settings',command=self.settings).pack(side='left',padx=(8,0))
        self.write('SYSTEM', 'NeoFLGPT Parallel desktop agent started. Local model status is shown above.')
    def write(self,who,text):
        self.chat.configure(state='normal');self.chat.insert('end',f'{who}: {text}\n\n');self.chat.see('end');self.chat.configure(state='disabled')
    def refresh_status(self):
        def f():
            s=self.brain.status();ok=s.get('online') and s.get('model_installed')
            label=('LOCAL BRAIN READY' if ok else 'LOCAL MODEL NOT READY')+' • '+str(s.get('model',''))
            self.after(0,lambda:self.status.config(text=label))
        threading.Thread(target=f,daemon=True).start()
    def send(self):
        q=self.entry.get().strip()
        if not q:return
        self.entry.delete(0,'end');self.write('YOU',q);save('user',q);self.messages.append({'role':'user','content':q})
        self.entry.config(state='disabled')
        def f():
            try:
                mem='\n'.join(f'{r}: {t}' for r,t in load_memory()[-20:])
                msgs=[{'role':'system','content':SYSTEM+'\nLocal memory:\n'+mem}]+self.messages[-20:]
                ans=self.brain.chat(msgs)
            except Exception as e: ans='LOCAL BRAIN ERROR: '+str(e)
            save('assistant',ans);self.messages.append({'role':'assistant','content':ans})
            self.after(0,lambda:(self.write('NEOFLGPT PARALLEL',ans),self.entry.config(state='normal'),self.entry.focus_set(),self.refresh_status()))
        threading.Thread(target=f,daemon=True).start()
    def settings(self):
        w=tk.Toplevel(self);w.title('Local Brain Settings');w.transient(self)
        c=cfg(); fields={}
        for i,(k,label) in enumerate([('backend','Backend'),('model','Model'),('ollama_url','Local Ollama URL'),('gguf_path','GGUF Model Path')]):
            ttk.Label(w,text=label).grid(row=i,column=0,padx=10,pady=8,sticky='w');e=ttk.Entry(w,width=55);e.insert(0,c[k]);e.grid(row=i,column=1,padx=10,pady=8);fields[k]=e
        def apply():
            n={k:e.get().strip() for k,e in fields.items()};CFG.write_text(json.dumps(n,indent=2));self.brain=LocalBrain(**n);self.refresh_status();w.destroy()
        ttk.Button(w,text='Save',command=apply).grid(row=5,column=1,pady=12,sticky='e')

if __name__=='__main__':
    db_init();App().mainloop()
