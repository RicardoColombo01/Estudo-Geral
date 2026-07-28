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
- Data no selo do item, sequência de dias e mapa de atividade de 12 semanas *(Fase 2,
  commit `6438a72` — no ar, ainda não conferido pelo Ricardo no navegador)*

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
| Rede (porta única) | `sbFetch()`, `salvarNoServidor()` |
| Auth | `sbClient` (SDK), `entrar()`, `sair()`, `logado()`, `podeEditar()`, `meuNome()` |
| Carga | `load()`, `carregarTrilha()`, `carregarProgresso()`, `recarregar()` |
| Progresso | `progresso` (Set), `marcarItem()`, `aplicarProgresso()`, `sincProgresso()` |
| Datas | `progressoEm` (Map id→ISO), `chaveDia()`, `diasDeEstudo()`, `calcularSequencia()`, `selo()` |
| Capacidades | `detectarColunas()`, `verificarAdmin()` — flags `temNota`, `temOrigem`, `souAdmin` |
| Modelo oficial | `modoModelo`, `faixaModelo()`, ação `modo-modelo` |
| Novidades | `carregarNovidades()`, `adicionarNovidades()`, `dispensarNovidades()`, `viewNovidades()` |
| Notas | `blocoNota()`, `acoesItem()`, `focusNota()`, ramo `[data-form-nota]` do submit |
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
| 3 | mural em tempo real | ✅ código no ar; **falta rodar a seção 3 do SQL** |
| 4 | admin do modelo oficial | ✅ código no ar; **falta rodar a seção 4 do SQL** (e pôr o e-mail dele) |
| 5 | puxar novidades do modelo | ✅ código no ar; **falta rodar a seção 5 do SQL** |
| 6 | anotações por item | ✅ código no ar; **falta rodar a seção 6 do SQL** |
| 7 | PWA | ✅ 2026-07-28, completa (não depende de SQL) |

⚠️ **O `supabase-evolucao.sql` ainda não foi rodado no banco** (conferido em 2026-07-28:
`admins` e `modelo_dispensado` dão 404, `nota` e `origem_id` dão 400). Até rodar, cada
recurso fica desligado sozinho — ver "degradação" abaixo.

> ⚠️ **NÃO EXECUTAR NENHUMA FASE SEM O RICARDO AUTORIZAR.** Ele pediu explicitamente para
> deixar pronto e só realizar quando voltar e mandar. Uma fase por vez, commit próprio.

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
