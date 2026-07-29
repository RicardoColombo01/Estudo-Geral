# Plano — IA de estudo + quadro de projeto compartilhado

## Contexto

A trilha está completa como **registro**: temas, itens, progresso com datas, anotações,
materiais, modelo oficial com novidades, PWA que funciona offline. O que falta é ela
**ajudar a estudar** — e é isso que o Ricardo pediu: IA para estudar e pesquisar, e algo
"tipo Notion" para tocar projeto em grupo.

A vantagem que este app tem sobre abrir o Claude direto é **o contexto**: ele sabe o que
você concluiu, quando, o que anotou e o que salvou. Todo o desenho abaixo parte disso — a
IA nunca começa do zero, e o resultado dela vira **conteúdo seu**, não conversa que se
perde.

Decisões tomadas com ele (AskUserQuestion, 2026-07-28):

| Assunto | Decisão |
|---|---|
| Superfície | **Os dois**: ações no lugar da dúvida **+** chat que já sabe o tema |
| Primeiras ações | **As três juntas**: buscar materiais · gerar cartões de revisão · explicar item |
| "Tipo Notion" | **Quadro de projeto compartilhado** (não clone do Notion) |
| Chave da API | **Ele ainda não tem** — a Fase 0 é criar a conta |

**Por que as três ações juntas não são três vezes o trabalho:** elas compartilham a Edge
Function, o montador de contexto, o limitador de uso e a tela de proposta/aceite. Depois da
primeira, cada ação nova é um prompt, um schema e um botão.

---

# Parte 1 — IA de estudo

## Fase 0 — Conta e crédito *(ele faz, ~10 min)*

1. `console.anthropic.com` → criar conta → **Billing** → adicionar crédito (mínimo US$5).
2. **API keys** → criar uma chave. Guardar: ela só aparece uma vez.

> ⚠️ **Assinatura do claude.ai não dá acesso à API.** São cobranças separadas: a
> assinatura é do site/app, a API é por uso. Ter uma não libera a outra.

**Custo por ação, para não haver susto** (Claude Opus 5: US$5 por milhão de tokens de
entrada, US$25 de saída):

| Ação | Ordem de grandeza |
|---|---|
| Explicar um item | ~US$0,03 |
| Gerar cartões de uma anotação | ~US$0,05 |
| Buscar materiais na web | ~US$0,10 **+ a cobrança por pesquisa** |

A busca na web é cobrada **por pesquisa**, além dos tokens — conferir o valor atual na
página de preços antes de liberar essa ação. Uso pessoal normal cabe folgado em US$5/mês;
os reguladores são `output_config.effort` (`low`/`medium` rendem muito acima do que o nome
sugere no Opus 5) e trocar para `claude-haiku-4-5` no que for mecânico.

## Fase 1 — A Edge Function `ia`

**A chave nunca vai para o navegador.** A `anon key` do Supabase é pública porque o RLS a
protege; a da Anthropic não tem nada atrás dela — quem abrir o "ver fonte" gasta o seu
dinheiro.

```
index.html  ──JWT do Supabase──▶  Edge Function "ia"  ──chave──▶  API da Claude
(arquivo único,                   guarda o segredo,
 continua sem build)              lê o banco COM O SEU JWT,
                                  monta o prompt, limita o uso
```

Quatro decisões que valem a pena:

1. **O cliente manda ids, não conteúdo.** A função busca o tema/itens/anotações no banco
   usando **o JWT de quem chamou** — então o RLS continua valendo e ela só enxerga o que
   aquele usuário enxergaria. Sem isso, o cliente poderia pedir contexto de outra conta.
2. **O prompt mora no servidor.** O cliente escolhe entre ações conhecidas (`explicar`,
   `buscar_materiais`, `cartoes`, `chat`); ele não envia system prompt. Senão qualquer
   pessoa com um JWT usaria a sua chave para o que quisesse.
3. **Limite por conta.** Tabela `ia_uso(user_id, dia, chamadas, tokens_entrada,
   tokens_saida)`, PK `(user_id, dia)`, RLS "ver o meu". Serve de freio e de extrato.
4. **A IA propõe, você aceita.** Nada que ela devolve entra no banco sozinho — o mesmo
   fluxo da tela de novidades, que ele já usa e entende.

SDK no Deno: `import Anthropic from "npm:@anthropic-ai/sdk"`. Modelo `claude-opus-5`.

## Fase 2 — As três ações e o chat

