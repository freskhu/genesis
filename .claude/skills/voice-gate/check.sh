#!/usr/bin/env bash
# voice-gate/check.sh — hard-block variant of the voice-check.sh hook.
# Reads a file path from $1, runs the full Tier 1 banlist check, prints
# VERDICT=passed|blocked|error and exits 0/1/2.
#
# Source of truth: .claude/rules/voice-banlist.md
#
# The detector patterns below implement the shipped example banlist
# (.claude/rules/voice-banlist.example.md). Categories T1.A, T1.E, T1.F and T1.G
# are language-neutral; the rest are European Portuguese and are there as a
# worked example of how a language-specific rule is expressed. Replace them with
# the rules of your own language and register before relying on the verdict.

set -u

file_path="${1:-}"

if [ -z "$file_path" ]; then
  echo "VERDICT=error reason=no-file-path-argument"
  exit 2
fi

# resolve relative paths against project root (cwd)
case "$file_path" in
  /*) ;;
  *) file_path="$(pwd)/$file_path" ;;
esac

if [ ! -f "$file_path" ]; then
  echo "VERDICT=error reason=file-not-found path=$file_path"
  exit 2
fi

# ----- context detection (same as hook, but no path-based default exit) -----
context="corporate"
if head -n 5 "$file_path" 2>/dev/null | grep -qE '^voice-context:'; then
  fm=$(head -n 10 "$file_path" 2>/dev/null | grep -E '^voice-context:' | head -n 1 | sed -E 's/^voice-context:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d ' \r')
  case "$fm" in
    corporate|literary|formal-minute|documentation) context="$fm" ;;
  esac
else
  case "$file_path" in
    */.claude/*) context="documentation" ;;
    *runbook*|*spec*|*SPEC*|*README*) context="documentation" ;;
    *minute*|*minuta*|*ata*) context="formal-minute" ;;
  esac
fi

if [ "$context" = "documentation" ]; then
  echo "VERDICT=passed reason=documentation-context-exits-clean"
  exit 0
fi

# ----- accumulator -----
violations=""
add_v() { violations="${violations}- ${1}"$'\n'; }

count_eri() {
  local n
  n=$(grep -cEi "$1" "$file_path" 2>/dev/null) || n=0
  printf '%s' "${n:-0}"
}

# T1.A
n=$(count_eri 'not just [^,.]+ but |não é [^,.]+, é ')
[ "$n" -gt 0 ] && add_v "T1.A rhetorical AI-tic construction: $n hit(s)"

# T1.B
n=$(count_eri 'é importante notar|vale ressaltar|cumpre referir|convém destacar|de realçar que|importa sublinhar|é de notar|cabe destacar|it'\''s important to note that|it'\''s worth mentioning that|generally speaking|it should be noted that|worth noting|of note,')
[ "$n" -gt 0 ] && add_v "T1.B hedging opener: $n hit(s)"

# T1.C
n=$(count_eri 'boa pergunta!|excelente ideia!|espero que ajude!|faz todo o sentido!|óptimo ponto!|great question!|excellent point!|i hope this helps!|happy to help!')
[ "$n" -gt 0 ] && add_v "T1.C sycophantic opener/closer: $n hit(s)"

# T1.D (skip in formal-minute)
if [ "$context" != "formal-minute" ]; then
  td_count=$(grep -cE '^[[:space:]]*(Em conclusão,|Em suma,|Em última análise,|Ao fim e ao cabo,|Por fim,|Adicionalmente,|Furthermore,|Moreover,|Additionally,|In conclusion,|Ultimately,|That said,)' "$file_path" 2>/dev/null) || td_count=0
  [ "$td_count" -gt 0 ] && add_v "T1.D throat-clearing transition (opener): $td_count hit(s)"
fi

# T1.E
n=$(count_eri '\bdelve\b|\bleverage\b|\brobust\b|\bseamless\b|\bpivotal\b|\bunderscore\b|\btapestry\b|\bcomprehensive\b|\bin the realm of\b|\bfacilitate\b|\butilize\b|\bmyriad\b|navigate the complexities of')
[ "$n" -gt 0 ] && add_v "T1.E inflated vocabulary: $n hit(s)"

# T1.F
n=$(count_eri '\bserves as\b|\bstands as\b|\bacts as\b|\bfunctions as\b|\bconstitutes\b')
[ "$n" -gt 0 ] && add_v "T1.F copula avoidance: $n hit(s)"

# T1.G em-dash (context-aware, line-by-line)
em_cap=0
[ "$context" = "literary" ] && em_cap=2
tg_hits=0
while IFS= read -r line || [ -n "$line" ]; do
  [ -z "$line" ] && continue
  case "$line" in
    \#*) continue ;;
    \|*\|*) continue ;;
  esac
  emcount=$(printf '%s' "$line" | grep -o '—' | wc -l | tr -d ' ')
  [ "${emcount:-0}" -eq 0 ] && continue
  if printf '%s' "$line" | grep -qE '^[[:space:]]*([-*]|[0-9]+\.|[a-zA-Z]\.|[ivx]+\.)[[:space:]]' \
     || printf '%s' "$line" | grep -qE '^[[:space:]]*\*\*'; then
    [ "$emcount" -ge 2 ] && tg_hits=$((tg_hits + emcount))
  else
    over=$((emcount - em_cap))
    [ "$over" -gt 0 ] && tg_hits=$((tg_hits + over))
  fi
done < "$file_path"
[ "$tg_hits" -gt 0 ] && add_v "T1.G decorative em-dash in running prose (context=$context): $tg_hits hit(s)"

# T1.I AO90
n=$(count_eri '\bacç(ão|ões)\b|\breacç(ão|ões)\b|\bfracç(ão|ões)\b|\bacto\b|\bactos\b|\bactor(es)?\b|\bactriz(es)?\b|\bactual(mente|izar|ização)?\b|\bactivid(ade|ades)\b|\bafect(o|os|ar|iva?o?s?|ivo|ivos|ivamente)\b|\baspect(o|os)\b|\bcorrect(o|a|os|as|amente|ar|ivo)\b|\bcorrecç(ão|ões)\b|\bdirect(o|a|os|as|amente|or|ora|ores|oras|orio)\b|\bdirecç(ão|ões)\b|\beléctric(o|a|os|as|idade)\b|\beletrónic(o|a|os|as)\b|\bexact(o|a|os|as|amente|idão)\b|\bobject(o|os|ivo|ivos|ivamente)\b|\bobjecç(ão|ões)\b|\bproject(o|os|ar|ado|ada)\b|\bselecç(ão|ões)\b|\bselect(ivo|iva|ivos|ivas)\b|\bprotecç(ão|ões)\b|\binfecç(ão|ões)\b|\binspecç(ão|ões)\b|\brecepç(ão|ões)\b|\bconcepç(ão|ões)\b|\bpercepç(ão|ões)\b|\bdecepç(ão|ões)\b|\bexcepç(ão|ões)\b|\badopç(ão|ões)\b|\bbaptism(o|al)\b|\bEgipto\b|\bóptim(o|a|os|as)\b|\boptimism(o)?\b|\bóptic(o|a|os|as)\b|\bassumpç(ão|ões)\b|\bperemptóri(o|a|os|as)\b|\bsumptuos(o|a|os|as)\b|\bpára\b|\bpêlo\b|\bpólo\b|\bextract(o|os)\b|\bfactor(es)?\b|\bespectador(es)?\b|\binsectos?\b|\barchitect(o|a|os|as|ura)\b|\btransacç(ão|ões)\b')
[ "$n" -gt 0 ] && add_v "T1.I spelling: $n pre-reform Portuguese form(s)"

# PT-BR
n=$(count_eri '\barquivo(s)?\b|\bgerenciar\b|\btela(s)?\b|\bacessar\b|\bcelular(es)?\b|\btrem\b|\bônibus\b|\besporte(s)?\b|\bgeladeira\b|\bsanduíche\b|\bbilheteria\b|\bcaixa eletrônico\b|\bcafé da manhã\b|\busuário(s)?\b|\bsenha(s)?\b|\bmídia(s)?\b')
[ "$n" -gt 0 ] && add_v "Brazilian Portuguese slips in a European Portuguese text: $n hit(s)"

# False-friend anglicisms: an English verb borrowed into the local language
# where it already means something else. Example is PT-PT; swap in your own.
n=$(count_eri '\bpinar\b|\bpinad[oa](s)?\b')
[ "$n" -gt 0 ] && add_v "False-friend anglicism 'pinar/pinado': $n hit(s) — it is vulgar slang, not 'to pin'; use fechar/fixar/deixar assente"

# ----- verdict -----
if [ -z "$violations" ]; then
  echo "VERDICT=passed context=$context file=$file_path"
  exit 0
else
  echo "VERDICT=blocked context=$context file=$file_path"
  echo "Violations:"
  printf '%s' "$violations"
  echo
  echo "See .claude/rules/voice-banlist.md. Refine and re-invoke /voice-gate."
  exit 1
fi
