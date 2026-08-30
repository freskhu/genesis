---
voice-context: documentation
---

# Voice Banlist — WORKED EXAMPLE

> **This is an example, not a rule you inherit.** It is written in and for
> European Portuguese, and it encodes one person's register. Copy it to
> `.claude/rules/voice-banlist.md`, cut everything that does not apply to you,
> and add what your own writing keeps getting wrong.
>
> Until `voice-banlist.md` exists, the `voice-check.sh` hook and the `/voice-gate`
> skill stay inert. That is deliberate: a banlist copied wholesale from someone
> else's voice blocks sentences you would have wanted and lets through the ones
> you would not.
>
> **What generalises** (worth keeping in any language): the Tier 1 categories for
> language-neutral AI tells — the `not X, but Y` construction (T1.A), inflated
> vocabulary (T1.E), copula avoidance (T1.F), the decorative em-dash (T1.G), and
> the factual rules in T1.H. **What does not generalise:** the Portuguese
> orthography table (T1.I), the Brazilian-Portuguese vocabulary list, and the
> false-friend section — those are the *shape* of a language-specific rule, not
> the rule itself.
>
> The rest of this file is kept verbatim as a worked example, in the original
> Portuguese, because a banlist half-translated is a banlist that no longer
> matches the text it is checking.

---

# Voice Banlist — exemplo (PT-PT)

**Single source of truth para regras de voz/estilo.** Aplica a todos os outputs do agente top-level (o orquestrador) e hired/proxy sub-agents: chat, deliverables, emails, posts, decks, exames, código (comentários e docstrings).

**Out of scope:** working notes internas, status files, diary entries, scratchpads em workspace folders, relatórios internos de kaizen.

**Princípio:** Tier 1 = zero tolerância (regras universais anti-AI-tell). Tier 2 = context-dependent. PT-BR slips e AO90 = correcção sempre.

---

## Tier 1 — Zero tolerância (9 categorias)

### T1.A — Construções retóricas AI-tic

- **`X não Y` / `não é X, é Y` / `not just X, but Y`** — contraste retórico que afirma Y opondo-o a X. **Afirmar Y directo.**
- **Rule of three matched-rhythm** (`fast, reliable, and affordable`). Banido quando cosmético. OK em `literary` se ritmo é genuíno.

### T1.B — Hedging openers (PT + EN)

**PT-PT (banido):** `É importante notar`, `Vale ressaltar`, `Cumpre referir`, `Convém destacar`, `De realçar que`, `Importa sublinhar`, `É de notar`, `Cabe destacar`.

**EN (banned):** `It's important to note that`, `It's worth mentioning that`, `Generally speaking`, `It should be noted that`, `Worth noting`, `Of note`.

→ Afirmar a coisa directamente.

### T1.C — Sycophantic openers/closers

**PT-PT (banido):** `Boa pergunta!`, `Excelente ideia!`, `Espero que ajude!`, `Faz todo o sentido!`, `Óptimo ponto!`.

**EN (banned):** `Great question!`, `Excellent point!`, `I hope this helps!`, `Happy to help!`, `Absolutely!` (as standalone reply).

→ Responder à pergunta. Sem cerimónia.

### T1.D — Throat-clearing transitions

**PT-PT (banido):** `Em conclusão,`, `Em suma,`, `Em última análise,`, `Ao fim e ao cabo,`, `Por fim,` (como opener), `Adicionalmente,` (opener).

**EN (banned):** `Furthermore,`, `Moreover,`, `Additionally,` (opener), `In conclusion,`, `Ultimately,`, `That said,` (decorativo).

→ Skip ou usar verbo directo. **Skipped em `formal-minute`** (atas/minutas usam estas fórmulas legitimamente).

### T1.E — Inflated vocab EN

| Banido | Use |
|---|---|
| delve | dig into |
| leverage | use |
| robust | strong / reliable |
| seamless | smooth |
| pivotal | key / central |
| underscore | show / highlight |
| tapestry | mix / range |
| comprehensive | full / complete |
| navigate the complexities of | (reescrever directo) |
| in the realm of | in |
| facilitate | help / enable |
| utilize | use |
| myriad | many |

**Skipped em `documentation`.**

### T1.F — Copula avoidance EN

Verbos de elisão do `to be` típicos AI:

| Banido | Use |
|---|---|
| serves as | is |
| stands as | is |
| represents | is (when copula) |
| acts as | is |
| functions as | is |
| constitutes | is |

**Skipped em `documentation`.**

### T1.G — Em-dash em prosa corrida