| Ação | Onde fica | Ferramenta da API | O resultado vira |
|---|---|---|---|
| ✨ **buscar materiais** | topo do tema | `web_search_20260209` + `web_fetch_20260209` + structured output | linhas em `materiais` (feature que acabou de subir) |
| ✨ **gerar cartões** | na anotação 📝 e no tema | structured output | linhas em `ia_cartoes`, revisadas em `#revisar` |
| ✨ **explicar** | no item | streaming, sem ferramenta | texto na tela + botão "salvar como anotação" |
| 💬 **chat** | botão flutuante dentro do tema | streaming | conversa, guardada no `localStorage` por tema |

Detalhes que economizam depuração:

- `web_search_20260209` **já traz a filtragem embutida** — não declarar `code_execution`
  junto, ou o modelo fica com dois ambientes e se confunde. Exige Opus 4.6+/Sonnet 4.6+:
  **não funciona no Haiku**.
- `web_fetch` só abre URLs **que já estão na conversa**. Primeiro pesquisa, depois lê.
- **Structured output não combina com o recurso de `citations` de documento** (dá 400). Não
  atrapalha: no `web_search` os endereços já voltam no resultado da ferramenta.
- **O chat guarda no `localStorage`, não no banco.** É pessoal, some quando ele quiser, e
  não custa tabela nem policy. Persistir no banco fica para quando fizer falta.

**Contexto que a função monta** (é a peça que dá vantagem): tema + itens com estado ✓ +
datas de conclusão + anotações + materiais já salvos + sequência de dias.
**Corolário:** não pedir ao modelo o que o app já calcula. `calcularSequencia()` e
`progressoEm` dão o número exato de graça — mandar pronto e pedir interpretação.

## Fase 3 — Revisão espaçada (`#revisar`)

`ia_cartoes(id, user_id, item_id, pergunta, resposta, proxima_revisao, acertos, erros)`.
Quem calcula quando revisar é **o app**, não a IA: SM-2 simplificado sobre acertos/erros.
A tela mostra os cartões vencidos hoje; errou, volta amanhã; acertou, o intervalo dobra.
Fecha o ciclo com `concluido_em`, que já existe desde a Fase 2 do roadmap antigo.

## Degradação e offline (a regra do projeto)

Mesmo padrão de `temNota`/`temMateriais`: uma sondagem descobre se a função existe, e sem
ela **os botões ✨ nem aparecem**. E: a chamada de IA vai para `functions/v1`, não para
`/rest/v1` — ou seja, **não passa pelo `sbFetch()` e não entra na fila de pendências**.
Requisição de IA velha não faz sentido; com `offline === true`, os botões ficam ocultos.

---

# Parte 2 — Quadro de projeto compartilhado

Não é um clone do Notion. O valor que ele quer — trabalhar junto num projeto — está no
**quadro com tarefas, responsável, prazo e comentários ao vivo**. Blocos aninhados, rich
text e arrastar-soltar são outro produto, e é neles que o esforço explodiria.

## O truque que faz um código servir aos dois casos

```sql
projetos(id, user_id, grupo_id NULL, nome, descricao, ordem, arquivado)
```

**`grupo_id` nulo = projeto pessoal.** Compartilhar é criar um grupo e preencher o campo —
sem refazer nada. Por isso a Fase 2a entrega valor sozinha antes de existir qualquer grupo.

## Fase 2a — Projetos e tarefas (sem grupo ainda)

```sql
tarefas(id, projeto_id, titulo, detalhe, status, responsavel_id, prazo, ordem, criado_em)
  status check in ('a_fazer','fazendo','feito')
tarefa_comentarios(id, tarefa_id, user_id, autor, texto, criado_em)
```
Policies por dono, iguais às de `itens`. Tela `#projetos` + `#projeto/<id>` em colunas.

**No celular, nada de arrastar-soltar** — é ruim em tela pequena e caro de fazer. Uma
coluna por vez com os chips de filtro que já existem (`.mat-filtros`), e botões
`← mover` / `mover →` na tarefa.

## Fase 2b — Grupos

```sql
grupos(id, nome, codigo, dono_id, criado_em)
grupo_membros(grupo_id, user_id, papel, entrou_em)   -- papel: dono | editor | leitor
```

- **Entrar por código, não por e-mail.** Uma função `entrar_no_grupo(codigo)` com
  `security definer` insere a linha de membro. Evita tabela de convites, envio de e-mail e
  todo o fluxo de token — e o app não tem infraestrutura de e-mail nenhuma.
