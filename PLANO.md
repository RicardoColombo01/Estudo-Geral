# Plano — o que vem depois da IA

Escrito em 2026-07-29, logo depois de a IA entrar no ar com o Gemini (commit `7e0289c`).
Complementa `planos/2026-07-28-ia-e-quadro-de-projeto.md`, que segue valendo para o quadro de
projeto — aqui só o que mudou de leitura desde então, mais os itens novos.

> **Este é o arquivo ativo.** Ideia nova se escreve aqui. Os arquivos em `planos/` são
> histórico: valem como registro do que foi decidido e por quê, e o de 2026-07-28 ainda
> guarda o desenho completo do quadro de projeto, que não foi construído.

## Onde o projeto está

A trilha está completa como **registro** (temas, itens, progresso com datas, anotações,
materiais, modelo oficial, PWA offline) e agora também **ajuda a estudar**: explicar item,
sugerir materiais, gerar cartões, chat por tema e `#revisar`.

O que a migração para o Gemini mudou no desenho, e que este plano leva em conta:

- **Não há busca na web.** O tier gratuito não inclui grounding com Google Search. A ação
  `buscar_materiais` funciona pela memória do modelo e é instruída a **deixar o endereço
  vazio em vez de inventar link**. Isso cria um vão novo — título sem link — que o item 2
  abaixo fecha.
- **A cota é da chave, não da conta.** `LIMITE_DIA` caiu para 12. Consequência de produto:
  o número passou a ser pequeno o suficiente para o usuário encostar nele, então mostrar
  quanto resta deixou de ser detalhe (ver "Mais ideias", nº 1).
- **Ação nova de IA é barata.** Edge Function, montador de contexto, freio e painel de
  aceite já existem. Uma ação nova é *um prompt, um esquema e um botão* — o que muda a
  relação custo/benefício de várias ideias abaixo.

---

## Item 1 — Fechar a Fase 3: exercitar cartões e `#revisar`

**Por que primeiro:** está escrito desde 2026-07-28 e **nunca executou uma única vez** —
não podia, sem chave funcionando. Foram testados chat, explicar e materiais. Geração de
cartões e a tela de revisão continuam sendo código não executado, que é código com bug até
prova em contrário. Custo: zero linha, só clicar.

### Roteiro de teste

1. Num tema que tenha **anotações** (📝), clicar em **✨ gerar cartões de revisão**.
   O valor está nas anotações, não no assunto — tema sem anotação tende a devolver pouco.
2. Desmarcar um dos cartões propostos e aceitar o resto. Conferir que **só os marcados**
   viraram linha (a regra "a IA propõe, o usuário aceita").
3. Abrir `#revisar`. Os cartões nascem com `proxima_revisao` = hoje, então devem aparecer.
4. **Mostrar resposta → "Sabia ✓"**: o cartão sai da fila e o intervalo dobra
   (`intervalo_dias * 2`, mínimo 1).
5. **"Ainda não sei"** noutro cartão: o intervalo volta para 1 dia.
6. Recarregar a página. Os revisados hoje **não** devem voltar; a conta é feita por
   `proxima_revisao=lte.<hoje>`.

### Três verificações que nunca foram possíveis

Estão na lista do plano antigo (itens 3, 4 e 5) e dependiam de a IA responder:

| | O que é | Como |
|---|---|---|
| Freio | O limite por conta recusa em vez de continuar gastando | Gastar as 12 chamadas do dia e conferir a mensagem, não um erro do Google |
| Aceite | Nada da IA vira linha sem caixinha marcada | Já coberto pelo passo 2 acima |
| **RLS no contexto** | Pedir contexto de tema de **outra conta** não devolve nada | Ver abaixo |

O terceiro é o que a cultura deste projeto chama de teste que vale: **o que deveria falhar,
falha?** Foi assim que uma exposição real foi descoberta aqui.

Pela leitura do código ele deve passar — `montarContexto()` usa `supaUsuario`, o cliente
montado com o **JWT de quem chamou**, então o RLS filtra e a função responde
`404 Tema não encontrado nesta conta`. Mas isso é raciocínio, não teste.

