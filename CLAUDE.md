# CLAUDE.md — Trilha de Estudos IA & Dev

Contexto para retomar este projeto sem precisar redescobrir nada.
Escrito referenciando **nomes de função**, não números de linha — linha muda a cada edição.

## O que é

App pessoal de acompanhamento de estudos. **Um único arquivo** `index.html`
(HTML + CSS + JS vanilla, sem build, sem empacotador), rotas por hash, publicado em
https://ricardocolombo01.github.io/Estudo-Geral/ via GitHub Pages (`main` / root).

Backend: **Supabase** (projeto `estudos-ia`, ref `zezzpdhjjgqavtlxmgsp`, São Paulo).
Login: **Google OAuth**. Dono: RicardoColombo01.

## Estado atual — tudo isto está no ar e testado

- Contas Google; cada usuário tem a **própria cópia** editável da trilha
- Progresso por conta, sincronizado entre aparelhos
- Mural de recados compartilhado, append-only, autor verificado
- Visitante sem login: lê a trilha oficial e o mural, não escreve nada
- Gestão de temas: criar, editar, reordenar, excluir, substituir por JSON
- Concluir/desmarcar um tema inteiro
- Data no selo do item, sequência de dias e mapa de atividade de 12 semanas *(Fase 2)*
- Mural em tempo real, modo admin do modelo, novidades do modelo, anotações por item e
  PWA instalável *(Fases 3–7; o Ricardo confirmou em 2026-07-28 que rodou o
  `supabase-evolucao.sql` e instalou o app no celular)*
- **Materiais de estudo** por tema + tela `#materiais` *(no ar; depende do
  `supabase-materiais.sql`, que ele ainda precisa rodar)*

## A regra que organiza tudo

Uma coluna `user_id` em `temas`, `itens`, `mensagens` e `progresso`:

- **`user_id IS NULL`** → linha do **modelo oficial**: todos leem, ninguém escreve pela API
- **`user_id = auth.uid()`** → é do dono: só ele lê e só ele escreve

Três decisões fazem o cliente quase não precisar saber disso:

1. `alter column user_id set default auth.uid()` — o banco carimba o dono sozinho, então
   nenhum `POST` do cliente precisa mandar `user_id`.
2. Um trigger em `auth.users` (`criar_trilha_do_usuario`, `security definer`, usa `new.id`)
   copia o modelo no cadastro.
3. `sbFetch()` manda `Bearer <access_token da sessão || anon key>`. Deslogado enxerga o
   modelo, logado enxerga a própria cópia — **a mesma chamada, crachá diferente**.

## Mapa do `index.html`

| Camada | Funções |
|---|---|
| Rede (porta única) | `sbFetch()`, `cabecalhosSb()`, `salvarNoServidor()`, `novoId()` |
| Offline | `fila`/`enfileirar()`/`enviarFila()`, `guardarRetrato()`/`lerRetrato()`, `tentarReconectar()`, `faixaRede()` |
| IA | `chamarIA()`, `iaStream()`, `detectarIA()`, `podeUsarIA()`, `painelIA()`, `blocoChat()`, `viewRevisar()` |
| Auth | `sbClient` (SDK), `entrar()`, `sair()`, `logado()`, `podeEditar()`, `meuNome()` |
| Carga | `load()`, `carregarTrilha()`, `carregarProgresso()`, `recarregar()` |
| Progresso | `progresso` (Set), `marcarItem()`, `aplicarProgresso()`, `sincProgresso()` |
| Datas | `progressoEm` (Map id→ISO), `chaveDia()`, `diasDeEstudo()`, `calcularSequencia()`, `selo()` |
| Capacidades | `detectarColunas()`, `verificarAdmin()` — flags `temNota`, `temOrigem`, `souAdmin` |
| Modelo oficial | `modoModelo`, `faixaModelo()`, ação `modo-modelo` |
| Novidades | `carregarNovidades()`, `adicionarNovidades()`, `dispensarNovidades()`, `viewNovidades()` |
| Notas | `blocoNota()`, `acoesItem()`, `focusNota()`, ramo `[data-form-nota]` do submit |
| Materiais | `TIPOS_MAT`, `urlSegura()`, `dominio()`, `blocoMateriais()`, `linhaMaterial()`, `viewMateriais()`, `acharMaterial()` |
| Mural | `ligarRealtimeMural()`, `desligarRealtimeMural()`, `ajustarMural()`, `digitandoNoMural()` |
| Migrações | `migrarProgressoAntigo()`, `migrarProgressoParaConta()` — casam por **texto** |
| Telas | `viewHome()`, `viewStage()`, `viewAfazer()`, `viewResumo()`, `viewMural()`, `render()` |
| Ações | um `click` delegado com `switch(action)`, um `submit` com 3 ramos |

