-- =====================================================================
--  Trilha de Estudos — IA & Dev  ·  quadro de projeto (Fase 2a)
-- =====================================================================
--  Roda DEPOIS do supabase-arquivo.sql. Ordem dos arquivos:
--    supabase.sql → supabase-contas.sql → supabase-evolucao.sql
--    → supabase-materiais.sql → supabase-ia.sql → supabase-arquivo.sql
--    → ESTE
--
--  O que faz: projetos com tarefas em três colunas (a fazer / fazendo /
--  feito). Nesta fase TUDO é pessoal: cada linha tem um dono e só ele vê.
--  A coluna projetos.grupo_id já existe e fica NULA — compartilhar, na
--  Fase 2b, é criar um grupo e preencher o campo, sem refazer nada aqui.
--
--  ⚠ REGRA DO PROJETO: este script só ADICIONA policies. O RLS combina
--  policies com OU, e uma permissiva reintroduzida reabre o banco em
--  silêncio, sem erro e sem log, com o painel mostrando "RLS enabled"
--  em verde. Já aconteceu aqui. Os únicos "drop policy" abaixo são das
--  policies das tabelas NOVAS, que ninguém mais usa.
--
--  ⚠ ANTES DE RODAR: abra o site e clique em "⤓ Exportar" para guardar
--  um backup da sua trilha.
--
--  ⚠ ESTE É O ENSAIO DA PRIMEIRA VEZ QUE O PROJETO SAI DE "UMA LINHA,
--  UM DONO". Aqui ainda é um dono por linha, de propósito: dá para
--  conferir o RLS com calma antes de existir qualquer grupo. A
--  conferência da seção 6 não é opcional.
--
--  O index.html publicado AGUENTA rodar sem este SQL: ele sonda a tabela
--  projetos e some com o card sozinho se ela não existir. A ordem entre
--  este script e o git push não importa.
-- =====================================================================


-- =====================================================================
--  1. PROJETOS
-- =====================================================================

create table if not exists public.projetos (
  id           uuid        primary key default gen_random_uuid(),
  user_id      uuid        not null default auth.uid() references auth.users(id) on delete cascade,
  grupo_id     uuid,
  nome         text        not null check (char_length(nome) between 1 and 80),
  descricao    text        not null default '' check (char_length(descricao) <= 300),
  ordem        integer     not null default 0,
  arquivado_em timestamptz,
  criado_em    timestamptz not null default now()
);

--  user_id NOT NULL, ao contrário de temas/itens/materiais: não existe
--  "projeto do modelo oficial". Mesma escolha de ia_cartoes. O default
--  auth.uid() faz o banco carimbar o dono, então nenhum POST do cliente
--  manda user_id — e, como não há modo modelo aqui, também não existe o
--  caso de mandar "user_id: null" explícito para vencer o default.
--
--  grupo_id: NULO = projeto pessoal. Fica SEM chave estrangeira porque a
--  tabela public.grupos ainda não existe. Na Fase 2b entra uma linha:
--    alter table public.projetos
--      add constraint projetos_grupo_fk foreign key (grupo_id)
--      references public.grupos(id) on delete set null;
--  Todas as linhas estarão nulas, então a validação é instantânea.
--
--  ⚠ Nesta fase NENHUMA policy lê grupo_id — ele é inerte. Preencher o
--  campo com um uuid qualquer não dá acesso a ninguém: as quatro policies
--  abaixo olham só user_id. Quem passa a policiar o campo é a Fase 2b,
--  com um trigger que recusa grupo do qual você não é membro — trigger, e
--  não policy, justamente para não precisar reescrever nada daqui.
--
--  arquivado_em (timestamptz), e não "arquivado" (boolean): guardar QUANDO
--  custa os mesmos 8 bytes que guardar SE, o filtro fica igualmente
--  simples ("arquivado_em is null" = ativo), e é a mesma convenção do
--  supabase-arquivo.sql (itens e temas) e da futura ideia "Desfazer". Duas
--  convenções para a mesma ideia no mesmo banco é o que se confunde meses
--  depois.
--
--  ⚠ Não existe arquivado_em em TAREFAS, e é de propósito: status='feito'
--  já é o eixo de "saiu do caminho". Dois eixos independentes podem
--  discordar (tarefa feita E arquivada?) e obrigariam toda leitura a
--  filtrar por dois campos — o custo escondido que o PLANO.md descreve.

create index if not exists projetos_user_idx  on public.projetos (user_id);
create index if not exists projetos_grupo_idx on public.projetos (grupo_id);


-- =====================================================================
--  2. TAREFAS
-- =====================================================================

create table if not exists public.tarefas (
  id             uuid        primary key default gen_random_uuid(),
  user_id        uuid        not null default auth.uid() references auth.users(id) on delete cascade,
  projeto_id     uuid        not null references public.projetos(id) on delete cascade,
  titulo         text        not null check (char_length(titulo) between 1 and 120),
  detalhe        text        not null default '' check (char_length(detalhe) <= 500),
  status         text        not null default 'a_fazer'
                             check (status in ('a_fazer','fazendo','feito')),
  responsavel_id uuid        references auth.users(id) on delete set null,
  prazo          date,
  ordem          integer     not null default 0,
  criado_em      timestamptz not null default now()
);