> **Dependência honesta:** a versão forte do teste exige uma **segunda conta Google**. A
> versão fraca (mandar um uuid inventado e conferir o 404) prova pouco, porque não distingue
> "o RLS filtrou" de "esse id não existe". Vale criar a segunda conta agora: ela é
> obrigatória de qualquer forma para a Fase 2b do quadro de projeto, onde o teste é
> "a conta B **não** vê o projeto pessoal da conta A".
>
> Cuidado ao ler o resultado: tema do **modelo oficial** (`user_id is null`) é público de
> propósito — devolver contexto dele é o comportamento certo, não vazamento. O teste tem que
> usar um tema que seja **cópia privada** da outra conta.

---

## Item 2 — Legibilidade do texto da IA no celular

**Reclamação dele, 2026-07-29:** *"o texto está em uma coluna pequena, muito difícil de ler"*.
Não é impressão nem questão de gosto — é um defeito de layout com número.

### A causa

`.item` é um grid de **três** colunas: `26px 1fr auto`.

- coluna 1 (`26px`) — o ✓
- coluna 2 (`1fr`) — o `.item-body`, e é **dentro dele** que a `.ia-caixa` renderiza
- coluna 3 (`auto`) — o `.item-actions`

Os botões têm `white-space:nowrap`, então a coluna `auto` assume a largura de conteúdo e
**se recusa a encolher**. E `.item-body{min-width:0}` permite que o `1fr` seja esmagado até
zero. O resultado é que os botões ficam com o que precisam e o texto fica com o resto.

Contas para um celular de 360px de largura:

| | |
|---|---|
| largura da tela | 360px |
| − `padding` do `.wrap` no mobile (15px × 2) | 330px |
| − `padding` do `.item` (16px × 2) | 298px |
| − coluna do ✓ (26px) + dois `gap` de 14px | 244px |
| − `.item-actions`: `✨` + `📝` + `editar` + `excluir` ≈ 198px | **≈ 46px** |

**≈ 46px para uma explicação de 300 palavras.** Uma ou duas letras por linha.

Por que passou: no desktop o `1fr` recebe folga de sobra, então o defeito **não existe na
tela de quem desenvolve**. O grid nunca quebra nem dá erro — ele silenciosamente entrega ao
texto o que sobrou, e o que sobrou é quase nada.

### A correção — CSS puro, no `@media (max-width:640px)` que já existe

```css
.item{grid-template-columns:26px 1fr}
.item-actions{grid-column:1 / -1; justify-content:flex-end; flex-wrap:wrap}
```

Duas colunas no celular, e os botões descem para uma linha própria de largura inteira. O
texto passa de ~46px para ~244px — cerca de **cinco vezes** mais.

Conferir junto, porque a mesma correção mexe neles: **anotação** (`blocoNota()`), **material**
(`.item.mat`, que também tem ações) e o próprio título do item, que hoje quebra em cascata
por causa do mesmo aperto. O painel de aceite não é afetado — `.nov-item` já redefine as
colunas e não tem `.item-actions`.

### Três ajustes que valem no mesmo passo

1. **`.ia-texto` está em 13.5px.** Serve para uma nota de rodapé, não para leitura longa num
   celular. Subir para ~15px no mobile (o `.item-text` já é 15px).
2. **`.chat-painel` usa `max-height:min(70vh,560px)`.** No celular, `vh` é medido contra o
   viewport **maior** — com a barra do navegador escondida — então parte do painel fica
   embaixo da barra e some. A unidade certa é `dvh` (`70dvh`), que acompanha a barra
   aparecendo e desaparecendo. Vale para qualquer `vh` novo daqui para frente.
3. **O `#revisar` não sofre do problema** — `.cartao` é bloco de largura inteira, com 17px na
   pergunta. É o contraexemplo útil: mostra que o defeito é do grid do item, não da IA.

### Opcional, mais caro: renderizar o markdown

A IA devolve `**negrito**`, `- listas` e `###`, e o app mostra tudo **cru** (`esc()` +
`white-space:pre-wrap`). Num celular esses símbolos são ruído em cima de um texto que já
estava apertado. Um renderizador mínimo — negrito, itálico, lista, código, parágrafo —
melhora muito a leitura.

