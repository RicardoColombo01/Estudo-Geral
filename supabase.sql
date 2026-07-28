-- =====================================================================
--  Trilha de Estudos — IA & Dev  ·  schema do Supabase
-- =====================================================================
--  Rode este arquivo INTEIRO no SQL Editor do Supabase (New query → Run).
--  É seguro rodar mais de uma vez: o seed no fim tem proteção contra
--  duplicar os dados.
--
--  ⛔ NÃO RODE ESTE ARQUIVO DEPOIS DO supabase-contas.sql ⛔
--  As policies daqui são ABERTAS (qualquer visitante edita e apaga tudo).
--  Elas foram substituídas pelas policies por dono do supabase-contas.sql.
--  Como o RLS combina policies com OU, recriar as daqui reabre o banco
--  inteiro sem gerar nenhum erro nem aviso.
--  Se rodar por engano: rode o supabase-contas.sql de novo em seguida.
--
--  Modelo de dados:
--    temas     → os estágios da trilha            (compartilhado por todos)
--    itens     → o que estudar dentro de cada tema (compartilhado por todos)
--    mensagens → o mural de recados                (compartilhado, append-only)
--
--  O que NÃO está aqui: a marcação de "concluído". Ela é pessoal e fica no
--  localStorage de cada visitante, porque o tema é um fato compartilhado
--  (existe uma trilha só) e o ✓ é uma opinião pessoal (cada um está num ponto).
-- =====================================================================


-- =====================================================================
--  1. TABELAS
-- =====================================================================

create table if not exists public.temas (
  id         uuid        primary key default gen_random_uuid(),
  slug       text        not null unique,          -- vira a rota: #fundamentos-ia
  nome       text        not null check (char_length(nome)   between 1 and 60),
  emoji      text        not null default '📘' check (char_length(emoji) between 1 and 8),
  resumo     text        not null default ''  check (char_length(resumo) <= 200),
  ordem      integer     not null default 0,       -- 01, 02, 03… na home
  criado_em  timestamptz not null default now()
);

create table if not exists public.itens (
  id         uuid        primary key default gen_random_uuid(),
  tema_id    uuid        not null references public.temas (id) on delete cascade,
  texto      text        not null check (char_length(texto)   between 1 and 200),
  detalhe    text        not null default '' check (char_length(detalhe) <= 300),
  ordem      integer     not null default 0,
  criado_em  timestamptz not null default now()
);

create table if not exists public.mensagens (
  id         uuid        primary key default gen_random_uuid(),
  autor      text        not null check (char_length(autor) between 1 and 40),
  texto      text        not null check (char_length(texto) between 1 and 500),
  criada_em  timestamptz not null default now()
);

-- Índices para as consultas que o app realmente faz
create index if not exists temas_ordem_idx      on public.temas     (ordem);
create index if not exists itens_tema_idx       on public.itens     (tema_id, ordem);
create index if not exists mensagens_recent_idx on public.mensagens (criada_em desc);


-- =====================================================================
--  2. SEGURANÇA (RLS)
-- =====================================================================
--  Com RLS ligado, o padrão do Postgres é NEGAR tudo. Cada policy abaixo
--  abre uma porta específica — e o que não tem policy fica fechado.
--  É por isso que a anon key pode ficar visível no HTML: quem protege o
--  banco são estas regras, não o segredo da chave.

alter table public.temas     enable row level security;
alter table public.itens     enable row level security;
alter table public.mensagens enable row level security;

-- --- temas e itens: app colaborativo aberto, todos podem tudo -----------
drop policy if exists "temas leitura publica"   on public.temas;
drop policy if exists "temas escrita publica"   on public.temas;
drop policy if exists "temas edicao publica"    on public.temas;
drop policy if exists "temas exclusao publica"  on public.temas;

create policy "temas leitura publica"  on public.temas for select using (true);
create policy "temas escrita publica"  on public.temas for insert with check (true);
create policy "temas edicao publica"   on public.temas for update using (true) with check (true);
create policy "temas exclusao publica" on public.temas for delete using (true);

drop policy if exists "itens leitura publica"   on public.itens;
drop policy if exists "itens escrita publica"   on public.itens;
drop policy if exists "itens edicao publica"    on public.itens;
drop policy if exists "itens exclusao publica"  on public.itens;

create policy "itens leitura publica"  on public.itens for select using (true);
create policy "itens escrita publica"  on public.itens for insert with check (true);
create policy "itens edicao publica"   on public.itens for update using (true) with check (true);
create policy "itens exclusao publica" on public.itens for delete using (true);

