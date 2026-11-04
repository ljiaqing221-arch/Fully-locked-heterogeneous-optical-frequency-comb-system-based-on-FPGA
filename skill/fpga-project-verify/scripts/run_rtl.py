"""Run manifest-defined RTL tests in fresh build directories. Stdlib only."""
import argparse,json,math,re,shutil,subprocess,tempfile
from pathlib import Path

def has_pass_marker(output,marker):
    # Match a displayed line prefix, not loader messages or command/path text.
    for line in output.splitlines():
        line=line.lstrip()
        if line.startswith('#'): line=line[1:].lstrip()
        if line.startswith(marker): return True
    return False

def execute(command,cwd,timeout):
    try:
        p=subprocess.run(command,cwd=cwd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=timeout)
        return p.returncode,p.stdout+p.stderr
    except subprocess.TimeoutExpired as e:
        return 124,'TIMEOUT\n'+str(e.stdout or '')+str(e.stderr or '')

def run_manifest(manifest,build,sim='modelsim',tool_dir=None,timeout=60):
    if sim not in ('modelsim','iverilog'): raise ValueError('Unsupported simulator')
    if not isinstance(timeout,(int,float)) or not math.isfinite(timeout) or timeout<=0: raise ValueError('timeout must be finite and positive')
    manifest=Path(manifest).resolve(); build=Path(build).resolve()
    spec=json.loads(manifest.read_text(encoding='utf-8')); results=[]
    if not isinstance(spec,dict) or not isinstance(spec.get('tests'),list) or not spec['tests']: raise ValueError('Manifest needs a nonempty tests list')
    names=set()
    for test in spec['tests']:
        if not isinstance(test,dict): raise ValueError('Each test must be an object')
        name=test.get('name');top=test.get('top');marker=test.get('pass_marker');sources=test.get('sources')
        if not isinstance(name,str) or not name.strip() or name in names: raise ValueError('Test names must be nonempty and unique')
        if not isinstance(top,str) or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*',top): raise ValueError('Invalid top module identifier')
        if not isinstance(marker,str) or not marker.strip() or '\n' in marker or '\r' in marker: raise ValueError('pass_marker must be a nonempty single-line prefix')
        if not isinstance(sources,list) or not sources or not all(isinstance(x,str) and x.strip() for x in sources): raise ValueError('sources must be a nonempty list of paths')
        names.add(name)
    build.mkdir(parents=True,exist_ok=True)
    def tool(name):
        p=(Path(tool_dir)/(name+('.exe' if __import__('os').name=='nt' else ''))) if tool_dir else shutil.which(name)
        if not p or not Path(p).is_file(): raise FileNotFoundError(f'Executable unavailable: {name}; set PATH or --tool-dir')
        return str(p)
    executables={name:tool(name) for name in (('vlib','vlog','vsim') if sim=='modelsim' else ('iverilog','vvp'))}
    for test in spec['tests']:
        name=test['name']; top=test['top']; marker=test['pass_marker'].strip()
        if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*',top): raise ValueError('Invalid top module identifier')
        sources=[str((manifest.parent/rel).resolve()) for rel in test['sources']]
        if not sources or not all(Path(p).is_file() for p in sources): raise FileNotFoundError(f'Source missing for {name}')
        wd=Path(tempfile.mkdtemp(prefix=re.sub(r'[^A-Za-z0-9_-]','_',name)+'-',dir=build)); output=''; runtime_output=''; rc=0
        if sim=='modelsim':
            macro=wd/'run.do'; macro.write_text('onerror {quit -code 2}\nrun -all\nquit -code 0\n',encoding='utf-8')
            commands=[[executables['vlib'],'work'],[executables['vlog'],'-sv','-work','work',*sources],
                [executables['vsim'],'-c','-onfinish','stop','-l','simulation.log','work.'+top,'-do',str(macro)]]
        else:
            commands=[[executables['iverilog'],'-g2012','-s',top,'-o','test.vvp',*sources],[executables['vvp'],'test.vvp']]
        for index,command in enumerate(commands):
            rc,log=execute(command,wd,timeout); output+=log
            if index==len(commands)-1: runtime_output=log
            if rc: break
        (wd/'combined.log').write_text(output,encoding='utf-8')
        (wd/'runtime.log').write_text(runtime_output,encoding='utf-8')
        errors=bool(re.search(r'\*\*\s+(?:Fatal|Error):|FATAL:|TIMEOUT',output,re.I))
        found=has_pass_marker(runtime_output,marker)
        passed=rc==0 and found and not errors
        results.append({'name':name,'passed':passed,'exit_code':rc,'pass_marker_found':found,'log':str(wd/'combined.log'),'runtime_log':str(wd/'runtime.log')})
    result={'simulator':sim,'passed':all(t['passed'] for t in results) and bool(results),'tests':results}
    (build/'rtl_results.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    return result

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--manifest',type=Path,required=True)
    p.add_argument('--build-dir',type=Path,required=True);p.add_argument('--sim',choices=['modelsim','iverilog'],default='modelsim')
    p.add_argument('--tool-dir',type=Path);p.add_argument('--timeout',type=int,default=60)
    a=p.parse_args()
    try: result=run_manifest(a.manifest,a.build_dir,a.sim,a.tool_dir,a.timeout)
    except (FileNotFoundError,ValueError,KeyError) as e: p.exit(2,str(e)+'\n')
    print(json.dumps(result,indent=2));return 0 if result['passed'] else 1
if __name__=='__main__': raise SystemExit(main())
