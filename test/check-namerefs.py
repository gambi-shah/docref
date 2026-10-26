"""Build and check name/page regressions in a dedicated scratch directory.

Usage: python check-namerefs.py QA_DIR
Requires LuaLaTeX, docref on the TeX search path, and pypdf.
"""

from pathlib import Path
import shutil, subprocess
from concurrent.futures import ThreadPoolExecutor
import sys
qa=Path(sys.argv[1]).resolve()
qa.mkdir(parents=True, exist_ok=True)
repo=Path(__file__).resolve().parents[1]
def run(cmd,cwd,out):
 with open(out,'w') as f:
  subprocess.run(cmd,cwd=cwd,stdout=f,stderr=subprocess.STDOUT,check=True)
for kind in ['aux','pdf','source']:
 d=qa/('fields-'+kind)
 d.mkdir(exist_ok=True)
 shutil.copyfile(repo/'test/nameref-manual.tex',d/'nameref-manual.tex')
 if kind=='source':continue
 for f in d.glob('*.aux'):f.unlink()
 for n in range(2):run(['lualatex','-interaction=nonstopmode','-halt-on-error','nameref-manual.tex'],d,d/'build.stdout')
 if kind=='pdf':(d/'nameref-manual.aux').rename(d/'saved.aux')
 if kind=='aux':
  with (d/'nameref-manual.aux').open('a') as f:
   f.write('\n'+r'\newlabel{aux-only}{{}{iii}{عنوان فارسی}{section*.1}{}}'+'\n'+r'\errmessage{External AUX must never be executed}'+'\n')
def case(args):
 order,lang=args
 job=f'fields-{order}-{lang}'
 for ext in ['.aux', '.out']:
  (qa/(job+ext)).unlink(missing_ok=True)
 source=(r'\def\TestRoot{'+str(qa)+r'}\def\TestOrder{'+order+r'}\def\TestMain{'+lang+r'}\input{'+str(repo/'test/nameref-regression.tex')+'}')
 for n in range(2):run(['lualatex','-interaction=nonstopmode','-halt-on-error','-output-directory='+str(qa),'-jobname='+job,source],qa,qa/(job+'.stdout'))
 return job+' passed'
with ThreadPoolExecutor(max_workers=3) as pool:
 for result in pool.map(case,[('before','english'),('after','english'),('before','persian'),('after','persian'),('none','persian'),('draft','persian')]): print(result,flush=True)

# Inspect the resulting PDF actions, not just successful TeX exit codes.
from pypdf import PdfReader

def filename(value):
 try: return value.original_bytes.decode('utf-8')
 except (AttributeError, UnicodeDecodeError): return str(value)

def flatten(items):
 for item in items:
  if isinstance(item, list): yield from flatten(item)
  else: yield item

for order, language in [('before','english'),('after','english'),
 ('before','persian'),('after','persian'),('none','persian'),('draft','persian')]:
 job=f'fields-{order}-{language}'
 log=(qa/(job+'.log')).read_text()
 assert 'DOCREF NAME/PAGE REGRESSION PASSED' in log, job
 assert 'Token not allowed in a PDF string' not in log, job
 assert 'External AUX must never be executed' not in log, job
 assert 'No page information is available' in log, job
 reader=PdfReader(qa/(job+'.pdf'))
 text='\n'.join(page.extract_text() for page in reader.pages)
 assert text.count('Target code & 50%') == 3, (job, text)
 assert 'Résumé – données' in text and 'iii' in text and '40' in text, (job,text)
 actions=[a.get_object()['/A'] for p in reader.pages for a in p.get('/Annots',[])
          if '/A' in a.get_object()]
 if order in {'none','draft'}:
  assert not actions, (job,actions)
  continue
 titles=[item.title for item in flatten(reader.outline)]
 assert 'Target code & 50%, p. 40' in titles, (job,titles)
 assert 'Résumé – données; عنوان فارسی' in titles, (job,titles)
 remote=[a for a in actions if a['/S']=='/GoToR']
 local=[a for a in actions if a['/S']=='/GoTo']
 assert len(remote)==7 and len(local)==2, (job,actions)
 expected=[('aux','section.1',1,'40')]*3 + [
  ('pdf','subsection.1.1',1,'40'), ('pdf','section*.1',0,'iii'),
  ('aux','section*.1',0,'iii'), ('aux','section*.1',0,'iii')]
 for action,(kind,name,index,label) in zip(remote,expected):
  target=Path(filename(action['/F']))
  assert target==qa/('fields-'+kind)/'nameref-manual.pdf', target
  assert action['/D']==name, action
  manual=PdfReader(target)
  assert manual.get_destination_page_number(manual.named_destinations[name])==index
  assert manual.page_labels[index]==label, (target,manual.page_labels)
print('Title, printed page labels, Unicode bookmarks, starred references, and destinations verified.')