-- --- mensagens: mural append-only ---------------------------------------
--  Repare no que NÃO existe abaixo: policy de update e de delete.
--  Essa ausência É a regra — ninguém edita nem apaga a mensagem de outro,
--  e isso vale para qualquer cliente, não só para o nosso JavaScript.
drop policy if exists "mensagens leitura publica" on public.mensagens;
drop policy if exists "mensagens escrita publica" on public.mensagens;

create policy "mensagens leitura publica" on public.mensagens for select using (true);
create policy "mensagens escrita publica" on public.mensagens for insert with check (true);


-- =====================================================================
--  3. SEED — os 8 temas atuais da trilha
-- =====================================================================
--  Só insere se o banco ainda estiver vazio.

insert into public.temas (slug, nome, emoji, resumo, ordem) values
  ('fundamentos-ia', 'Fundamentos de IA',   '🧠', 'Entender o que a IA generativa é — e o que ela não é.',            1),
  ('usar-claude',    'Usar a Claude',       '🤝', 'Tratar a IA como colaborador: contexto, objetivo e formato.',      2),
  ('prompt',         'Engenharia de Prompt','✍️', 'A arte de instruir o modelo para extrair o melhor resultado.',     3),
  ('lovable',        'Lovable',             '💜', 'No-code para gerar apps web completos a partir de descrições.',    4),
  ('git',            'Git + GitFlow',       '🌿', 'Controle de versão e uma convenção de branches para times.',       5),
  ('worktree',       'Git Worktree',        '🌳', 'Várias branches abertas em pastas diferentes ao mesmo tempo.',     6),
  ('cc-ninja',       'Claude Code Ninja',   '🥷', 'Dominar os recursos avançados de produtividade do Claude Code.',   7),
  ('apis',           'APIs + API do Meta',  '🔌', 'Como programas conversam — e como falar com Facebook/WhatsApp.',   8)
on conflict (slug) do nothing;