**Degradação (a regra que permitiu publicar o código antes do SQL):**
`detectarColunas()` e `verificarAdmin()` sondam o banco uma vez por sessão e ligam/desligam
cada recurso. Sem `nota` não aparece o botão 📝; sem `origem_id` não há novidades; sem
`admins` ninguém é admin. Por isso a ordem entre rodar o SQL e dar push **não importa** — não
existe janela com o site quebrado. Qualquer recurso novo que dependa de schema deve seguir
esse mesmo padrão.

**Como o app se vira sem rede (corrigido em 2026-07-28):**
`sbFetch()` distingue *não chegou ao servidor* (fetch rejeita) de *o servidor recusou*
(`r.ok` falso, e o erro sai com `.status`). Só o primeiro caso vira pendência na fila —
repetir um 403 mil vezes não conserta nada. `load()` tenta 3 vezes antes de desistir,
porque abrir o app instalado é justamente quando o rádio do celular ainda está acordando.
Sem rede, a tela vem do **retrato** (última cópia boa, chaveada por usuário) e nunca da
SEED. Os ids das linhas novas nascem no cliente (`novoId()`), que é o que permite criar
coisas offline.

**Invariantes que devem ser preservadas:**

- `sbFetch()` é a **única** saída de rede para dados. Autenticação nova entra ali, não espalhada.
- O `Set` `progresso` é a única fonte da verdade do ✓. `aplicarProgresso()` projeta na tela.
- `state.abas[].id` é o **slug**, não o uuid — é o que vira a rota `#git`. O uuid mora em `dbId`.
- Item e tema novos nascem só na memória (`novo: true`) e só viram linha no `submit`.
- `marcarTodosDoTema()` foi escrita pelo Ricardo. Não reescrever sem perguntar; o handler
  compara o Set antes/depois em vez de assumir o que ela faz.

## Arquivos

| Arquivo | Papel |
|---|---|
| `index.html` | O app inteiro |
| `supabase.sql` | Schema base. ⛔ **Nunca rodar depois do `supabase-contas.sql`** — recria policies abertas |
| `supabase-contas.sql` | Migração para contas: dono, `progresso`, policies, trigger |
| `supabase-evolucao.sql` | Fases 3–6: realtime, `admins`, `origem_id`+`modelo_dispensado`, `nota`. Só adiciona policies |
| `supabase-materiais.sql` | Tabela `materiais` (links por tema) + trigger de cadastro copiando materiais |
| `supabase-ia.sql` | `ia_uso` (freio + extrato) e `ia_cartoes`. `registrar_uso_ia()` só para a service_role |
| `supabase/functions/ia/index.ts` | Edge Function. **O único lugar com a chave da Anthropic** |
| `manifest.json`, `sw.js`, `icon-*.png` | PWA. O `sw.js` nunca intercepta `supabase.co` |
| `data.json` | Backup versionável (está com a semente antiga; regerar pelo Exportar) |

## Armadilhas que já custaram tempo aqui

- **RLS combina policies com OU.** Uma permissiva sobrevivente (`using (true)`) anula todas
  as restritivas — sem erro, sem log, com o painel mostrando "RLS enabled" em verde.
  Todo SQL novo deve **só adicionar** policies. A migração derruba varrendo `pg_policies`,
  nunca por nome fixo.
- **Nem toda resposta de sucesso do PostgREST tem corpo.** `Prefer: return=minimal` devolve
  **201 vazio**, não 204. Decidir parsear JSON pelo status quebra; testar o corpo.
- **Resetar tem dois lados.** O SQL não alcança o `localStorage`, e é ele que guarda o
  progresso de quem está deslogado. "O reset não funcionou" quase sempre é isso.
- **OAuth e rota em hash brigam.** `flowType:"pkce"` é obrigatório: o fluxo implícito
  devolveria `#access_token=` e atropelaria o `route()`.
- **SDK via `<script src>` UMD, nunca `type="module"`** — módulo ES quebra o `file://`, e o
  duplo clique no arquivo precisa continuar funcionando.
- **A ação `ping` existe para não pagar só para descobrir se dá.** Ela não chama a IA e não
  gasta token: devolve se a chave está configurada e quanto do limite do dia resta. Sem ela,
  o único jeito de saber se a IA funciona seria tentar uma ação de verdade.