> ⚠️ **A ordem importa e é questão de segurança.** Escapar **primeiro** com `esc()`, aplicar
> as transformações **depois**, e só de uma lista fechada de padrões. Fazer ao contrário —
> transformar antes de escapar — transforma a resposta do modelo em vetor de injeção.
> Escapar depois apagaria as marcações que acabaram de ser criadas.

Fazer isto **depois** da correção de grid: o grid é o problema real, o markdown é o polimento.

---

## Item 3 — Botão 🔍 no material sem link

**Esforço: ~5 linhas.** É o patch do vão que o tier gratuito abriu, e só faz sentido
*porque* perdemos a busca na web: a IA agora sugere "Curso em Vídeo — Git e GitHub" sem
endereço, e a ponte entre o título e o material é você digitando no Google.

**Onde:** `linhaMaterial()`, no ramo em que `href` é vazio, e opcionalmente na mesma
situação dentro de `painelIA()`.

**Como:** um link para
`https://www.google.com/search?q=` + `encodeURIComponent(titulo + " " + nome do tema)`.
Incluir o nome do tema desambigua ("Rebase" sozinho não é busca útil).

Três detalhes que evitam retrabalho:

- `encodeURIComponent` é obrigatório, não opcional: título com `&` ou `#` quebraria a busca
  em silêncio, e título com `"` quebraria o atributo.
- **Não passar por `urlSegura()`.** Ela existe para endereço **digitado por usuário**; esta
  URL é construída por nós e é `https` por construção. Passar por lá não é errado, só
  confunde quem ler depois sobre de onde vem o risco.
- O botão fica **fora** do bloco `podeEditar()`. Buscar não é editar — visitante deslogado
  lendo a trilha oficial também se beneficia.

---

## Item 4 — Busca global

**Esforço: baixo.** Puro cliente, nenhum SQL, nenhuma policy: o `state` já tem tudo em
memória, e `todosMateriais()` já existe. O motivo é atrito diário — o conteúdo cresceu ao
ponto de procurar na mão incomodar.

**Escopo da busca:** nome e resumo do tema, texto e detalhe do item, **anotação** do item,
título/nota/domínio do material. A anotação é o que mais importa: é o conteúdo escrito por
ele, e hoje é o mais difícil de reencontrar, porque só aparece ao abrir o item.

**Desenho:**
- Campo na `topBar()`, rota `#buscar` (o `state.abas[].id` é slug, então cada resultado
  linka para `#<slug>` e a tela do tema já sabe se posicionar).
- Uma função `normalizar(s)` com
  `s.normalize("NFD").replace(/\p{Diacritic}/gu,"").toLowerCase()` — sem isso, "revisao"
  não acha "revisão", e é exatamente assim que se digita com pressa no celular.
- Resultado agrupado por tipo (itens · anotações · materiais), com o nome do tema em cada
  linha, no mesmo formato que `linhaMaterial(m, aba, true)` já usa na tela global.
- **Sem debounce.** Os dados estão na memória; atraso artificial aqui só piora a sensação.

**Cuidado:** o trecho que casou tem que ser destacado com `esc()` aplicado **antes** de
inserir a marcação de destaque. Escapar depois apagaria o `<mark>`; destacar antes de
escapar transforma o termo buscado em vetor de injeção — e o termo vem digitado pelo usuário.

---

## Item 5 — Quadro de projeto

O desenho completo está em `planos/2026-07-28-ia-e-quadro-de-projeto.md`, Parte 2, e continua
válido.
Resumo do que decide a forma:

- **`projetos(… grupo_id NULL …)`** — `grupo_id` nulo é projeto pessoal. Compartilhar é
  criar um grupo e preencher o campo. Por isso a **Fase 2a entrega valor sozinha**, antes de
  existir qualquer grupo, e é onde começar.
- **Fase 2a:** `projetos`, `tarefas` (status `a_fazer`/`fazendo`/`feito`),
  `tarefa_comentarios`. Telas `#projetos` e `#projeto/<id>` em colunas. **Nada de
  arrastar-soltar no celular** — uma coluna por vez com os chips que `.mat-filtros` já usa,
  e botões `← mover` / `mover →`.