insert into public.itens (tema_id, texto, detalhe, ordem)
select t.id, v.texto, v.detalhe, v.ordem
from (values
  -- Fundamentos de IA
  ('fundamentos-ia', 'Diferença entre IA, Machine Learning e LLM',            'Situar os termos antes de aprofundar.',        1),
  ('fundamentos-ia', 'O que é token e janela de contexto',                    'Por que o modelo tem limite de texto.',        2),
  ('fundamentos-ia', 'Treinamento × inferência (noção geral)',                'Como o modelo aprende vs. como responde.',     3),
  ('fundamentos-ia', 'Alucinação, cutoff de conhecimento e viés',             'Sempre verificar fatos críticos.',             4),
  ('fundamentos-ia', 'RAG: dar documentos ao modelo (noção)',                 'Como ampliar o conhecimento na hora.',         5),
  ('fundamentos-ia', 'Fine-tuning: saber que existe',                         'Quando ajustar o modelo faz sentido.',         6),

  -- Usar a Claude
  ('usar-claude', 'Dar contexto: quem é você, para quê, quem vai ler',        'O hábito que mais muda o resultado.',          1),
  ('usar-claude', 'Ser específico no objetivo e no formato',                  '''5 bullets para leigo'' > ''resuma isso''.',  2),
  ('usar-claude', 'Iterar: tratar a 1ª resposta como rascunho',               'Refinar com ''mais curto'', ''mais técnico''.',3),
  ('usar-claude', 'Few-shot: dar exemplos do resultado desejado',             'Mostrar em vez de só descrever.',              4),
  ('usar-claude', 'Pedir raciocínio passo a passo em problemas difíceis',     'Melhora precisão em tarefas complexas.',       5),
  ('usar-claude', 'Anexar arquivos/dados em vez de descrever',                'Menos ruído, mais precisão.',                  6),
  ('usar-claude', 'Escolher o canal: chat × Claude Code × API',               'Cada um serve a um tipo de tarefa.',           7),

  -- Engenharia de Prompt
  ('prompt', 'Estrutura: Papel / Tarefa / Contexto / Formato / Exemplo',      'O esqueleto de um bom prompt.',                1),
  ('prompt', 'Zero-shot × Few-shot',                                          'Sem exemplos vs. com exemplos.',              2),
  ('prompt', 'Chain-of-thought (''pense passo a passo'')',                    'Raciocínio explícito em etapas.',              3),
  ('prompt', 'Delimitadores para separar instrução de conteúdo',              'Usar ``` ou tags.',                            4),
  ('prompt', 'Decompor tarefa grande em etapas',                              'Quebrar problemas complexos.',                 5),
  ('prompt', 'Prompt de sistema × de usuário',                                'Relevante ao usar a API.',                     6),
  ('prompt', 'Ler o guia oficial da Anthropic',                               'docs.anthropic.com → Prompt Engineering.',     7),

  -- Lovable
  ('lovable', 'Descrever features com clareza',                               'Aqui a engenharia de prompt volta.',           1),
  ('lovable', 'Integração com Supabase (banco/auth)',                         'Lovable usa bastante.',                        2),
  ('lovable', 'Conectar APIs externas',                                       'Deixar o app ''vivo''.',                       3),
  ('lovable', 'Exportar/versionar o código no GitHub',                        'Por isso Git importa.',                        4),
  ('lovable', 'Limites do no-code: quando editar código de verdade',          'Saber a hora de sair da ferramenta.',          5),
  ('lovable', 'Construir 1 MVP de prática (ex: CRUD de tarefas)',             'Projeto pequeno real.',                        6),

  -- Git + GitFlow
  ('git', 'Comandos essenciais: init, add, commit, branch, checkout, merge',  'A base do dia a dia.',                         1),
  ('git', 'push / pull com o GitHub',                                         'Enviar e receber código.',                     2),
  ('git', 'GitFlow: main, develop, feature/*, release/*, hotfix/*',           'Organização de branches.',                     3),
  ('git', 'Simular um hotfix num repo de teste',                              'Praticar o fluxo completo.',                   4),
  ('git', 'Ler o Pro Git book',                                               'git-scm.com/book/pt-br (gratuito).',           5),

  -- Git Worktree
  ('worktree', 'O que é: várias branches em pastas simultâneas',              'Sem ficar dando checkout/stash.',              1),
  ('worktree', 'Comandos: worktree add / list / remove',                      'Criar, listar e remover.',                     2),
  ('worktree', 'Trabalhar numa feature enquanto revisa outra',                'O ganho prático principal.',                   3),
  ('worktree', 'Uso com Claude Code (isolamento de agentes)',                 'Agentes em worktrees separadas.',              4),

  -- Claude Code Ninja
  ('cc-ninja', 'Slash commands (/init, /code-review, /plugin)',               'Atalhos poderosos.',                           1),
  ('cc-ninja', 'CLAUDE.md: memória do projeto',                               'Contexto automático em cada sessão.',          2),
  ('cc-ninja', 'Subagentes e paralelismo',                                    'Várias tarefas ao mesmo tempo.',               3),
  ('cc-ninja', 'Worktrees para isolamento',                                   'Liga com o tema anterior.',                    4),
  ('cc-ninja', 'Hooks: automações em eventos',                                'Ex: rodar testes após editar.',                5),
  ('cc-ninja', 'MCP: conectar ferramentas externas',                          'Browser, Drive, bancos, etc.',                 6),
  ('cc-ninja', 'Plugins e skills',                                            'Pacotes de instruções reutilizáveis.',         7),

  -- APIs + API do Meta
  ('apis', 'HTTP: GET/POST/PUT/DELETE, JSON e status codes',                  'O vocabulário básico da web.',                 1),
  ('apis', 'Autenticação: API key, token e OAuth',                            'Como provar quem você é.',                     2),
  ('apis', 'Testar com Postman ou Insomnia',                                  'Ferramenta para experimentar.',                3),
  ('apis', 'Chamar 1 API pública simples (ex: clima)',                        'Primeiro contato prático.',                    4),
  ('apis', 'Meta: criar app em developers.facebook.com',                      'Ponto de partida do ecossistema.',             5),
  ('apis', 'Graph API (Facebook/Instagram)',                                  'A base de tudo no Meta.',                      6),
  ('apis', 'WhatsApp Cloud API: enviar 1 mensagem',                           'O ''hello world'' da automação.',              7),
  ('apis', 'Webhooks: receber eventos',                                       'O Meta te avisa quando algo acontece.',        8)
) as v (slug, texto, detalhe, ordem)
join public.temas t on t.slug = v.slug
where not exists (select 1 from public.itens);


-- =====================================================================
--  4. CONFERÊNCIA — deve devolver 8 temas e 50 itens
-- =====================================================================
select
  (select count(*) from public.temas)     as temas,
  (select count(*) from public.itens)     as itens,
  (select count(*) from public.mensagens) as mensagens;