- **Chamada de IA não passa pelo `sbFetch()`.** Vai para `functions/v1`, não `/rest/v1` — e
  por isso **não entra na fila de pendências**, o que é intencional: pergunta guardada para
  amanhã não faz sentido. `podeUsarIA()` esconde os botões quando `offline`.
- **A IA propõe, o usuário aceita.** Nada que ela devolve vira linha sem passar por uma
  caixinha marcada. E o `item_id` que ela sugere é conferido contra os itens reais do tema
  antes de gravar — id inventado faria o banco recusar o lote inteiro.
- **A chave da Anthropic NUNCA pode ir para o `index.html`.** A anon key do Supabase é
  pública porque o RLS a protege; a da Anthropic não tem nada atrás dela — quem abrir o
  "ver fonte" gasta o dinheiro dele. Ela vive só como secret da Edge Function.
- **Na Edge Function, dois clientes com papéis diferentes.** O contexto é lido com o **JWT
  de quem chamou** (o RLS continua valendo, e ninguém pede a trilha de outra conta); o
  contador de uso é escrito com a **service_role** (se o usuário pudesse escrever em
  `ia_uso`, zeraria o próprio freio). Trocar um pelo outro abre um buraco em silêncio.
- **`revoke` sem `grant` depois derruba a service_role.** `revoke all ... from public` tira
  a permissão padrão de todo mundo, inclusive dela — por isso o `grant execute ... to
  service_role` logo em seguida não é redundância.
- **Uma falha de rede na abertura envenenava a sessão inteira.** `detectarColunas()`
  marcava `colunasDetectadas = true` antes de sondar, então "sem rede" virava "esta coluna
  não existe" e materiais/notas/novidades ficavam desligados até recarregar a página.
  Sondagem que não fala com o servidor agora devolve `null` e não trava nada.
- **`persist()` só grava no modo offline.** Era por isso que abrir sem rede mostrava a
  SEED: não havia nada guardado do usuário. Quem cuida disso agora é o `guardarRetrato()`,
  chamado em toda carga e toda escrita bem-sucedida.
- **URL digitada por usuário é vetor de XSS.** `esc()` protege as aspas do atributo, mas
  não o **esquema**: `javascript:...` num `href` executa. Todo endereço que virar link
  passa por `urlSegura()`, que só aceita `http:` e `https:` — o resto vira texto. Vale
  para qualquer campo de link novo daqui para a frente.
- **`supabase-materiais.sql` redefine `criar_trilha_do_usuario()`.** Rodar o
  `supabase-evolucao.sql` depois dele faz contas novas nascerem sem os materiais — sem
  erro nenhum, só faltando. A ordem dos quatro `.sql` é sempre para frente.
- **Admin também pode apagar o modelo.** Desde a Fase 4 o RLS autoriza o admin a escrever nas
  linhas com `user_id is null`. Todo `DELETE` em massa precisa de filtro **explícito** de dono
  — `substituirTrilha()` usava `id=not.is.null` confiando no RLS e apagaria a trilha oficial
  de todo mundo junto com a sua.
- **`user_id` tem `default auth.uid()`.** Ao criar linha do modelo, mandar `user_id: null`
  explícito, senão o default carimba o admin como dono e a linha vira a cópia dele.
- **`concluido_em` é `timestamptz`, guardado em UTC.** Agrupar conclusão por dia tem que usar
  o fuso do aparelho (`chaveDia()`): estudar às 21h em SP já é o dia seguinte em UTC, e
  contar por UTC parte uma noite de estudo em dois dias — sequência inflada, sem erro nenhum.
- **O upsert do progresso preserva a data.** `Prefer: resolution=merge-duplicates` manda só
  `item_id` e `user_id`, então o `ON CONFLICT` não toca em `concluido_em`. Por isso
  `marcarItem()` só grava data otimista quando ainda não existe uma — sobrescrever faria a
  tela discordar do banco até o próximo F5.

## Verificação obrigatória depois de mexer em policy

O teste que vale não é "a funcionalidade funciona?", é **"o que deveria falhar, falha?"**.
Foi assim que uma exposição real foi descoberta neste projeto:

```powershell
$k = "<anon key>"; $base = "https://zezzpdhjjgqavtlxmgsp.supabase.co/rest/v1"
$h = @{ apikey=$k; Authorization="Bearer $k"; "Content-Type"="application/json" }
# TEM que dar 401:
Invoke-RestMethod -Uri "$base/temas" -Method Post -Headers $h -Body '{"slug":"__x__","nome":"x","ordem":99}'
```