- **Fase 2b:** `grupos`, `grupo_membros`, entrar **por código** (não por e-mail: o app não
  tem infraestrutura de e-mail), `eh_membro()` como `security definer` — mesmo motivo de
  `eh_admin()`, policy que consulta tabela com RLS entra em recursão.
- Tempo real reaproveitando `ligarRealtimeMural()`, que já tem o formato certo.
- **Last-write-wins, e dito na tela.** CRDT é outro produto.

> ⚠️ É a **primeira vez que o projeto sai de "uma linha, um dono"**. Todo SQL de grupo tem
> que passar pelo teste da conta B — a mesma segunda conta do item 1.

---

## Item 6 — Arquivo do que já foi estudado (arquivar em vez de excluir)

**Pedido dele, 2026-07-29:** *"a cada coisa concluída com sucesso, fique armazenado em alguma
parte para poder ser consultada […] fazendo assim não precisar ficar excluindo o item"*.

### O achado que torna isto urgente

A cadeia de chaves estrangeiras é toda `on delete cascade`:

```
temas ──cascade──▶ itens ──cascade──▶ progresso   (item_id, concluido_em)
                         └─cascade──▶ ia_cartoes  (item_id, tema_id)
```

E `progresso` é a **única** fonte de `calcularSequencia()`, de `diasDeEstudo()` (o mapa de
atividade de 12 semanas) e da data que aparece no `selo()`.

**Consequência:** excluir um item concluído para "limpar a tela" apaga a linha de `progresso`
— e com ela a prova de que ele estudou naquele dia. A sequência cai, o mapa de 12 semanas
perde quadradinhos e os cartões de revisão daquele item desaparecem. **Excluir um tema faz
isso com o tema inteiro de uma vez.** Nenhum aviso, nenhum erro: o histórico é reescrito
retroativamente e a tela mostra um número menor como se ele tivesse estudado menos.

> **Mitigação disponível hoje, de graça:** não excluir item nem tema **concluído**. Enquanto
> o item 6 não existir, essa é a única proteção — e vale dizer a ele em voz alta, porque a
> perda é invisível.

### A boa notícia: o dado já está guardado

Nada precisa ser criado para *consultar* o histórico. `progresso` já tem `item_id` e
`concluido_em`, `itens` já tem `nota`, e o cliente já mantém `progressoEm` (Map id→ISO) e
`chaveDia()`. O que falta é **um lugar para ver** e **um jeito de tirar da frente sem
destruir**. São duas partes independentes, e a ordem importa.

### 6a — Tela `#historico` *(zero mudança de schema, faz sozinha o que ele pediu)*

Somente leitura: tudo que foi concluído, mais recente primeiro, agrupado por mês, cada linha
com o tema, a data e a **anotação** — que é o conteúdo escrito por ele e hoje só aparece
abrindo o item. Reaproveita `progressoEm`, `chaveDia()` e o formato de
`linhaMaterial(m, aba, true)`, que já mostra "de qual tema" na tela global.

Pode subir sozinha, sem risco nenhum, e já entrega o "poder ser consultada".

### 6b — Arquivar *(a parte que substitui o excluir)*

```sql
alter table public.itens add column if not exists arquivado_em timestamptz;
alter table public.temas add column if not exists arquivado_em timestamptz;
```

Item arquivado sai da lista ativa e **mantém** progresso, anotação e cartões. Segue a regra de
degradação do projeto: `detectarColunas()` sonda a coluna; sem ela, o botão não aparece e nada
quebra — então a ordem entre rodar o SQL e dar push continua não importando.

Na tela: um chip "mostrar arquivados" reaproveitando `.mat-filtros`, que já existe.

> ⚠️ **O custo escondido é o mesmo da ideia "Desfazer": toda leitura precisa passar a
> filtrar.** `carregarTrilha()`, `stats()`, `totals()`, `viewAfazer()` e a tela `#materiais`.
> Esquecer **um** faz as telas discordarem entre si sem dar erro. O caso mais traiçoeiro é o
> `stats()`: ele conta `a.itens.length` como denominador, então item arquivado não filtrado
> **derruba a porcentagem** — e a tela mostra regressão onde houve arrumação.

