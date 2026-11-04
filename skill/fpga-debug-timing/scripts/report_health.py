"""Read Vivado text reports without modifying the project. Stdlib only."""
import argparse, hashlib, json, math, re
from pathlib import Path

def timing_summary(text):
    lines=text.splitlines()
    result={k:None for k in ('wns_ns','tns_ns','setup_failing_endpoints','whs_ns','ths_ns','hold_failing_endpoints','wpws_ns')}
    for i,line in enumerate(lines):
        if 'WNS(ns)' in line and 'TNS(ns)' in line:
            for candidate in lines[i+1:i+6]:
                cells=candidate.split()
                if len(cells)>=12:
                    try: v=[float(x) for x in cells[:12]]
                    except ValueError: continue
                    if not all(math.isfinite(x) for x in v): continue
                    result.update(wns_ns=v[0],tns_ns=v[1],setup_failing_endpoints=int(v[2]),
                        whs_ns=v[4],ths_ns=v[5],hold_failing_endpoints=int(v[6]),wpws_ns=v[8])
                    break
            break
    result['unconstrained']={}
    for k,n in re.findall(r'checking\s+(no_clock|unconstrained_internal_endpoints|no_input_delay|no_output_delay)\s*\((\d+)\)',text):
        result['unconstrained'][k]=max(result['unconstrained'].get(k,0),int(n))
    return result

def utilization(text):
    names={'Slice LUTs':'lut','CLB LUTs':'lut','Slice Registers':'register','CLB Registers':'register','Block RAM Tile':'bram','DSPs':'dsp'}
    result={}
    for line in text.splitlines():
        cells=[x.strip() for x in line.strip().strip('|').split('|')]
        if len(cells)>=6:
            key=re.sub(r'\*+$','',cells[0]).strip()
            if key in names:
                try:
                    values=[float(cells[1].replace(',','')),float(cells[-2].replace(',','')),float(cells[-1].replace('%',''))]
                    if all(math.isfinite(x) and x>=0 for x in values): result[names[key]]={'used':values[0],'available':values[1],'percent':values[2]}
                except ValueError: pass
    return result

def drc_rules(text):
    rules=[]
    for line in text.splitlines():
        m=re.match(r'\|\s*([A-Z][A-Z0-9]+-\d+)\s*\|\s*(Critical Warning|Warning|Error|Advisory)\s*\|\s*(.*?)\s*\|\s*(\d+)\s*\|',line)
        if m: rules.append({'rule':m[1],'severity':m[2],'description':m[3],'count':int(m[4])})
    return rules

def review(timing_text,utilization_text='',drc_text='',methodology_text=''):
    t=timing_summary(timing_text); u=utilization(utilization_text); rules=drc_rules(drc_text)+drc_rules(methodology_text)
    findings=[]
    metadata={}
    for label,text in [('timing',timing_text),('utilization',utilization_text),('drc',drc_text),('methodology',methodology_text)]:
        match=re.search(r'^\s*\|\s*Design\s*:\s*([^|\r\n]+)',text,re.M)
        if match: metadata[label]={'design':match[1].strip()}
    if len({v['design'] for v in metadata.values()})>1: findings.append('mixed_design_reports')
    if re.search(r'Timing constraints are not met\b',timing_text,re.I): findings.append('explicit_timing_failure')
    if any(t[k] is not None and t[k]<0 for k in ('wns_ns','whs_ns','wpws_ns')): findings.append('negative_timing_slack')
    if any(t[k] is not None and t[k]>0 for k in ('setup_failing_endpoints','hold_failing_endpoints')): findings.append('failing_timing_endpoints')
    if any(t['unconstrained'].values()): findings.append('missing_timing_constraints')
    if any(r['severity'] in ('Critical Warning','Error') for r in rules): findings.append('critical_or_error_drc')
    missing=[]
    if utilization_text.strip() and not u: missing.append('utilization_unparsed')
    for label,text in [('drc',drc_text),('methodology',methodology_text)]:
        reported=re.search(r'Violations found:\s*(\d+)',text)
        parsed=drc_rules(text)
        if text.strip() and not parsed and (not reported or int(reported[1])!=0): missing.append(label+'_summary_unparsed')
    if t['wns_ns'] is None or t['whs_ns'] is None or t['wpws_ns'] is None: missing.append('timing_summary')
    if set(t['unconstrained'])!={'no_clock','unconstrained_internal_endpoints','no_input_delay','no_output_delay'}: missing.append('constraint_coverage')
    status='fail' if findings else ('unknown' if missing else 'pass_within_report_scope')
    return {'status':status,'timing':t,'resources':u,'rules':rules,'report_metadata':metadata,'findings':findings,'missing':missing,
        'scope':'Report extraction only; does not prove current RTL freshness, CDC correctness or hardware function.'}

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ('timing','utilization','drc','methodology'): ap.add_argument('--'+name,type=Path)
    ap.add_argument('--output',type=Path); ap.add_argument('--strict',action='store_true')
    args=ap.parse_args(); texts={}; evidence={}
    try:
        for name in ('timing','utilization','drc','methodology'):
            p=getattr(args,name)
            texts[name]=p.read_text(encoding='utf-8-sig',errors='replace') if p else ''
            if p: evidence[name]={'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
    except OSError as e: ap.exit(2,str(e)+'\n')
    result=review(texts['timing'],texts['utilization'],texts['drc'],texts['methodology']); result['evidence']=evidence
    data=json.dumps(result,ensure_ascii=False,indent=2)
    if args.output: args.output.write_text(data,encoding='utf-8')
    else: print(data)
    if args.strict: return {'fail':1,'unknown':2}.get(result['status'],0)
    return 0
if __name__=='__main__': raise SystemExit(main())