- **`eh_membro(grupo_id)` como `security definer`**, exatamente pelo mesmo motivo que
  `eh_admin()` do `supabase-evolucao.sql`: policy que consulta outra tabela com RLS entra
  em recursão e dá surpresa. A precedência já está no projeto.
- Policy de `projetos`:
  `using (user_id = auth.uid() or (grupo_id is not null and public.eh_membro(grupo_id)))`.
- **Tempo real reaproveitando o mural**: `ligarRealtimeMural()` já tem o formato certo —
  assinar `tarefas` e `tarefa_comentarios`, com o poll de 60s como rede de segurança.
- **Edição concorrente: last-write-wins**, e dito na tela. CRDT é o que o Notion faz e não
  cabe num arquivo único sem build. Com comentários e tempo real, a colisão real é rara.

⚠️ Esta é a **primeira vez que o projeto sai de "uma linha, um dono"**. Todo SQL de grupo
tem que ser conferido com o teste de sempre: entrar com a conta B e confirmar que ela
**não** vê o projeto pessoal da conta A.

---

# Parte 3 — Outras ideias que valem

| Ideia | Por que | Esforço |
|---|---|---|
| **Busca global** (campo no topo: itens, anotações, materiais) | O conteúdo já cresceu a ponto de procurar na mão incomodar. Puro cliente, o `state` já tem tudo | Baixo |
| **Modo estudo / pomodoro com registro de tempo** | Transforma a trilha de checklist em diário: "3h em Git esta semana". E dá material real para a IA montar o plano | Baixo |
| **Exportar caderno** (Markdown/PDF) | Trilha + anotações + materiais viram um documento — o resultado palpável de meses de estudo | Baixo |
| **Notificações push** | O SW já existe e ele está no Android. Precisa de VAPID + um cron no Supabase. É o que traz de volta quem parou | Médio |
| **Desfazer** | Hoje excluir tema ou item é definitivo. Uma lixeira de 30 dias (`excluido_em`) resolve | Médio |

---

# Ordem sugerida

**0 → 1 → 2 → 3 → 2a → 2b**, com as extras entrando quando der vontade.

A IA vem antes do quadro porque é o que ele pediu primeiro e o que muda o dia a dia de
estudo. Dentro da IA, a ordem é obrigatória: sem a Fase 1 nenhuma ação existe.

Cada fase termina com commit e push próprios.

## Arquivos

| Arquivo | O quê |
|---|---|
| `supabase/functions/ia/index.ts` | **Novo** — Edge Function: valida JWT, lê o banco com o JWT do usuário, monta prompt, chama a Claude, registra uso |
| `supabase-ia.sql` | **Novo** — `ia_uso`, `ia_cartoes`, policies. Só adiciona |
| `supabase-projetos.sql` | **Novo** — `projetos`, `tarefas`, `tarefa_comentarios`, e depois `grupos`, `grupo_membros`, `eh_membro()`, `entrar_no_grupo()` |
| `index.html` | Botões ✨, painel de proposta/aceite, chat do tema, `#revisar`, `#projetos` |
| `README.md` / `CLAUDE.md` | Como configurar a chave, custo, e as armadilhas novas |

## Verificação

1. `node --check` no bloco `<script>` e teste de fumaça com DOM mínimo (procedimento já
   documentado no `CLAUDE.md`), incluindo as telas novas e o caso "função de IA ausente".
2. **A função de IA recusa quem não está logado.** Chamar `functions/v1/ia` sem
   `Authorization` tem que dar 401 — o equivalente, para a IA, do teste de escrita anônima
   que já pegou uma exposição real neste projeto.
3. **O limite por conta funciona:** estourar o número de chamadas do dia e conferir que a
   função recusa em vez de continuar gastando.
4. **A IA não escreve no banco sozinha:** conferir que nenhuma proposta vira linha sem
   passar pelo aceite.
5. **Contexto respeita o RLS:** pedir explicação de um item de outra conta pelo id e
   confirmar que a função não devolve nada.
6. Depois do SQL de projetos: escrita anônima em `/rest/v1/projetos` tem que dar 401, e a
   conta B **não** pode ver o projeto pessoal da conta A.
7. Grupo ao vivo: duas janelas no mesmo projeto, mover uma tarefa numa e ver na outra.
8. Custo real: depois de um dia de uso, conferir `ia_uso` e o painel da Anthropic para
   calibrar `effort` e modelo antes de usar de verdade.