`marcarTodosDoTema()` foi escrita pelo Ricardo: não reescrever sem perguntar.

---

## Item 7 — Importar qualquer arquivo e virar trilha

**Pedido dele, 2026-07-29:** *"colocar um WORD lá, ou TXT, o programa ler o arquivo, e
realizar a criação da tabela"*.

Hoje só existe `substituirTrilha()`, que aceita **JSON** e **substitui** a trilha.

### A divisão que faz o problema virar tratável

Duas metades, cada uma resolvida pela ferramenta certa:

| | Quem faz | Por quê |
|---|---|---|
| **extrair o texto** do arquivo | o cliente, sem biblioteca | é determinístico: descompactar e tirar marcação não admite palpite |
| **decidir o que é tema e o que é item** | a IA, com esquema | é justamente o julgamento difuso em que o modelo é bom e o parser é ruim |

### 7a — Extração no cliente

- **`.txt` / `.md` / `.csv`** — `FileReader`, direto. **Cuidado com a codificação:** TXT
  exportado do Word costuma vir em `windows-1252`, não UTF-8. Decodificar como UTF-8 e, se
  aparecer `U+FFFD` no resultado, redecodificar com `new TextDecoder("windows-1252")`. Sem
  isso, todo acento vira caractere quebrado — e o arquivo "importou", só ilegível.
- **`.docx`** — é um ZIP com o texto em `word/document.xml`. Dá para ler **sem CDN e sem
  build**: o navegador tem `DecompressionStream("deflate-raw")`. Localizar a entrada no
  diretório central, inflar, tratar `<w:p>` como parágrafo e remover o resto das tags. ~40
  linhas. É isto que mantém a regra do arquivo único intacta — nenhuma dependência nova.
- **`.doc`** (binário pré-2007) — não vale o esforço. A tela pede "Salvar como .docx".
- **`.pdf`** — fora de escopo. Extrair texto de PDF exige lidar com fontes e posicionamento;
  é `pdf.js` e é outro produto. Dizer isso na tela em vez de tentar e falhar torto.

### 7b — Estruturação pela IA

Ação nova `estruturar_trilha`, com `responseSchema`:

```
{ temas: [ { nome, emoji, resumo, itens: [ { texto, detalhe } ] } ] }
```

O resultado cai no **painel de aceite que já existe** — a regra do projeto continua: a IA
propõe, você aceita. Pelo próprio plano, ação nova é "um prompt, um esquema e um botão".

### Cinco armadilhas para não descobrir na hora

1. **Teto de tamanho, e dito na tela.** Um `.docx` de 300 páginas estoura o contexto e
   **queima uma das 12 chamadas do dia** sem devolver nada. Cortar em ~40 mil caracteres e
   **avisar o que foi cortado**: truncar em silêncio faz ele acreditar que o arquivo todo
   entrou.
2. **Conteúdo de arquivo é entrada não confiável.** Todo texto passa por `esc()`, todo
   endereço por `urlSegura()`. Um `.docx` pode perfeitamente conter `javascript:` num trecho
   que viraria link — é a mesma armadilha de URL digitada, com outra porta de entrada.
3. **Importar tem que ACRESCENTAR, não substituir.** `substituirTrilha()` apaga, e ela já
   quase apagou a trilha oficial de todos uma vez por confiar no RLS em vez de filtrar por
   dono. Reaproveitar aquele caminho sem pensar repete o acidente. Liga com a ideia "mesclar
   trilha importada".
4. **Sem rede não funciona, e a tela precisa dizer.** Depende da Edge Function;
   `podeUsarIA()` já esconde botão quando `offline` — o botão de importar segue a mesma regra.
5. **Degradação para quando a IA não estiver disponível:** um parser burro de markdown
   (`#` = tema, `- ` = item) ainda serve para `.md` e `.txt`. Menos esperto, sempre
   disponível, e coerente com o resto do projeto.

---

## Mais ideias

Ordenadas por (valor ÷ esforço), com o porquê. As cinco primeiras nasceram do estado atual;
as últimas vêm da Parte 3 do plano antigo e seguem valendo.

