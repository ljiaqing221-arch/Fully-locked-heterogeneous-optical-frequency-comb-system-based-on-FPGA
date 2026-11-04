"""Audit a simple named-port ILA instance against XML or JSON XCI."""
import argparse,json,math,re,xml.etree.ElementTree as ET
from pathlib import Path

KEY=re.compile(r'C_(?:NUM_OF_PROBES|DATA_DEPTH|PROBE\d+_WIDTH)$')
def xci_parameters(path):
    text=Path(path).read_text(encoding='utf-8-sig'); result={}
    def scalar(v):
        if isinstance(v,list): return scalar(v[0])
        if isinstance(v,dict): return scalar(v.get('value'))
        return int(v)
    def accept(key,value):
        number=scalar(value)
        if number<1: raise ValueError(f'{key} must be positive')
        if key in result and result[key]!=number: raise ValueError(f'Conflicting XCI values for {key}')
        result[key]=number
    def walk(o):
        if isinstance(o,dict):
            for k,v in o.items():
                if KEY.fullmatch(k): accept(k,v)
                else: walk(v)
        elif isinstance(o,list):
            for v in o: walk(v)
    if text.lstrip().startswith('{'): walk(json.loads(text))
    else:
        for el in ET.fromstring(text).iter():
            for value in el.attrib.values():
                key=value.split('.')[-1]
                if KEY.fullmatch(key) and el.text: accept(key,el.text.strip())
    return result

def audit(rtl,xci,core,clock_hz,stride=1):
    if not math.isfinite(clock_hz) or clock_hz<=0 or type(stride) is not int or stride<1: raise ValueError('Finite clock_hz > 0 and integer stride >= 1 required')
    rtl=re.sub(r'/\*.*?\*/|//[^\n]*','',rtl,flags=re.S)
    instances=list(re.finditer(r'\b'+re.escape(core)+r'\s+(\w+)\s*\((.*?)\);',rtl,flags=re.S))
    if len(instances)!=1: raise ValueError('Expected exactly one simple named instance for --core; use elaborated-netlist tools for parameterized/complex RTL')
    inst=instances[0]; widths={}; scope=rtl; owner=None
    modules=list(re.finditer(r'\bmodule\s+(\w+)\b.*?\bendmodule\b',rtl,flags=re.S))
    if modules:
        owners=[m for m in modules if m.start()<=inst.start()<m.end()]
        if len(owners)!=1: raise ValueError('Cannot determine owning module; use elaborated-netlist tools')
        scope=owners[0][0];owner=owners[0][1]
    for m in re.finditer(r'\b(?:wire|reg|logic)\s+(?:signed\s+)?(?:\[(\d+)\s*:\s*(\d+)\]\s*)?(\w+)',scope):
        widths[m[3]]=abs(int(m[1])-int(m[2]))+1 if m[1] else 1
    params=xci_parameters(xci); probes=[]; issues=[]
    for index,expression in re.findall(r'\.probe(\d+)\s*\(\s*([^)]*?)\s*\)',inst[2]):
        idx=int(index); expected=params.get(f'C_PROBE{idx}_WIDTH'); actual=widths.get(expression)
        state='unknown' if actual is None or expected is None else ('match' if actual==expected else 'mismatch')
        probes.append({'index':idx,'signal':expression,'rtl_width':actual,'xci_width':expected,'status':state})
        if state!='match': issues.append(f'probe{idx}_{state}')
    count=params.get('C_NUM_OF_PROBES'); depth=params.get('C_DATA_DEPTH')
    indices=[x['index'] for x in probes]
    if count is None or len(indices)!=count or len(set(indices))!=len(indices) or any(i<0 or i>=count for i in indices): issues.append('probe_count_or_indices')
    if depth is None: issues.append('capture_depth_unknown')
    clock=re.search(r'\.clk\s*\(\s*([^)]*)\)',inst[2])
    return {'instance':inst[1],'owner_module':owner,'clock_expression':clock[1].strip() if clock else None,'probes':probes,'capture_depth':depth,
      'assumed_clock_hz':clock_hz,'assumed_capture_stride':stride,
      'capture_duration_s':depth*stride/clock_hz if depth else None,
      'first_to_last_sample_s':(depth-1)*stride/clock_hz if depth else None,
      'issues':issues,'status':'pass' if not issues else 'needs_review',
      'scope':'Lightweight source scan; complex expressions/macros require elaboration. Clock rate and stride are caller supplied.'}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--rtl',type=Path,required=True);p.add_argument('--xci',type=Path,required=True)
    p.add_argument('--core',required=True);p.add_argument('--clock-hz',type=float,required=True)
    p.add_argument('--stride',type=int,default=1);p.add_argument('--output',type=Path)
    a=p.parse_args()
    try: data=audit(a.rtl.read_text(encoding='utf-8-sig',errors='replace'),a.xci,a.core,a.clock_hz,a.stride)
    except (OSError,ValueError,TypeError,IndexError,ET.ParseError) as e: p.exit(2,str(e)+'\n')
    text=json.dumps(data,ensure_ascii=False,indent=2)
    if a.output: a.output.write_text(text,encoding='utf-8')
    else: print(text)
    return 0 if data['status']=='pass' else 1
if __name__=='__main__': raise SystemExit(main())
