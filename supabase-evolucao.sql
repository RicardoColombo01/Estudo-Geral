-- =====================================================================
--  Trilha de Estudos — IA & Dev  ·  evolução (fases 3 a 6)
-- =====================================================================
--  Roda DEPOIS do supabase-contas.sql. Cada seção é independente e
--  idempotente: dá para rodar o arquivo inteiro, ou só uma seção, e
--  rodar duas vezes não quebra nada.
--
--  ⚠ REGRA QUE VALE PARA O ARQUIVO INTEIRO: este script só ADICIONA
--  policies. Nenhum "drop policy" em temas, itens, mensagens ou
--  progresso. O RLS combina policies com OU — uma permissiva
--  reintroduzida por engano reabre o banco em silêncio, sem erro e sem
--  log, com o painel mostrando "RLS enabled" em verde. Já aconteceu
--  neste projeto. Os únicos drops aqui são das policies das tabelas
--  NOVAS (admins, modelo_dispensado), que ninguém mais usa.
--
--  ⚠ ANTES DE RODAR: abra o site e clique em "⤓ Exportar" para guardar
--  um backup da sua trilha.
--
--  O index.html publicado AGUENTA rodar sem este SQL: cada recurso novo
--  testa se o banco tem a estrutura e se desliga sozinho se não tiver.
--  Ou seja, a ordem entre este script e o git push não importa — não
--  existe janela com o site quebrado.
-- =====================================================================


-- =====================================================================
--  3. MURAL EM TEMPO REAL
-- =====================================================================
--  Publica a tabela para o Realtime. O site continua com o poll ligado
--  como rede de segurança: WebSocket cai em rede móvel, e o poll cobre
--  o buraco sem ninguém perceber. Se você nunca rodar esta seção, o
--  mural simplesmente segue atualizando pelo poll.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename  = 'mensagens'
  ) then
    execute 'alter publication supabase_realtime add table public.mensagens';
  end if;
end $$;

--  O Realtime respeita o RLS: a policy "mural: leitura publica" é o que
--  permite que até visitante deslogado receba os eventos.


-- =====================================================================
--  4. ADMIN DO MODELO OFICIAL
-- =====================================================================
--  Hoje a curadoria da trilha oficial só acontece pelo Table Editor do
--  Supabase. Isto permite fazer pelo site.

create table if not exists public.admins (
  user_id  uuid primary key references auth.users(id) on delete cascade,
  criado_em timestamptz not null default now()
);

alter table public.admins enable row level security;
grant select on public.admins to authenticated;

drop policy if exists "admins: ver o meu" on public.admins;
create policy "admins: ver o meu" on public.admins for select
  using (user_id = (select auth.uid()));

--  Sem policy de insert/update/delete de propósito: entrar para a lista
--  de admins só acontece por aqui, pelo SQL Editor. Ninguém se promove
--  pela API.

--  Função em vez de subconsulta solta nas policies: SECURITY DEFINER
--  ignora o RLS de public.admins ao conferir, então a regra funciona
--  igual para todo mundo e o Postgres avalia uma vez por query.
create or replace function public.eh_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

grant execute on function public.eh_admin() to authenticated;

-- --- policies ADICIONAIS: admin escreve nas linhas do modelo ----------
--  Elas convivem com as policies por dono que já existem. O RLS soma com
--  OU: quem não é admin continua exatamente como estava.

drop policy if exists "temas: admin edita o modelo" on public.temas;
create policy "temas: admin edita o modelo" on public.temas for all
  using      (user_id is null and public.eh_admin())
  with check (user_id is null and public.eh_admin());

drop policy if exists "itens: admin edita o modelo" on public.itens;
create policy "itens: admin edita o modelo" on public.itens for all
  using      (user_id is null and public.eh_admin())
  with check (user_id is null and public.eh_admin());

--  ⚠ Detalhe que morde: temas.user_id tem "default auth.uid()". Ao criar
--  um tema do MODELO, o app precisa mandar user_id = null explicitamente,
--  senão o default carimba o admin como dono e a linha vira a cópia dele
--  em vez de modelo. O index.html já faz isso no modo modelo.

-- --- 👉 EDITE A LINHA ABAIXO E RODE ----------------------------------
--  Troque o e-mail pelo da SUA conta Google (a mesma com que você entra
--  no site). Sem isto, ninguém é admin e a seção 4 não faz nada.

insert into public.admins (user_id)
select id from auth.users where email = 'SEU-EMAIL-AQUI@gmail.com'
on conflict (user_id) do nothing;


-- =====================================================================
--  5. PUXAR NOVIDADES DO MODELO
-- =====================================================================
--  O trigger copia o modelo UMA vez, no cadastro. Se a trilha oficial
--  melhorar amanhã, quem já tem conta nunca fica sabendo. Esta seção é a
--  única do arquivo que conserta um defeito de verdade; o resto é
--  melhoria.
--
--  A ideia: cada linha copiada passa a lembrar de qual linha do modelo
--  ela nasceu (origem_id). O que está no modelo e não é origem de nada
--  seu é novidade.

alter table public.temas add column if not exists origem_id uuid references public.temas(id) on delete set null;
alter table public.itens add column if not exists origem_id uuid references public.itens(id) on delete set null;

create index if not exists temas_origem_idx on public.temas (origem_id);
create index if not exists itens_origem_idx on public.itens (origem_id);