Checar sintaxe do JS sem abrir navegador: extrair o último bloco `<script>` e `node --check`.

## Roadmap

**7 melhorias aprovadas e detalhadas** em
`C:\Users\ricar\.claude\plans\al-m-disso-quero-que-imperative-allen.md`:

| Fase | | Estado |
|---|---|---|
| 1 | publicar consentimento do Google | pendente — **só o Ricardo faz**, no Google Cloud Console |
| 2 | datas e sequência | ✅ 2026-07-28, commit `6438a72` |
| 3 | mural em tempo real | ✅ 2026-07-28 |
| 4 | admin do modelo oficial | ✅ 2026-07-28 |
| 5 | puxar novidades do modelo | ✅ 2026-07-28 |
| 6 | anotações por item | ✅ 2026-07-28 |
| 7 | PWA | ✅ 2026-07-28, instalado no celular |

Fases 2 a 7 estão no ar **e o `supabase-evolucao.sql` foi rodado** (ele confirmou:
"nada travou, e o aplicativo instalou").

**Depois disso** — plano aprovado em `C:\Users\ricar\.claude\plans\replicated-conjuring-lagoon.md`:

| | Estado |
|---|---|
| Materiais de estudo | ✅ no ar; **falta ele rodar o `supabase-materiais.sql`** |
| App instalado offline (retry, retrato, fila) | ✅ 2026-07-28, commit `a250216` |
| **IA — Fase 1** (SQL + Edge Function) | ✅ escrita; **bloqueada na chave da Anthropic, que ele ainda não tem** |
| **IA — Fase 2** (botões ✨, painel de aceite, chat do tema) | ✅ escrita; some da tela até a função responder ao `ping` |
| **IA — Fase 3** (`#revisar`, revisão espaçada) | ✅ escrita |

### Estado em 2026-07-29 — tudo pronto, parado só na chave paga

Infraestrutura **inteira no ar e conferida**:

| | |
|---|---|
| CLI do Supabase | instalada em `C:\Users\ricar\supabase-cli`, no PATH, Ricardo logado |
| Função `ia` | publicada; 401 anônimo **com a nossa mensagem** (prova que é o nosso código, não o gateway) |
| `supabase-materiais.sql` e `supabase-ia.sql` | rodados; `materiais`, `ia_uso` e `ia_cartoes` existem |
| Escrita anônima | 401 em todas |
| Botões ✨ e bolha 💬 | aparecem na tela |

**O que falta é só uma coisa:** a conta da Anthropic não tem crédito, e o Ricardo disse
que **não consegue pôr os US$5 mínimos**. A API responde `invalid x-api-key` /
`credit balance is too low`, e o app mostra o erro dentro do painel — sem quebrar nada.

> ⚠️ **A decisão dele: adaptar a função para o Gemini gratuito, e SÓ quando ele autorizar.**
> Não começar essa migração sozinho, e **não sugerir de novo pôr crédito na Anthropic** —
> ele já respondeu que não dá. O que a troca custa: perde a busca na web integrada, o
> formato estruturado fica menos garantido, e as explicações caem um degrau.
| Quadro de projeto (pessoal → grupo) | ⏳ desenhado no plano, nada escrito |

O plano tem o desenho completo das duas partes e uma lista de outras ideias (busca global,
pomodoro, exportar caderno, push, desfazer). Vale ler antes de propor qualquer uma.

> ⚠️ **NÃO SEGUIR PARA A PRÓXIMA FASE SEM O RICARDO AUTORIZAR.** Uma fase por vez,
> commit próprio.

## Como o Ricardo trabalha

- **Uma etapa por vez**, com comandos prontos para colar. Ele diz "próxima etapa".
- Explicar o **porquê** junto com o quê — ele usa isso para defender o próprio trabalho.
- Diff mínimo: preferir migrar a camada de dados a reescrever UI que já funciona.
- Fechar cada bloco com um **resumo em lista** do que mudou.

## Ambiente (Windows, PowerShell 5.1)

- `git commit -F <arquivo>` — here-string com aspas duplas quebra ao passar para o git
- **Não** usar `2>&1` em comando nativo: vira `NativeCommandError` mesmo com exit 0
- `Invoke-RestMethod` às vezes colapsa arrays JSON; preferir `Invoke-WebRequest` e ler
  `.Content` cru
- Ao passar SQL para o SQL Editor, abrir no Notepad — o clipboard já se perdeu no caminho
