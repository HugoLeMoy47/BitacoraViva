#!/usr/bin/env bash
# Uso: fin.sh <tipo> <nombre>   (desde la raíz del repo)
export ARCHIFY_UPDATE_CHECK_DISABLED=1
node ~/.claude/skills/archify/bin/archify.mjs finalize "$1" docs/diagramas/fuente/$2.json docs/diagramas/$2.html --quality "${3:-standard}" --json 2>&1 | python -c "
import sys,json
d=json.loads(sys.stdin.read())
print(d['status'],d['gates'])
for x in d.get('diagnostics',[]): print(x['code'],x['message'][:400])
"
rm -f docs/diagramas/*.finalize*.json docs/diagramas/*.browser-check.json docs/diagramas/*.delivery.json