--  ⚠ POR QUE tarefas TEM user_id PRÓPRIO, mesmo sendo filha de projetos
--
--  A alternativa era a policy de select ser um "exists" sobre projetos:
--    using (exists (select 1 from public.projetos p
--                   where p.id = tarefas.projeto_id and p.user_id = auth.uid()))
--  Três problemas, na ordem em que doem:
--
--  1. RLS DENTRO DE RLS. Uma policy que consulta outra tabela protegida
--     faz o Postgres avaliar TAMBÉM as policies daquela tabela. É
--     exatamente o motivo pelo qual public.eh_admin() existe como
--     security definer no supabase-evolucao.sql. Na Fase 2b a policy de
--     projetos vai chamar eh_membro(), e cada linha de tarefa lida
--     dispararia essa cadeia inteira.
--  2. CUSTO NO CAMINHO QUENTE. Ler um quadro é ler N tarefas; escrever é
--     uma linha por vez. Com coluna própria o SELECT vira comparação de
--     coluna indexada (tarefas_user_idx) e o custo de conferir o pai é
--     pago só na ESCRITA, onde é uma vez.
--  3. O QUE A 2b PRECISA. Com coluna própria, a 2b não altera nenhuma
--     policy daqui: ela só ACRESCENTA uma permissiva de select para o
--     grupo — que é a regra do projeto ("todo SQL novo só adiciona").
--
--  O risco da denormalização é a coluna divergir do dono do projeto. Ele
--  é fechado por construção: (a) o default auth.uid() significa que o
--  cliente nunca manda user_id, então quem carimba é o banco com a
--  identidade de quem chamou; (b) o "with check" de insert/update exige
--  que o PROJETO também seja seu (função da seção 3). Sem o item (b),
--  qualquer pessoa logada que soubesse o uuid de um projeto alheio
--  poderia enfiar tarefas dentro dele — não vazaria leitura, mas seria
--  escrita no quadro dos outros, e na Fase 2b os uuids de projeto passam
--  a circular. Fechar agora custa quatro linhas.
--
--  ⚠ Se a Fase 2b introduzir TRANSFERÊNCIA de projeto entre contas,
--  tarefas.user_id passa a mentir. Registrado aqui de propósito: é mais
--  barato ler este aviso do que descobrir o sintoma.
--
--  responsavel_id e prazo já entram aqui. responsavel_id fica sem UI
--  nesta fase (o responsável é sempre você): coluna nullable não custa
--  nada e evita um "alter table" na 2b.

create index if not exists tarefas_user_idx    on public.tarefas (user_id);
create index if not exists tarefas_projeto_idx on public.tarefas (projeto_id, status, ordem);


-- =====================================================================
--  3. O HELPER — mesmo molde de public.eh_admin()
-- =====================================================================
--  security definer para não entrar em recursão de RLS, stable para o
--  planejador poder reaproveitar, e search_path fixo para ninguém
--  redirecionar o "projetos" para outro schema.

create or replace function public.meu_projeto(p_projeto uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.projetos
    where id = p_projeto and user_id = auth.uid()
  );
$$;

--  auth.uid() CRU aqui dentro (a função já roda uma vez por chamada); o
--  "(select auth.uid())" das policies é a otimização de avaliar uma vez
--  por query em vez de uma vez por linha.
--
--  Na Fase 2b esta função ganha o segundo caso — e é só isto que muda:
--    ... where id = p_projeto
--          and (user_id = auth.uid()
--               or (grupo_id is not null and public.eh_membro(grupo_id)))

grant execute on function public.meu_projeto(uuid) to authenticated;


-- =====================================================================
--  4. RLS E PERMISSÕES
-- =====================================================================

alter table public.projetos enable row level security;
alter table public.tarefas  enable row level security;

--  SEM "to anon", de propósito e ao contrário de materiais: aqui não
--  existe linha do modelo oficial, então visitante não tem o que ler. A
--  consequência é que /rest/v1/projetos responde 401 para a anon key em
--  QUALQUER método — é o que a seção 6 confere.
grant select, insert, update, delete on public.projetos to authenticated;
grant select, insert, update, delete on public.tarefas  to authenticated;


-- =====================================================================
--  5. POLICIES — quatro por comando, nunca "for all"
-- =====================================================================
--  Nota de performance: (select auth.uid()) faz o Postgres avaliar a
--  função uma vez por query em vez de uma vez por linha.

drop policy if exists "projetos: ver os meus"     on public.projetos;
drop policy if exists "projetos: criar os meus"   on public.projetos;
drop policy if exists "projetos: editar os meus"  on public.projetos;
drop policy if exists "projetos: excluir os meus" on public.projetos;

create policy "projetos: ver os meus" on public.projetos for select
  using (user_id = (select auth.uid()));
create policy "projetos: criar os meus" on public.projetos for insert
  with check (user_id = (select auth.uid()));