Em-dash é **banido como aposição decorativa mid-sentence** ou ligador de pensamento em prosa corrida. **Convenção tipográfica legítima em:**

- Headers e títulos (`# Title — Subtitle`)
- Expansão de acrónimo (`SDK — Software Development Kit`)
- Células de tabela markdown
- List items com **1** em-dash (annotation pattern `- ITEM — ANNOTATION`); 2+ = abuso
- Bold-opener definition pattern (`**Id — Desc**` ou `**Id** — Desc`); cap 1 em-dash

**Detector é context-aware linha-a-linha:**

```
Para cada linha:
- Começa por # (header) → skip
- Tabela markdown (| celula | celula |) → skip
- É list item ou bold-opener:
    regex: ^[[:space:]]*([-*]|[0-9]+\.|[a-zA-Z]\.|[ivx]+\.)[[:space:]]
    OR    ^[[:space:]]*\*\*
  → conta em-dashes na linha:
      1 em-dash → skip (annotation legítima)
      2+ em-dashes → flag
- Resto (prosa corrida): cada em-dash conta como hit
```

**Cap por contexto:** `corporate`=0 em-dashes em prosa; `literary`=2 (prosa narrativa, case studies em prosa).

### T1.H — Capa AI factual

- **Invented personal details** — nunca fabricar `último café`, `lembras-te quando`, memórias partilhadas sem contexto verificado.
- **Gender assumption from names** — nomes ambíguos (Adri, Alex, Yuri, Sam, Chris) em PT/ES/IT/EN precisam de verificação **antes** de pronome ou concordância. Em PT, default neutro estrutural até confirmação.
- **Intentional typos a mimetizar voz humana** — quando se imita voz humana conhecida, ortografia sempre correcta. Typos da pessoa são byproduct de velocidade, não assinatura.

### T1.I — Ortografia PT-PT pós-AO90

O Acordo Ortográfico de 1990 está em vigor legal em Portugal desde 2009 e obrigatório desde 2014. Em PT-PT pós-AO90, consoantes mudas (c/p não pronunciadas em PT-PT culto) são eliminadas.

**Banidos (formas pré-AO90):**

| Categoria | Pré-AO90 | Pós-AO90 PT-PT |
|---|---|---|
| `c` muda (acção family) | acção, reacção, fracção | ação, reação, fração |
| `c` muda (acto/actor/actu-) | acto, actor, actual, actividade | ato, ator, atual, atividade |
| `c` muda (afecto/aspecto) | afecto, afectivo, aspecto | afeto, afetivo, aspeto |
| `c` muda (correct-/direct-) | correcto, correcção, directo | correto, correção, direto |
| `c` muda (eléctrico/exacto) | eléctrico, eletrónico, exacto | elétrico, eletrónico, exato |
| `c` muda (objecto/projecto) | objecto, objectivo, projecto | objeto, objetivo, projeto |
| `c` muda (selecç-/protecç-) | selecção, protecção, infecção | seleção, proteção, infeção |
| `p` muda (recep-/concep-) | recepção, concepção, percepção | receção, conceção, perceção |
| `p` muda (adopt-/bapt-) | adopção, baptismo, Egipto | adoção, batismo, Egito |
| `p` muda (óptimo/óptico) | óptimo, optimismo, óptico | ótimo, otimismo, ótico |
| `mp` → `n` | assumpção, peremptório, sumptuoso | assunção, perentório, suntuoso |
| Acentos diferenciais | pára (verbo), pêlo, pólo | para, pelo, polo |
| Outros | extracto, factor, director, espectador | extrato, fator, diretor, espetador |

**Exceções (NUNCA flagar)** — mantêm c/p em PT-PT pós-AO90 porque a consoante é pronunciada:
`facto`, `contacto`, `pacto`, `ficção`, `convicção`, `friccionar`, `apto`, `adepto`, `díptico`, `erupção`, `núpcias`, `rapto`, `expectativa`, `expectável`, `característica`, `carácter`, `prática` (substantivo), `egípcio` (mas `Egipto` flag), `compacto`, `intacto`, `infecto`, `inepto`, `manuscrito`, `descritivo`.

**Dúvidas resolvidas (excluídas do detector):** `facção`, `corrupto`, `tacto`, `pêra`, `pêro` — uso PT-PT culto mantém-se.

**Skipped em `documentation`** (docs que catalogam AO90 citam formas pré-AO90 como exemplos).

---

## PT-BR slips (sem tier — substituir sempre)

