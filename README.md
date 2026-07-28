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

## 💾 Onde cada coisa fica salva

Esta é a parte que vale entender:

| O quê | Onde | Quem vê |
|---|---|---|
| Temas e itens | Supabase (tabelas `temas` e `itens`) | **Todos** — é uma trilha só |
| Recados do mural | Supabase (tabela `mensagens`) | **Todos** |
| Seu ✓ concluído | `localStorage` do seu navegador | **Só você** |
| Apelido e tema claro/escuro | `localStorage` | Só você |

O progresso é pessoal de propósito: o tema é um fato compartilhado (existe uma trilha só),
enquanto o ✓ é uma opinião pessoal — cada pessoa está num ponto diferente. Se o progresso
fosse compartilhado, qualquer visitante marcaria itens pelos outros.

**Modo local:** se o banco não responder (sem internet, chave em branco, projeto fora do
ar), o app não quebra — ele cai no conteúdo semente embutido e avisa **"⚠ Modo local"** no
rodapé. Nesse modo as mudanças ficam só naquele navegador e o mural fica indisponível.

## 🚀 Como rodar

**Online (o normal):** acesse a URL publicada, ou dê duplo clique no `index.html`.
As duas formas funcionam — o Supabase aceita requisições de páginas abertas por `file://`.

**Do zero, num Supabase novo:**

1. Crie um projeto em [supabase.com](https://supabase.com).
2. **SQL Editor → New query** → cole o conteúdo de `supabase.sql` → **Run**.
   Ao final ele confere: deve dar 8 temas e 50 itens.
3. **Settings → API**: copie a *Project URL* e a chave *anon/publishable*.
4. Preencha as duas no topo do `index.html`, no bloco `const SB = {...}`.

> A chave `anon` é pública por desenho e pode ir para o Git — ela só diz "sou um visitante
> anônimo". Quem protege o banco são as políticas de RLS definidas no `supabase.sql`.
> A chave **`service_role`/`secret` nunca deve entrar no repositório**: ela ignora o RLS.

## 🔄 Backup e substituição em massa

- **⤓ Exportar** baixa um `data.json` com a trilha atual. Use como backup.
- **⤒ Importar** substitui a trilha **de todos** pelo conteúdo do arquivo, depois de uma
  confirmação. Exporte antes se quiser poder voltar.
- **↺ Zerar meu progresso** limpa só os seus ✓ — não toca no conteúdo compartilhado.

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
  index.html    → o app inteiro (HTML + CSS + JS + conteúdo semente do modo local)
  supabase.sql  → schema, políticas de RLS e seed dos 8 temas
  data.json     → backup versionável (use Exportar/Importar)
  README.md     → este arquivo
  .gitignore
```

Feito para estudar com prazer. Bons estudos! 🚀
