#!/usr/bin/env bash
# voice-check.sh — PostToolUse soft-alert hook for voice-banlist violations.
# Reads JSON tool input from stdin, scans the Write/Edit target when it is in
# deliverable scope, and emits warnings as JSON hookSpecificOutput.additionalContext.
#
# CRITICAL: PostToolUse stdout does NOT reach the model. Warnings MUST be emitted
# in JSON via hookSpecificOutput.additionalContext. A plain echo only goes to debug.
#
# Source of truth: .claude/rules/voice-banlist.md — the hook stays INERT until
# that file exists. Ship a banlist of your own; .claude/rules/voice-banlist.example.md
# is a worked example (European Portuguese plus the language-neutral AI tells).
# The detector patterns below match that example: Tier 1 categories are
# language-neutral (T1.A, T1.E, T1.F, T1.G), the rest are PT-PT specific. Rewrite
# the PT-PT blocks for your own language before relying on them.
#
# The gate is soft by design: it warns, it never blocks. The hard gate for
# published deliverables is the /voice-gate skill.

set -u

# Repo root is two levels up from .claude/hooks/.
REPO_ROOT="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)" || exit 0
[ -f "$REPO_ROOT/.claude/rules/voice-banlist.md" ] || exit 0

# ----- read input -----
input="$(cat)"
file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)"

# ----- effort gate -----
# This is a soft-alert, not a safety control, so it is cheap to skip when the turn
# is running at low effort (quick iterative edits) — cuts noise without hiding a
# real gate. $CLAUDE_EFFORT first, JSON stdin (.effort.level) fallback. Absent /
# any other level (medium|high|xhigh|max) -> run the full scan (current behaviour).
effort="${CLAUDE_EFFORT:-$(printf '%s' "$input" | jq -r '.effort.level // empty' 2>/dev/null)}"
[ "$effort" = "low" ] && exit 0

# silent exit if no file_path
[ -z "$file_path" ] && exit 0
[ ! -f "$file_path" ] && exit 0

