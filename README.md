# 📚 Trilha de Estudos — IA & Dev

Um "navegador de estudos" por temas, editável e **compartilhado**, para acompanhar sua
trilha de aprendizado em **IA, uso da Claude, Engenharia de Prompt, Lovable, Git/GitFlow,
Worktree, Claude Code e APIs**.

Continua sendo um **único arquivo `index.html`** — sem instalação, sem build, sem
dependência de CDN. A diferença é que agora ele conversa com um banco no **Supabase**.

## ✨ O que dá para fazer

- **Navegar por temas** — cada um é um estágio (01, 02, 03…) + Visão geral e A fazer.
- **Marcar itens como concluídos** → selo **✓ pronto · 27/jul** e texto riscado.
  A data aparece para quem está logado; deslogado o navegador guarda só o ✓.
- **Sequência e atividade** na Visão geral — dias seguidos de estudo e um mapa
  das últimas 12 semanas.
- **Concluir o tema inteiro** de uma vez, com um botão que também desfaz.
- **Editar, adicionar e excluir** itens.
- **Gerenciar temas** — criar, renomear, trocar emoji/resumo, reordenar e excluir.
- **Substituir a trilha inteira** importando um `data.json`.
- **Mural de recados** compartilhado, **em tempo real** — recado enviado numa janela aparece
  na outra na hora.
- **Anotações por item** (📝), com o que você aprendeu, links e dúvidas.
- **Materiais de estudo** (📎) por tema — cursos, vídeos, artigos e livros —, com uma
  tela que junta tudo e filtra por tipo.
- **Novidades da trilha oficial**: quando ela melhora, você escolhe o que trazer.
- **Instalar no celular** — é um PWA, abre em tela cheia pelo ícone.
- **Tema claro/escuro** e layout responsivo.

## 👤 Contas

Entrar é opcional para **ler**, obrigatório para **editar**:

| | Sem entrar | Entrando com o Google |
|---|---|---|
| Ver a trilha oficial | ✅ | ✅ |
| Ler o mural | ✅ | ✅ |
| Ter uma trilha própria e editável | ❌ | ✅ |
| Marcar ✓ | só neste navegador | na conta, em qualquer aparelho |
| Escrever no mural | ❌ | ✅ (assinado, verificado) |

Ao criar a conta, um *trigger* no banco copia a trilha oficial para você. A partir daí ela é
sua: edite, reordene, exclua — ninguém mais vê suas mudanças, e você não vê as dos outros.

## 💾 Onde cada coisa fica salva

| O quê | Onde | Quem vê |
|---|---|---|
| Trilha oficial (`user_id` nulo) | Supabase | Todos leem, **ninguém edita** pelo site |
| Sua trilha (`user_id` = você) | Supabase | **Só você** |
| Seu progresso | Supabase (tabela `progresso`) | **Só você**, em todos os seus aparelhos |
| Recados do mural | Supabase (tabela `mensagens`) | Todos leem; só contas escrevem |
| Tema claro/escuro | `localStorage` | Só você |

Quem não entrou tem o ✓ no `localStorage`. No primeiro login esse progresso é migrado para
a conta — casando por **texto do item**, porque a sua cópia tem ids diferentes dos do modelo.

**Modo local:** se o banco não responder (sem internet, chave em branco, projeto fora do
ar), o app não quebra — ele cai no conteúdo semente embutido e avisa **"⚠ Modo local"** no
rodapé. Nesse modo as mudanças ficam só naquele navegador e o mural fica indisponível.

## 🚀 Como rodar

**Online (o normal):** acesse a URL publicada, ou dê duplo clique no `index.html`.
As duas formas funcionam — o Supabase aceita requisições de páginas abertas por `file://`.

**Do zero, num Supabase novo:**

