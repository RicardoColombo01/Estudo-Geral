-- =====================================================================
--  Trilha de Estudos — IA & Dev  ·  IA de estudo
-- =====================================================================
--  Roda DEPOIS do supabase-materiais.sql. Ordem dos arquivos:
--    supabase.sql → supabase-contas.sql → supabase-evolucao.sql
--    → supabase-materiais.sql → ESTE
--
--  Duas tabelas: o extrato de uso da IA (que também é o freio) e os
--  cartões de revisão que a IA propõe e você aceita.
--
--  ⚠ REGRA DO PROJETO: só ADICIONA policies. Os únicos "drop policy"
--  abaixo são das policies das tabelas NOVAS.
--
--  O index.html publicado AGUENTA rodar sem este SQL e sem a Edge
--  Function: ele sonda os dois e some com os botões ✨ se faltar algum.
-- =====================================================================


-- =====================================================================
--  1. EXTRATO E FREIO DE USO
-- =====================================================================
--  Uma linha por usuário por dia. Serve para duas coisas ao mesmo tempo:
--  impedir que uma conta sozinha torre a cota da chave, e mostrar a você
--  quanto a IA está custando antes de a fatura chegar.

create table if not exists public.ia_uso (
  user_id        uuid   not null references auth.users(id) on delete cascade,
  dia            date   not null default current_date,
  chamadas       integer not null default 0,
  tokens_entrada bigint  not null default 0,
  tokens_saida   bigint  not null default 0,
  primary key (user_id, dia)
);

alter table public.ia_uso enable row level security;
grant select on public.ia_uso to authenticated;

drop policy if exists "ia_uso: ver o meu" on public.ia_uso;
create policy "ia_uso: ver o meu" on public.ia_uso for select
  using (user_id = (select auth.uid()));

--  ⚠ De propósito NÃO existe policy de insert/update aqui.
--  Se o próprio usuário pudesse escrever nesta tabela, ele zeraria o
--  contador e o freio não freava nada. Quem grava é a Edge Function,
--  com a service_role, pela função abaixo.

create or replace function public.registrar_uso_ia(
  p_user uuid, p_entrada bigint, p_saida bigint
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare n integer;
begin
  insert into public.ia_uso (user_id, dia, chamadas, tokens_entrada, tokens_saida)
  values (p_user, current_date, 1, coalesce(p_entrada,0), coalesce(p_saida,0))
  on conflict (user_id, dia) do update
    set chamadas       = ia_uso.chamadas + 1,
        tokens_entrada = ia_uso.tokens_entrada + excluded.tokens_entrada,
        tokens_saida   = ia_uso.tokens_saida   + excluded.tokens_saida
  returning chamadas into n;
  return n;
end $$;

--  Só a service_role chama. Tirar do authenticated é o que impede alguém
--  de inflar o próprio contador — ou de zerá-lo. O grant explícito depois
--  do revoke não é redundância: o "revoke from public" tira a permissão
--  que vinha por padrão, e sem o grant a Edge Function levaria 403.
revoke all on function public.registrar_uso_ia(uuid, bigint, bigint) from public, anon, authenticated;
grant execute on function public.registrar_uso_ia(uuid, bigint, bigint) to service_role;


-- =====================================================================
--  2. CARTÕES DE REVISÃO
-- =====================================================================
--  A IA propõe; você aceita; o cartão vira seu. Quem decide QUANDO
--  revisar é o app, não a IA: intervalo dobra a cada acerto e volta ao
--  começo no erro. Conta exata, de graça e sem alucinação.

create table if not exists public.ia_cartoes (
  id              uuid    primary key default gen_random_uuid(),
  user_id         uuid    not null default auth.uid() references auth.users(id) on delete cascade,
  item_id         uuid    references public.itens(id) on delete cascade,
  tema_id         uuid    references public.temas(id) on delete cascade,
  pergunta        text    not null check (char_length(pergunta) between 1 and 500),
  resposta        text    not null check (char_length(resposta) between 1 and 2000),
  proxima_revisao date    not null default current_date,
  intervalo_dias  integer not null default 1,
  acertos         integer not null default 0,
  erros           integer not null default 0,
  criado_em       timestamptz not null default now()
);

create index if not exists ia_cartoes_user_idx  on public.ia_cartoes (user_id, proxima_revisao);
create index if not exists ia_cartoes_item_idx  on public.ia_cartoes (item_id);

alter table public.ia_cartoes enable row level security;
grant select, insert, update, delete on public.ia_cartoes to authenticated;

drop policy if exists "cartoes: ver os meus"    on public.ia_cartoes;
drop policy if exists "cartoes: criar os meus"  on public.ia_cartoes;
drop policy if exists "cartoes: editar os meus" on public.ia_cartoes;
drop policy if exists "cartoes: excluir os meus" on public.ia_cartoes;

create policy "cartoes: ver os meus" on public.ia_cartoes for select
  using (user_id = (select auth.uid()));
create policy "cartoes: criar os meus" on public.ia_cartoes for insert
  with check (user_id = (select auth.uid()));
create policy "cartoes: editar os meus" on public.ia_cartoes for update
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "cartoes: excluir os meus" on public.ia_cartoes for delete
  using (user_id = (select auth.uid()));

--  Cartão é sempre pessoal: não existe cartão do modelo oficial e não há
--  policy de admin aqui. Se um dia fizer sentido a trilha oficial vir com
--  cartões, aí sim entra o user_id nulo e a policy aditiva — como em
--  temas, itens e materiais.


-- =====================================================================
--  3. CONFERÊNCIA
-- =====================================================================

select
  (select count(*) from public.ia_uso)     as linhas_de_uso,
  (select count(*) from public.ia_cartoes) as cartoes,
  (select count(*) from pg_proc where proname = 'registrar_uso_ia') as funcao_no_lugar;

--  Nenhuma linha abaixo pode ter qualificador "true".
select tablename, policyname, cmd, qual::text as usando, with_check::text as checando
from pg_policies
where schemaname = 'public'
  and tablename in ('ia_uso','ia_cartoes')
order by tablename, cmd, policyname;

--  E o teste que vale: escrita anônima TEM que dar 401.
--
--    $k = "<anon key>"; $base = "https://zezzpdhjjgqavtlxmgsp.supabase.co/rest/v1"
--    $h = @{ apikey=$k; Authorization="Bearer $k"; "Content-Type"="application/json" }
--    Invoke-RestMethod -Uri "$base/ia_cartoes" -Method Post -Headers $h `
--      -Body '{"pergunta":"x","resposta":"y"}'