-- --- backfill: as cópias que já existem não têm origem_id -------------
--  Casa por TEXTO — o mesmo truque já usado duas vezes neste projeto
--  (migrarProgressoAntigo e migrarProgressoParaConta). Não é perfeito:
--  se você renomeou um tema, ele não casa e vai reaparecer como novidade
--  (é só dispensar). E se houver dois itens com texto idêntico no mesmo
--  tema, o Postgres casa com um deles — sem consequência prática, porque
--  os dois apontariam para conteúdo igual.

update public.temas c
set origem_id = m.id
from public.temas m
where c.user_id is not null
  and c.origem_id is null
  and m.user_id is null
  and m.slug = c.slug;

update public.itens ci
set origem_id = mi.id
from public.temas ct
join public.temas mt on mt.id = ct.origem_id
join public.itens mi on mi.tema_id = mt.id
where ci.tema_id  = ct.id
  and ci.user_id is not null
  and ci.origem_id is null
  and mi.texto = ci.texto;

-- --- o que foi dispensado nunca mais é oferecido ----------------------
--  Sem isto, um tema que você apagou de propósito voltaria a aparecer
--  como "novidade" para sempre.

create table if not exists public.modelo_dispensado (
  user_id   uuid not null default auth.uid() references auth.users(id) on delete cascade,
  origem_id uuid not null,
  criado_em timestamptz not null default now(),
  primary key (user_id, origem_id)
);

--  origem_id aqui NÃO tem foreign key de propósito: ele guarda ora um id
--  de tema, ora um id de item. Duas colunas exclusivas seriam mais
--  "corretas" e deixariam toda consulta do cliente duas vezes maior.

alter table public.modelo_dispensado enable row level security;
grant select, insert, delete on public.modelo_dispensado to authenticated;

drop policy if exists "dispensado: ver o meu"   on public.modelo_dispensado;
drop policy if exists "dispensado: dispensar"   on public.modelo_dispensado;
drop policy if exists "dispensado: desfazer"    on public.modelo_dispensado;

create policy "dispensado: ver o meu" on public.modelo_dispensado for select
  using (user_id = (select auth.uid()));
create policy "dispensado: dispensar" on public.modelo_dispensado for insert
  with check (user_id = (select auth.uid()));
create policy "dispensado: desfazer" on public.modelo_dispensado for delete
  using (user_id = (select auth.uid()));

-- --- o trigger de cadastro agora grava a origem -----------------------
--  ⚠ Se esta função der erro, o CADASTRO INTEIRO falha e ninguém novo
--  consegue entrar. Teste com uma conta descartável antes de divulgar.

create or replace function public.criar_trilha_do_usuario()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  t       record;
  novo_id uuid;
begin
  for t in select * from public.temas where user_id is null order by ordem loop
    insert into public.temas (user_id, slug, nome, emoji, resumo, ordem, origem_id)
    values (new.id, t.slug, t.nome, t.emoji, t.resumo, t.ordem, t.id)
    returning id into novo_id;

    insert into public.itens (user_id, tema_id, texto, detalhe, ordem, origem_id)
    select new.id, novo_id, i.texto, i.detalhe, i.ordem, i.id
    from public.itens i
    where i.tema_id = t.id;
  end loop;
  return new;
end;
$$;

drop trigger if exists ao_criar_usuario on auth.users;
create trigger ao_criar_usuario
after insert on auth.users
for each row execute function public.criar_trilha_do_usuario();


-- =====================================================================
--  6. ANOTAÇÕES POR ITEM
-- =====================================================================
--  Transforma a trilha de checklist em caderno de estudo. A nota é da
--  SUA cópia: o modelo nasce sem nota, e puxar novidade nunca sobrescreve
--  nota existente (a seção 5 só INSERE linhas novas).

alter table public.itens add column if not exists nota text not null default '';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'itens_nota_tamanho') then
    alter table public.itens add constraint itens_nota_tamanho check (char_length(nota) <= 2000);
  end if;
end $$;


-- =====================================================================
--  7. CONFERÊNCIA
-- =====================================================================

--  Estrutura nova no lugar:
select
  (select count(*) from public.admins)                                          as admins,
  (select count(*) from public.temas where user_id is not null and origem_id is null) as temas_sem_origem,
  (select count(*) from public.itens where user_id is not null and origem_id is null) as itens_sem_origem,
  (select count(*) from public.modelo_dispensado)                               as dispensados,
  (select count(*) from pg_publication_tables
    where pubname='supabase_realtime' and tablename='mensagens')                as mural_no_realtime;

--  "temas_sem_origem" e "itens_sem_origem" só devem contar o que VOCÊ
--  criou do zero (não veio do modelo). Se der um número alto logo após o
--  backfill, o casamento por texto não pegou — provavelmente você
--  renomeou coisas. Não é erro: é só que elas vão aparecer como novidade.

--  A conferência que importa de verdade: nenhuma linha abaixo pode ter
--  qualificador "true" em temas, itens ou progresso.
select tablename, policyname, cmd, qual::text as usando, with_check::text as checando
from pg_policies
where schemaname = 'public'
  and tablename in ('temas','itens','mensagens','progresso','admins','modelo_dispensado')
order by tablename, cmd, policyname;

--  E, no PowerShell, o teste que já pegou uma exposição real aqui —
--  escrita anônima TEM que dar 401:
--
--    $k = "<anon key>"; $base = "https://zezzpdhjjgqavtlxmgsp.supabase.co/rest/v1"
--    $h = @{ apikey=$k; Authorization="Bearer $k"; "Content-Type"="application/json" }
--    Invoke-RestMethod -Uri "$base/temas" -Method Post -Headers $h -Body '{"slug":"__x__","nome":"x","ordem":99}'