1. Crie um projeto em [supabase.com](https://supabase.com).
2. **SQL Editor → New query** → rode o `supabase.sql` (schema base, 8 temas / 50 itens).
3. Rode o `supabase-contas.sql` (contas, progresso e policies por dono).
4. **Settings → API**: copie a *Project URL* e a chave *anon/publishable* e preencha no topo
   do `index.html`, no bloco `const SB = {...}`.

**Login com Google:**

5. No [Google Cloud Console](https://console.cloud.google.com): *APIs e Serviços → Tela de
   permissão OAuth* (Externo) → *Credenciais → ID do cliente OAuth → Aplicativo da Web*.
   Em **URIs de redirecionamento autorizados**, use:
   `https://<SEU-REF>.supabase.co/auth/v1/callback`
6. No Supabase: *Authentication → Providers → Google* → habilitar e colar Client ID e Secret.
7. *Authentication → URL Configuration*: **Site URL** e **Redirect URLs** apontando para a URL
   publicada do site.

> A tela de permissão nasce em modo **Teste** e só deixa entrar contas listadas em *Usuários
> de teste*. Para abrir a qualquer pessoa, publique a tela de consentimento.

> A **Chave secreta do cliente** fica só no painel do Supabase — nunca no repositório. É ela
> que o Supabase usa para trocar o código do Google por uma sessão, e não pode passar pelo
> navegador.

> A chave `anon` é pública por desenho e pode ir para o Git — ela só diz "sou um visitante
> anônimo". Quem protege o banco são as políticas de RLS definidas no `supabase.sql`.
> A chave **`service_role`/`secret` nunca deve entrar no repositório**: ela ignora o RLS.

## 🔄 Backup e substituição em massa

- **⤓ Exportar** baixa um `data.json` com a trilha que está na tela. Use como backup.
- **⤒ Importar** substitui a **sua** trilha pelo conteúdo do arquivo, depois de uma
  confirmação. A trilha oficial e a dos outros não são afetadas.
- **↺ Zerar meu progresso** limpa só os seus ✓.

## 🛠️ Como editar a trilha oficial

Quem estiver na tabela `admins` ganha o botão **🛠 editar modelo oficial** na home. Ele
mostra a trilha oficial no lugar da sua, com uma faixa amarela no topo para você nunca
confundir as duas. Sair é o botão **↩ voltar à minha trilha**.

Entrar para a lista de admins **não acontece pelo site** — não existe policy de escrita em
`admins`. É uma linha no SQL Editor do Supabase:

```sql
insert into public.admins (user_id)
select id from auth.users where email = 'seu-email@gmail.com';
```

No modo modelo o progresso some da tela de propósito: os ✓ são de itens da *sua* cópia, que
têm outros ids. Melhor nenhum ✓ do que ✓ no item errado.

## ✨ Novidades do modelo

Sua trilha é uma cópia e **não muda sozinha**. Quando a oficial ganha um tema ou um item, a
home mostra uma faixa e a tela `#novidades` lista o que falta, com seleção:

- **Adicionar selecionados** copia para a sua trilha, sem tocar no seu progresso nem nas
  suas anotações.
- **Dispensar selecionados** é definitivo: aquilo não é mais oferecido, nem depois do F5. É
  o que impede um tema que você apagou de propósito de reaparecer para sempre.

Cada linha copiada guarda de qual linha do modelo nasceu (`origem_id`) — é assim que o app
sabe o que você já tem.

## 📝 Anotações

Cada item tem um botão **📝**. A nota fica na **sua** cópia, aparece abaixo do item e o botão
ganha um ponto quando existe nota, para você não precisar abrir para descobrir. Limite de
2000 caracteres, garantido pelo banco.

## 📎 Materiais de estudo

Cada tema tem uma seção **📎 Materiais e links** no fim da página: guarde ali o curso, o
vídeo, o artigo ou o livro que ajudou naquele assunto. Cada material tem **título, link,
tipo** (vídeo/curso/artigo/livro/outro) e uma **observação** — o "por que salvei isso".

O card **📎 Materiais** na home abre a tela que junta os materiais de todos os temas,
agrupados na ordem da trilha e com filtro por tipo.

Materiais são da **sua** cópia, entram no modelo oficial (modo admin) e chegam a quem já
tem conta como **novidade**, igual a temas e itens.

> 🔒 Só endereços `http` e `https` viram link clicável. Qualquer outro esquema (como
> `javascript:`) aparece como texto e não abre — é o que impede um link malicioso de
> executar código na página.

## ✨ IA de estudo (opcional, e desligada por padrão)

O app pode usar a Claude para **buscar materiais**, **explicar um item**, **gerar cartões
de revisão** e **conversar sobre o tema** — sempre com o contexto da *sua* trilha: o que
você concluiu, quando, o que anotou e o que já salvou.

Enquanto não estiver configurada, **os botões ✨ nem aparecem**. Nada quebra.

### Como ligar

> ⚠️ **Assinatura do claude.ai não serve.** A assinatura é do site/app; a API é cobrada
> por uso, à parte. Ter uma não libera a outra.

1. **Conta e crédito** — `console.anthropic.com` → **Billing** → adicionar crédito
   (mínimo US$5) → **API keys** → criar a chave. Ela só aparece uma vez.
2. **Banco** — rodar o `supabase-ia.sql` no SQL Editor.
3. **Função** — no terminal, dentro da pasta do projeto:
   ```bash
   supabase functions deploy ia
   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
   ```

### Quanto custa

Ordem de grandeza por ação (Claude Opus 5, US$5 por milhão de tokens de entrada e US$25 de
saída):

| Ação | ~custo |
|---|---|
| Explicar um item | US$0,03 |
| Gerar cartões de uma anotação | US$0,05 |
| Buscar materiais na web | US$0,10 **+ a cobrança por pesquisa** |

A busca na web é cobrada **por pesquisa**, além dos tokens. Uso pessoal cabe folgado em
US$5/mês. Há um **limite de 40 usos por dia por conta**, e a tabela `ia_uso` guarda o
extrato — dá para conferir o gasto antes de a fatura chegar.

### O que a IA não faz

- **Não vê a chave.** Ela mora como *secret* na Edge Function; o navegador nunca a recebe.
- **Não lê a trilha de outra pessoa.** A função consulta o banco com o **seu** login, então
  o RLS vale igual.
- **Não escreve no banco.** Tudo que ela devolve é proposta: você aceita ou dispensa, do
  mesmo jeito que já faz com as novidades do modelo.

## 📱 Instalar no celular

O app é um PWA. No Chrome do Android: menu → **Instalar app**. No iPhone, Safari →
**Compartilhar** → **Adicionar à Tela de Início**.

Instalado, ele abre em tela cheia, sem barra de navegador. O service worker guarda o
**casco** (HTML, ícones, manifest e o SDK do Supabase) — **dados nunca**: toda chamada ao
banco passa direto para a rede. E o documento é *network-first*, então um `git push` novo
aparece no próximo abrir, sem "por que meu app não atualizou?".

### Sem conexão

O celular costuma abrir o app antes de o rádio acordar. Para isso não virar problema:

- a carga **tenta três vezes** antes de assumir que está sem rede;
- sem rede, você vê **a sua trilha como estava na última vez** (não a trilha genérica
  embutida no arquivo), com uma faixa no topo dizendo de quando é;
- o que você **marcar, editar, anotar ou criar** entra numa fila e **sobe sozinho** quando
  a conexão volta — a faixa mostra quantas alterações estão esperando;
- voltando a rede (ou trazendo o app para a frente), ele reconecta e envia sozinho; dá
  para forçar no botão **↻ Tentar agora**.

## 🌿 Fluxo com o git

```bash
git add .
git commit -m "estudos: descricao da mudanca"
git push
```

O conteúdo da trilha não precisa mais de commit — ele vive no banco. O `data.json` do
repositório é só backup/semente.

## 🗂️ Estrutura

```
estudos-ia/
  index.html             → o app inteiro (HTML + CSS + JS + semente do modo local)
  supabase.sql           → schema base: 3 tabelas, RLS e seed dos 8 temas
  supabase-contas.sql    → migração para contas: dono, progresso, policies e trigger
  supabase-evolucao.sql  → realtime do mural, admins, novidades do modelo e notas
  supabase-materiais.sql → materiais de estudo por tema
  supabase-ia.sql        → extrato/freio de uso da IA e cartões de revisão
  supabase/functions/ia/ → Edge Function: o único lugar com a chave da Anthropic
  manifest.json          → PWA: nome, cores e ícones
  sw.js                  → service worker (só o casco; nunca os dados)
  icon-192.png           → ícone do app
  icon-512.png           → ícone do app (e maskable)
  data.json              → backup versionável (use Exportar/Importar)
  README.md              → este arquivo
  .gitignore
```

Os `.sql` rodam **em ordem** e só uma vez cada: `supabase.sql` → `supabase-contas.sql` →
`supabase-evolucao.sql` → `supabase-materiais.sql` → `supabase-ia.sql`. Nunca voltar
atrás — o primeiro recria policies abertas, e o terceiro redefine o trigger de cadastro
sem a cópia dos materiais.

Feito para estudar com prazer. Bons estudos! 🚀