| PT-BR (banido) | PT-PT (correcto) |
|---|---|
| arquivo | ficheiro |
| gerenciar | gerir |
| time (equipa) | equipa |
| tela | ecrã |
| acessar | aceder |
| celular | telemóvel |
| trem | comboio |
| ônibus | autocarro |
| esporte | desporto |
| geladeira | frigorífico |
| sanduíche | sandes |
| bilheteria | bilheteira |
| caixa eletrônico | multibanco |
| café da manhã | pequeno-almoço |
| tá | está |
| pra | para |
| imã | íman |
| usuário | utilizador |
| senha | palavra-passe |
| mídia | media |
| time (sport) | equipa |
| cara (sujeito) | tipo / gajo |

PT-BR slips são separados de AO90. AO90 cobre ortografia (`receção` vs `recepção`); PT-BR slip cobre vocabulário (`ficheiro` vs `arquivo`). As duas regras aplicam em paralelo.

---

## Anglicismos falsos-amigos (banir sempre — vocabulário, sem tier)

Palavras inglesas adaptadas que, em PT-PT, têm um significado completamente diferente (e por vezes vulgar) do sentido técnico pretendido. Banir em todos os contextos, incluindo os relaxados.

| Banido (anglicismo) | Sentido pretendido | Usar em PT-PT |
|---|---|---|
| pinar / pinado | "to pin" — fixar/assentar uma decisão | **fechar**, **fixar**, **deixar assente**, **assentar**, **confirmar** |

**Nota crítica:** `pinar` em PT-PT é calão vulgar para "ter relações sexuais". NUNCA usar com o sentido de "pin/lock in" — risco real de aparecer num email a cliente. Aplica a TODOS os agentes que produzem texto.

---

## Contextos (4)

O detector reconhece 4 contextos. Cada um relaxa um subset de regras em situações onde aplicação literal de Tier 1 produz false positives.

### Como o context é determinado

**1. Front-matter explicit (priority).** Se o ficheiro tem YAML front-matter com `voice-context: <type>`, esse valor wins.

```yaml
---
voice-context: literary
---
```

**2. Path-based defaults (fallback) — adaptado ao nosso setup:**

- Prosa académica ou formal em `Owners Inbox/**` → `corporate` (strict)
- `.claude/**`, `Owners Inbox/**/runbook*`, `Owners Inbox/**/spec*` (docs técnicas) → `documentation`
- Atas, minutas e propostas formais → `formal-minute`
- Prosa narrativa (se existir no teu setup) → `literary`

**3. Default.** `corporate` (strict Tier 1, sem relaxamentos).

### Comportamento por context

| Context | Categoria relaxada | Regra |
|---|---|---|
| `corporate` (default) | — | Full Tier 1 strict |
| `literary` | T1.G em-dash | Cap = 2 em-dashes por linha de prosa. Headers/tables/lists mantêm regra original |
| `formal-minute` | T1.D throat-clearing | Skip T1.D-PT e T1.D-EN. `Em conclusão` / `In conclusion` OK em atas/minutas/propostas legais |
| `documentation` | **(todas)** | Exit clean. Gate não corre. Docs catalogam patterns em todas as categorias |

### Trade-off conhecido

Em `documentation` context, o gate **não corre**. Mitigação: restringir este context a paths específicos (`.claude/rules/`, `.claude/skills/`, docs de estilo, specs técnicas) onde catalogar/explicar patterns é a função do ficheiro.

---

## Aplicação em sub-agentes

Sub-agentes que produzem texto recebem instrução literal no dispatch:

> "Aplicar voice-banlist em `.claude/rules/voice-banlist.md`. Tier 1 zero tolerância. AO90 PT-PT sempre. Sem PT-BR slips. Sem invented personal details. Sem gender assumption from names."

---

## Manutenção

- Quando um AI-tell novo aparece num deliverable real, propor adição à banlist com pattern + categoria + tier + exemplos. O dono do sistema aprova ou rejeita.
- Edits à banlist mantêm changelog no fim com data + razão + amostras validadas.
- Calibrações ao detector vão ao changelog do hook/skill, com validação contra amostras reais.

---

## Changelog

- **v1** — banlist canónica criada. 9 categorias Tier 1 + PT-BR slips + 4 contextos + path-based defaults.
- **v2** — Adicionada a secção "Anglicismos falsos-amigos": `pinar/pinado` banido (calão vulgar PT-PT, não "pin/fixar"). Entrou depois de o orquestrador o usar repetidamente e ser corrigido duas vezes — o padrão de como uma regra nasce: um erro real, repetido, corrigido, escrito.
