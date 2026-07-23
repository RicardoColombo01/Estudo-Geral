# 📚 Trilha de Estudos — IA & Dev

Um "navegador de estudos" por abas, editável, para acompanhar sua trilha de
aprendizado em **IA, uso da Claude, Engenharia de Prompt, Lovable, Git/GitFlow,
Worktree, Claude Code e APIs**.

É um **único arquivo `index.html`** — sem instalação, sem build. Abre com duplo
clique e funciona offline.

## ✨ O que dá para fazer

- **Navegar por abas** — cada tema é um estágio (01–08) + uma aba de **Visão geral**.
- **Marcar itens como concluídos** → aparece o selo **✓ pronto** e o texto é riscado.
- **Editar, adicionar e excluir** itens em cada estágio.
- **Ver o progresso** no painel de Visão geral (anel geral, barras por estágio,
  pendentes e cronograma de 10 semanas).
- **Tema claro/escuro** e layout responsivo.

## 🚀 Como usar

1. Dê **duplo clique** em `index.html` (abre no navegador padrão).
2. Marque itens, edite, adicione. **Tudo salva sozinho** no navegador (localStorage).
3. Para guardar/versionar seus dados, clique em **⤓ Exportar** — baixa um
   `data.json`. Substitua o `data.json` do projeto por esse e comite (veja abaixo).
4. Para carregar dados de volta (ex: em outro computador), use **⤒ Importar**.
5. **↺ Restaurar** volta ao conteúdo original.

> Observação: os edits vivem no navegador. O `data.json` do repositório é a
> "semente" versionável — sincronize-o com Exportar/Importar quando quiser
> registrar o progresso no git.

## 🌿 Conectar ao git / GitHub

O repositório local já vem inicializado. Para enviar ao GitHub:

```bash
# 1. Crie um repositório vazio no GitHub (sem README), copie a URL.

# 2. No terminal, dentro desta pasta:
git remote add origin https://github.com/SEU_USUARIO/estudos-ia.git
git branch -M main
git push -u origin main
```

Fluxo do dia a dia, depois de editar seus estudos:

```bash
# Exporte o data.json pelo app (botão Exportar) e substitua o arquivo daqui, então:
git add data.json
git commit -m "estudos: atualiza progresso"
git push
```

## 🗂️ Estrutura

```
estudos-ia/
  index.html   → o app inteiro (HTML + CSS + JS + conteúdo semente)
  data.json    → mesma semente, versionável (use Exportar/Importar)
  README.md    → este arquivo
  .gitignore
```

Feito para estudar com prazer. Bons estudos! 🚀