create policy "projetos: editar os meus" on public.projetos for update
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "projetos: excluir os meus" on public.projetos for delete
  using (user_id = (select auth.uid()));

drop policy if exists "tarefas: ver as minhas"     on public.tarefas;
drop policy if exists "tarefas: criar as minhas"   on public.tarefas;
drop policy if exists "tarefas: editar as minhas"  on public.tarefas;
drop policy if exists "tarefas: excluir as minhas" on public.tarefas;

create policy "tarefas: ver as minhas" on public.tarefas for select
  using (user_id = (select auth.uid()));

--  O "and public.meu_projeto(...)" só aparece nos with check: ele responde
--  "o projeto de destino é meu?". No update, o "using" olha a linha como
--  ela ESTÁ (é minha?) e o "with check" olha como ela vai FICAR (o projeto
--  novo é meu?) — juntos, cobrem inclusive mover uma tarefa de um projeto
--  para outro.
create policy "tarefas: criar as minhas" on public.tarefas for insert
  with check (user_id = (select auth.uid()) and public.meu_projeto(projeto_id));
create policy "tarefas: editar as minhas" on public.tarefas for update
  using      (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and public.meu_projeto(projeto_id));
create policy "tarefas: excluir as minhas" on public.tarefas for delete
  using (user_id = (select auth.uid()));

--  ⚠ criar_trilha_do_usuario() NÃO muda e não é redefinida aqui. O trigger
--  de cadastro copia o MODELO OFICIAL, e projeto não tem modelo — mesma
--  situação de ia_cartoes. Conta nova nasce com zero projetos, que é o
--  certo. Redefinir a função aqui reintroduziria o acidente do
--  supabase-materiais.sql (contas novas nascendo sem os materiais).

--  ⚠ Realtime fica FORA desta fase. Publicar tarefas em supabase_realtime
--  não serve a um quadro de um dono só. A Fase 2b acrescenta uma linha:
--    alter publication supabase_realtime add table public.tarefas;


-- =====================================================================
--  6. CONFERÊNCIA
-- =====================================================================
--  ⚠ O SQL Editor do Supabase mostra só o resultado do ÚLTIMO comando de
--  uma execução. Rodar o arquivo inteiro exibe apenas a listagem de
--  pg_policies, e o select de contagens abaixo passa despercebido como se
--  não tivesse rodado. Para ver cada um, cole-o SOZINHO numa query nova.

select
  (select count(*) from public.projetos) as projetos,
  (select count(*) from public.tarefas)  as tarefas,
  (select count(*) from public.projetos where grupo_id is not null) as ja_em_grupo,
  (select count(*) from pg_proc where proname = 'meu_projeto')      as helper_no_lugar;

--  Devem sair 8 linhas. A conferência que importa: NENHUMA LINHA PODE TER
--  QUALIFICADOR "true" — uma permissiva aberta anula todas as restritivas,
--  sem erro e sem log.
select tablename, policyname, cmd, qual::text as usando, with_check::text as checando
from pg_policies
where schemaname = 'public'
  and tablename in ('projetos','tarefas')
order by tablename, cmd, policyname;

--  E, no PowerShell, os testes que valem — "o que deveria falhar, falha?"
--
--    $k = "<anon key>"; $base = "https://zezzpdhjjgqavtlxmgsp.supabase.co/rest/v1"
--    $h = @{ apikey=$k; Authorization="Bearer $k"; "Content-Type"="application/json" }
--
--    # (1) escrita anônima TEM que dar 401:
--    Invoke-RestMethod -Uri "$base/projetos" -Method Post -Headers $h `
--      -Body '{"nome":"__x__"}'
--
--    # (2) LEITURA anônima também TEM que dar 401 — aqui não há linha
--    #     pública como em temas/materiais. Se voltar "[]" com 200, alguém
--    #     pôs "grant ... to anon" e a tabela está aberta para leitura.
--    Invoke-RestMethod -Uri "$base/projetos?select=id" -Headers $h
--
--    # (3) com o SEU token, criar tarefa num projeto que não é seu TEM que
--    #     dar 403 ("violates row-level security policy"). Se vier 409 ou
--    #     o código 23503 (erro de chave estrangeira), a policy PASSOU e o
--    #     meu_projeto() não está no with check:
--    #  $t  = "<access_token da sessão>"
--    #  $hh = @{ apikey=$k; Authorization="Bearer $t"; "Content-Type"="application/json" }
--    #  Invoke-RestMethod -Uri "$base/tarefas" -Method Post -Headers $hh `
--    #    -Body '{"projeto_id":"00000000-0000-0000-0000-000000000000","titulo":"x"}'
--
--  ⚠ O QUE ESTES TESTES NÃO PROVAM: "a conta B não vê o projeto pessoal
--  da conta A". O teste (3) usa um uuid INEXISTENTE, e por isso não
--  distingue "o RLS filtrou" de "essa linha não existe" — é a mesma
--  fraqueza registrada no PLANO.md. Provar isso exige uma SEGUNDA CONTA
--  GOOGLE, e ela é pré-requisito da Fase 2b, não desta.
