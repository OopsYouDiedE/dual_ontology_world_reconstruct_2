"""Assemble a blind contestant's label syntax without changing their policy."""
import argparse
from hashlib import sha256
import json
from pathlib import Path
import re

from .fuel import PolicyVM


def assemble(source):
    labels, code = {}, []
    for n, raw in enumerate(source.splitlines(),1):
        line=raw.strip()
        if not line or line.startswith("#"): continue
        if match := re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*):",line):
            name=match[1]
            if name in labels: raise ValueError(f"duplicate label {name} at source line {n}")
            labels[name]=len(code)
        else:
            row=json.loads(line)
            if not isinstance(row,list) or not row: raise ValueError(f"expected instruction at source line {n}")
            code.append(row)
    for pc,row in enumerate(code):
        if row[0] in ("jump","if") and isinstance(row[-1],str):
            if row[-1] not in labels: raise ValueError(f"unknown label {row[-1]} at pc={pc}")
            row[-1]=labels[row[-1]]
    PolicyVM(code)
    return code


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source",type=Path)
    parser.add_argument("--out",type=Path,required=True)
    parser.add_argument("--revision",required=True)
    parser.add_argument("--provenance",required=True)
    parser.add_argument("--ability-profile",required=True)
    args=parser.parse_args()
    original=args.source.read_bytes()
    code=assemble(original.decode("utf-8-sig"))
    sol={"model":"gpt-6.2-sol","revision":args.revision,"provenance":args.provenance,
         "ability_profile":args.ability_profile,"author_source_sha256":sha256(original).hexdigest(),"program":code}
    result=(json.dumps(sol,ensure_ascii=False,indent=2)+"\n").encode("utf-8")
    args.out.parent.mkdir(parents=True,exist_ok=True)
    # Freeze rather than overwrite a submitted version.
    with args.out.open("xb") as file: file.write(result)
    print(json.dumps({"instructions":len(code),"author_source_sha256":sol["author_source_sha256"],"policy_sha256":sha256(result).hexdigest()}))
    return 0


if __name__=="__main__":
    raise SystemExit(main())