# ----- scope filter (positive match required) -----
# Only run on deliverable folders. Adjust paths as needed.
case "$file_path" in
  */Owners\ Inbox/*) ;;
  */Team\ Inbox/*) ;;
  *) exit 0 ;;
esac

# ----- out-of-scope sub-paths -----
case "$file_path" in
  *.status.md|*_status.md|*diary-entry*|*kg-facts*|*_session_pending*|*/_processed/*|*/_archive*/*) exit 0 ;;
esac

# ----- extension filter -----
case "$file_path" in
  *.md|*.markdown|*.txt) ;;
  *) exit 0 ;;
esac

# ----- context detection -----
context="corporate"
# front-matter wins
if head -n 5 "$file_path" 2>/dev/null | grep -qE '^voice-context:'; then
  fm=$(head -n 10 "$file_path" 2>/dev/null | grep -E '^voice-context:' | head -n 1 | sed -E 's/^voice-context:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d ' \r')
  case "$fm" in
    corporate|literary|formal-minute|documentation) context="$fm" ;;
  esac
else
  # path-based fallback
  case "$file_path" in
    */.claude/*) context="documentation" ;;
    *runbook*|*spec*|*SPEC*|*README*) context="documentation" ;;
    *proposta*concurso*|*minuta*|*ata*) context="formal-minute" ;;
  esac
fi

# documentation context → exit clean
[ "$context" = "documentation" ] && exit 0

# ----- accumulator -----
warnings=""
add_warning() { warnings="${warnings}- ${1}"$'\n'; }

# Helper: count matches of an extended-regex pattern (case-insensitive) in file.
# Always prints exactly one integer (grep -c exits 1 with output "0" when no match).
count_eri() {
  local n
  n=$(grep -cEi "$1" "$file_path" 2>/dev/null) || n=0
  printf '%s' "${n:-0}"
}

# ----- T1.A — rhetorical AI-tic constructions -----
ta_count=0
ta_count=$((ta_count + $(count_eri 'not just [^,.]+ but ')))
ta_count=$((ta_count + $(count_eri 'não é [^,.]+, é ')))
[ "$ta_count" -gt 0 ] && add_warning "T1.A rhetorical AI-tic construction (not X but Y / nao e X, e Y): $ta_count hit(s). State the claim directly."

# ----- T1.B — hedging openers -----
tb_count=0
tb_pat='é importante notar|vale ressaltar|cumpre referir|convém destacar|de realçar que|importa sublinhar|é de notar|cabe destacar|it'\''s important to note that|it'\''s worth mentioning that|generally speaking|it should be noted that|worth noting|of note,'
tb_count=$(count_eri "$tb_pat")
[ "$tb_count" -gt 0 ] && add_warning "T1.B hedging opener: $tb_count hit(s). State the thing directly."

# ----- T1.C — sycophantic openers/closers -----
tc_count=0
tc_pat='boa pergunta!|excelente ideia!|espero que ajude!|faz todo o sentido!|óptimo ponto!|great question!|excellent point!|i hope this helps!|happy to help!'
tc_count=$(count_eri "$tc_pat")
[ "$tc_count" -gt 0 ] && add_warning "T1.C sycophantic opener/closer: $tc_count hit(s). Answer the question, skip the ceremony."

# ----- T1.D — throat-clearing transitions (skip in formal-minute) -----
if [ "$context" != "formal-minute" ]; then
  td_count=0
  # match only as line-openers to avoid mid-sentence false positives
  td_pat='^[[:space:]]*(Em conclusão,|Em suma,|Em última análise,|Ao fim e ao cabo,|Por fim,|Adicionalmente,|Furthermore,|Moreover,|Additionally,|In conclusion,|Ultimately,|That said,)'
  td_count=$(grep -cE "$td_pat" "$file_path" 2>/dev/null) || td_count=0
  [ "$td_count" -gt 0 ] && add_warning "T1.D throat-clearing transition (line opener): $td_count hit(s). Cut it, or lead with the verb."
fi

# ----- T1.E — inflated vocab EN (skip in documentation, but we already exited if doc) -----
te_count=0
te_pat='\bdelve\b|\bleverage\b|\brobust\b|\bseamless\b|\bpivotal\b|\bunderscore\b|\btapestry\b|\bcomprehensive\b|\bin the realm of\b|\bfacilitate\b|\butilize\b|\bmyriad\b|navigate the complexities of'
te_count=$(count_eri "$te_pat")
[ "$te_count" -gt 0 ] && add_warning "T1.E inflated vocabulary: $te_count hit(s). Use the plain word (delve->dig into, leverage->use, robust->strong, seamless->smooth, pivotal->key, underscore->show, comprehensive->full, facilitate->help, utilize->use, myriad->many)."

# ----- T1.F — copula avoidance EN -----
tf_count=0
tf_pat='\bserves as\b|\bstands as\b|\bacts as\b|\bfunctions as\b|\bconstitutes\b'
tf_count=$(count_eri "$tf_pat")
[ "$tf_count" -gt 0 ] && add_warning "T1.F copula avoidance: $tf_count hit(s). Use a plain 'is' (serves as->is, stands as->is, acts as->is)."

# ----- T1.G — em-dash context-aware line-by-line -----
# em-dash chars: U+2014 (—). en-dash (–) optional include.
em_cap=0
[ "$context" = "literary" ] && em_cap=2
tg_hits=0
while IFS= read -r line || [ -n "$line" ]; do
  # skip empty
  [ -z "$line" ] && continue
  # skip headers
  case "$line" in
    \#*) continue ;;
  esac
  # skip table rows (simple heuristic: starts with | and contains another |)
  case "$line" in
    \|*\|*) continue ;;
  esac
  # count em-dashes on the line (— = U+2014, 3 bytes UTF-8; BSD awk RS multi-byte unreliable, use grep -o)
  emcount=$(printf '%s' "$line" | grep -o '—' | wc -l | tr -d ' ')
  [ "${emcount:-0}" -eq 0 ] && continue

  # is list-item or bold-opener?
  if printf '%s' "$line" | grep -qE '^[[:space:]]*([-*]|[0-9]+\.|[a-zA-Z]\.|[ivx]+\.)[[:space:]]' \
     || printf '%s' "$line" | grep -qE '^[[:space:]]*\*\*'; then
    # annotation pattern: 1 em-dash OK; 2+ flag
    if [ "$emcount" -ge 2 ]; then
      tg_hits=$((tg_hits + emcount))
    fi
  else
    # running prose — every em-dash beyond cap counts
    over=$((emcount - em_cap))
    [ "$over" -gt 0 ] && tg_hits=$((tg_hits + over))
  fi
done < "$file_path"
[ "$tg_hits" -gt 0 ] && add_warning "T1.G decorative em-dash in running prose: $tg_hits hit(s) over the cap (context=$context). Fine in headers, table cells and list items carrying one em-dash; banned mid-sentence in prose."

# ----- T1.I — AO90 PT-PT (skip in documentation, but we already exited if doc) -----
# pre-AO90 forms (case-insensitive) — list compiled from banlist tables
# avoid exceptions: facto, contacto, pacto, ficção, convicção, friccionar, apto, adepto,
#   díptico, erupção, núpcias, rapto, expectativa, expectável, característica, carácter,
#   prática (substantivo), egípcio, facção, corrupto, tacto, pêra, pêro, compacto, intacto,
#   infecto, inepto, manuscrito, descritivo
# we use word-boundary patterns that target the specific banned roots
ti_count=0
ti_pat='\bacç(ão|ões)\b|\breacç(ão|ões)\b|\bfracç(ão|ões)\b|\bacto\b|\bactos\b|\bactor(es)?\b|\bactriz(es)?\b|\bactual(mente|izar|ização)?\b|\bactivid(ade|ades)\b|\bafect(o|os|ar|iva?o?s?|ivo|ivos|ivamente)\b|\baspect(o|os)\b|\bcorrect(o|a|os|as|amente|ar|ivo)\b|\bcorrecç(ão|ões)\b|\bdirect(o|a|os|as|amente|or|ora|ores|oras|orio)\b|\bdirecç(ão|ões)\b|\beléctric(o|a|os|as|idade)\b|\beletrónic(o|a|os|as)\b|\bexact(o|a|os|as|amente|idão)\b|\bobject(o|os|ivo|ivos|ivamente)\b|\bobjecç(ão|ões)\b|\bproject(o|os|ar|ado|ada)\b|\bselecç(ão|ões)\b|\bselect(ivo|iva|ivos|ivas)\b|\bprotecç(ão|ões)\b|\binfecç(ão|ões)\b|\binspecç(ão|ões)\b|\brecepç(ão|ões)\b|\bconcepç(ão|ões)\b|\bpercepç(ão|ões)\b|\bdecepç(ão|ões)\b|\bexcepç(ão|ões)\b|\badopç(ão|ões)\b|\bbaptism(o|al)\b|\bEgipto\b|\bóptim(o|a|os|as)\b|\boptimism(o)?\b|\bóptic(o|a|os|as)\b|\bassumpç(ão|ões)\b|\bperemptóri(o|a|os|as)\b|\bsumptuos(o|a|os|as)\b|\bpára\b|\bpêlo\b|\bpólo\b|\bextract(o|os)\b|\bfactor(es)?\b|\bespectador(es)?\b|\binsectos?\b|\barchitect(o|a|os|as|ura)\b|\bcaracteriz(ar|ado|ada)\b|\bjuriz?dicção\b|\btransacç(ão|ões)\b'
ti_count=$(count_eri "$ti_pat")
[ "$ti_count" -gt 0 ] && add_warning "T1.I spelling (PT-PT, post-1990 orthographic agreement): $ti_count pre-reform form(s) found. Drop the silent c/p (accao->acao, recepcao->rececao, projecto->projeto, electrico->eletrico, factor->fator, director->diretor). Exceptions such as 'facto', 'contacto' and 'pacto' keep theirs."

# ----- PT-BR slips -----
ptbr_count=0
ptbr_pat='\barquivo(s)?\b|\bgerenciar\b|\btela(s)?\b|\bacessar\b|\bcelular(es)?\b|\btrem\b|\bônibus\b|\besporte(s)?\b|\bgeladeira\b|\bsanduíche\b|\bbilheteria\b|\bcaixa eletrônico\b|\bcafé da manhã\b|\busuário(s)?\b|\bsenha(s)?\b|\bmídia(s)?\b'
ptbr_count=$(count_eri "$ptbr_pat")
[ "$ptbr_count" -gt 0 ] && add_warning "Brazilian Portuguese slip in a European Portuguese text: $ptbr_count hit(s). arquivo->ficheiro, gerenciar->gerir, tela->ecra, acessar->aceder, celular->telemovel, usuario->utilizador, senha->palavra-passe, midia->media."

# ----- False-friend anglicisms -----
# An English verb borrowed into the local language where it already means
# something else entirely. Worth a rule of its own: the borrowed sense reads as
# perfectly normal jargon to the writer and as something else to the reader.
# Example below is PT-PT; replace it with the false friends of your own language.
fa_count=$(count_eri '\bpinar\b|\bpinad[oa](s)?\b')
[ "$fa_count" -gt 0 ] && add_warning "False-friend anglicism 'pinar/pinado' ($fa_count hit(s)): it does not mean 'to pin' in European Portuguese, it is vulgar slang. Use fechar / fixar / deixar assente."

# ----- emit -----
if [ -n "$warnings" ]; then
  # safely build the additionalContext payload
  payload=$(printf 'VOICE-CHECK warnings in %s (context=%s):\n%s\nSee .claude/rules/voice-banlist.md. Fix before declaring the work done.' "$file_path" "$context" "$warnings")
  # emit JSON
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ctx "$payload" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
  else
    # fallback manual escape
    esc=$(printf '%s' "$payload" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n' | sed 's/\\n$//')
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' "$esc"
  fi
fi

exit 0
