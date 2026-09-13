#!/usr/bin/env python3
"""Runner-level delivery check: facts only, no judgment.
A part.json is accepted in either shape the solver produces:
  (a) a components list (non-empty, unique ids), or
  (b) a module delivery: "module" (file) + "export" (symbol) that the parent composes.
Child references, if present, must point at existing part.json files."""
import json, sys, os
from pathlib import Path
p = Path(sys.argv[1])
try:
    d = json.loads(p.read_text())
except Exception as e:
    print(f"invalid_json: {e}"); sys.exit(1)
if isinstance(d, list): d = {'components': d}
comps = d.get('components')
mod = d.get('module'); exp = d.get('export')
if comps:
    ids = [c.get('id') for c in comps if isinstance(c, dict)]
    if len(ids) != len(set(ids)):
        print("duplicate_ids"); sys.exit(1)
    shape = f"components={len(comps)}"
elif isinstance(mod, str) and mod and isinstance(exp, str) and exp:
    if not (p.parent / mod).exists():
        print(f"module_missing: {mod}"); sys.exit(1)
    shape = f"module={mod}:{exp}"
else:
    print("empty_components"); sys.exit(1)
def _child_ok(c):  # a child is referenced either by a relative path to its part.json or by its node name
    return (p.parent / c).exists() or (p.parent.parent / c / 'part.json').exists() or (p.parent / c / 'part.json').exists()
missing = [c for c in (d.get('children') or []) if isinstance(c, str) and not _child_ok(c)]
if missing:
    print(f"child_missing: {missing[0]}"); sys.exit(1)
print(f"ok {shape} children={len(d.get('children') or [])}")