| | Ideia | Por que agora | Esforço |
|---|---|---|---|
| 1 | **Mostrar quanto resta da IA hoje** | O `ping` já devolve `usadas`/`limite` e ninguém vê. Com o freio em 12, o usuário passa a encostar nele — e "não sei por que o ✨ parou" é pior que qualquer limite. Uma linha no `#resumo` ou ao lado dos botões ✨ | Mínimo |
| 2 | **Terceiro grau no `#revisar`** | Hoje são dois botões, e "Ainda não sei" zera o intervalo para 1 dia. Isso pune igual quem errou tudo e quem quase acertou, o que faz o cartão quase-sabido voltar todo dia até irritar. Um "mais ou menos" que corta o intervalo pela metade em vez de zerar | Baixo |
| 3 | **Plano da semana** (ação nova de IA) | A infraestrutura toda existe: é um prompt, um esquema e um botão. E o corolário do plano antigo se aplica inteiro — mandar `calcularSequencia()` e os pendentes **calculados**, pedindo só a interpretação. O que a IA faz de melhor aqui é priorizar, não contar | Baixo |
| 4 | **Virar cartão a partir do chat** | Fecha o ciclo conversa → conteúdo → revisão. Hoje a boa resposta do chat morre no `localStorage`; o cartão a promove a conteúdo dele. Reaproveita o painel de aceite inteiro | Baixo |
| 5 | **Fallback de modelo no 429** | Robustez específica do tier gratuito: se `GEMINI_MODELO` estourar a cota, tentar um modelo `-lite` antes de desistir. O nome já vem de secret, então é só uma segunda tentativa | Baixo |
| 6 | **Exportar caderno** (Markdown/PDF) | Trilha + anotações + materiais viram um documento — o resultado palpável de meses de estudo | Baixo |
| 7 | **Pomodoro com registro de tempo** | Transforma a trilha de checklist em diário ("3h em Git esta semana"). Bônus: dá dado real para o item 3 | Baixo |
| 8 | **Desfazer** (lixeira de 30 dias, `excluido_em`) | Hoje excluir tema ou item é definitivo | Médio |
| 9 | **Notificações push** | O SW existe e ele está no Android. Precisa de VAPID + cron no Supabase. É o que traz de volta quem parou | Médio |
| 10 | **Regerar `data.json`** | Está com a semente antiga; regerar pelo Exportar. Faxina, não recurso | Mínimo |

---

## Ordem sugerida

**2 → 6a → 1 → 3 → mais-ideias nº 1 → 6b → 7 → 4 → 5**

O **6a** subiu para logo depois da correção de tela por um motivo que não é de recurso, é de
perda de dado: enquanto ele não existe, cada exclusão de item concluído apaga história de
estudo em silêncio. A tela de histórico custa zero mudança de schema, já entrega o que ele
pediu, e passa a dar um lugar para onde olhar antes de excluir qualquer coisa. O **6b**
(arquivar) vem mais tarde porque mexe em toda leitura, e isso é trabalho de verdade.

O **7** (importar arquivo) fica depois do 6b de propósito: importar aumenta a quantidade de
itens na tela, e sem o arquivar a tela fica pior justamente por causa do recurso novo.

O item 2 passou para a frente: são duas linhas de CSS que multiplicam por cinco a largura do
texto, e **é o que decide se a IA que acabou de subir vai ser usada ou abandonada**. Recurso
que existe mas é desconfortável de ler no aparelho em que ele estuda vale menos que recurso
nenhum, porque custou tempo e não devolve nada.

O item 1 vem logo depois porque não é código e pode revelar trabalho que muda toda a ordem —
testar antes de construir. Vale notar que ele fica **melhor** depois do 2: o teste dos
cartões acontece no celular, e ler cartão em coluna de 46px atrapalharia o próprio teste.

O item 3 e o nº 1 das ideias são consertos pequenos de coisas que a migração de hoje deixou
meio-abertas, e sai barato fechá-las enquanto o assunto está fresco. A busca global é o
primeiro recurso novo de verdade. O quadro de projeto é o único bloco grande, e merece
começar com a segunda conta já criada.

Uma fase por vez, commit próprio, e **nada começa sem o Ricardo autorizar**.
