# 📚 Trilha de Estudos — IA & Dev

Um "navegador de estudos" por temas, editável e **compartilhado**, para acompanhar sua
trilha de aprendizado em **IA, uso da Claude, Engenharia de Prompt, Lovable, Git/GitFlow,
Worktree, Claude Code e APIs**.

Continua sendo um **único arquivo `index.html`** — sem instalação, sem build, sem
dependência de CDN. A diferença é que agora ele conversa com um banco no **Supabase**.

## ✨ O que dá para fazer

- **Navegar por temas** — cada um é um estágio (01, 02, 03…) + Visão geral e A fazer.
- **Marcar itens como concluídos** → selo **✓ pronto** e texto riscado.
- **Concluir o tema inteiro** de uma vez, com um botão que também desfaz.
- **Editar, adicionar e excluir** itens.
- **Gerenciar temas** — criar, renomear, trocar emoji/resumo, reordenar e excluir.
- **Substituir a trilha inteira** importando um `data.json`.
- **Mural de recados** compartilhado com todo mundo que abrir a página.
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

As policies impedem escrita nas linhas com `user_id` nulo — **inclusive para você**, pelo
site. Isso é proposital: não existe "modo admin" escondido no HTML público.

Para curar o modelo, use o **Table Editor** ou o **SQL Editor** do Supabase, onde a chave
`service_role` do painel passa por cima do RLS. Quem criar conta a partir daí recebe a versão
nova.

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
  index.html           → o app inteiro (HTML + CSS + JS + semente do modo local)
  supabase.sql         → schema base: 3 tabelas, RLS e seed dos 8 temas
  supabase-contas.sql  → migração para contas: dono, progresso, policies e trigger
  data.json            → backup versionável (use Exportar/Importar)
  README.md            → este arquivo
  .gitignore
```

Feito para estudar com prazer. Bons estudos! 🚀
