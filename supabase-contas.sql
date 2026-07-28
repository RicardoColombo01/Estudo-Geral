-- =====================================================================
--  Trilha de Estudos — IA & Dev  ·  migração para contas
-- =====================================================================
--  Roda DEPOIS do supabase.sql. Transforma a trilha única e compartilhada
--  em: um MODELO oficial (só-leitura) + uma CÓPIA por usuário.
--
--  A regra que organiza tudo:
--    user_id IS NULL        → é o modelo oficial: todos leem, ninguém edita
--    user_id = auth.uid()   → é meu: só eu leio e só eu escrevo
--
--  ⚠ ORDEM IMPORTA: assim que este arquivo rodar, o site publicado fica
--  somente-leitura até você subir a nova versão do index.html. Rode isto e
--  faça o push logo em seguida.
--
--  ⚠ ANTES DE RODAR: abra o site e clique em "⤓ Exportar" para guardar um
--  backup da trilha. Esta migração não tem volta fácil.
-- =====================================================================


-- =====================================================================
--  1. COLUNA DE DONO
-- =====================================================================

alter table public.temas     add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.itens     add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.mensagens add column if not exists user_id uuid references auth.users(id) on delete cascade;

--  O default faz o banco carimbar o dono sozinho: todo INSERT que o app já
--  envia continua igual, sem precisar passar user_id no corpo da requisição.
alter table public.temas     alter column user_id set default auth.uid();
alter table public.itens     alter column user_id set default auth.uid();
alter table public.mensagens alter column user_id set default auth.uid();

--  As linhas que já existem ficam com user_id NULL — ou seja, viram o modelo
--  oficial automaticamente. Nada é apagado nem reinserido.

create index if not exists temas_user_idx on public.temas (user_id);
create index if not exists itens_user_idx on public.itens (user_id);


-- =====================================================================
--  2. O SLUG DEIXA DE SER ÚNICO NO MUNDO
-- =====================================================================
--  Com uma cópia por usuário, dez pessoas terão um tema com slug "git".
--  A unicidade passa a ser por dono. O "nulls not distinct" (PG15+) impede
--  dois temas com o mesmo slug dentro do modelo.

alter table public.temas drop constraint if exists temas_slug_key;
drop index if exists public.temas_user_slug_idx;
create unique index temas_user_slug_idx on public.temas (user_id, slug) nulls not distinct;


-- =====================================================================
--  3. PROGRESSO SAI DO NAVEGADOR E VAI PARA A CONTA
-- =====================================================================
--  É isto que faz o ✓ marcado no celular aparecer no PC.

create table if not exists public.progresso (
  user_id      uuid        not null default auth.uid() references auth.users(id) on delete cascade,
  item_id      uuid        not null references public.itens(id) on delete cascade,
  concluido_em timestamptz not null default now(),
  primary key (user_id, item_id)
);

--  A chave primária composta já impede marcar o mesmo item duas vezes.
--  Nenhum código precisa checar isso.

alter table public.progresso enable row level security;
grant select, insert, update, delete on public.progresso to authenticated;


-- =====================================================================
--  4. POLICIES — as antigas eram abertas; agora são por dono
-- =====================================================================
--  Nota de performance: (select auth.uid()) faz o Postgres avaliar a função
--  uma vez por query em vez de uma vez por linha.

-- --- LIMPEZA TOTAL antes de recriar ----------------------------------
--  Derruba TODA policy existente nestas tabelas, qualquer que seja o nome.
--  Isto não é preciosismo: o RLS combina policies com OU, então UMA única
--  policy permissiva sobrevivente ("using (true)") anula todas as regras
--  restritivas abaixo. Apagar por nome fixo é frágil — se o supabase.sql
--  rodar de novo depois desta migração, ele recria as policies abertas e
--  o banco volta a ficar exposto sem nenhum aviso.
do $$
declare p record;
begin
  for p in
    select policyname, tablename
    from pg_policies
    where schemaname = 'public'
      and tablename in ('temas','itens','mensagens','progresso')
  loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- --- temas -----------------------------------------------------------
create policy "temas: ver o modelo e os meus" on public.temas for select
  using (user_id is null or user_id = (select auth.uid()));
create policy "temas: criar os meus" on public.temas for insert
  with check (user_id = (select auth.uid()));
create policy "temas: editar os meus" on public.temas for update
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "temas: excluir os meus" on public.temas for delete
  using (user_id = (select auth.uid()));

-- --- itens -----------------------------------------------------------
create policy "itens: ver o modelo e os meus" on public.itens for select
  using (user_id is null or user_id = (select auth.uid()));
create policy "itens: criar os meus" on public.itens for insert
  with check (user_id = (select auth.uid()));
create policy "itens: editar os meus" on public.itens for update
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "itens: excluir os meus" on public.itens for delete
  using (user_id = (select auth.uid()));

-- --- progresso: totalmente privado -----------------------------------
create policy "progresso: ver o meu" on public.progresso for select
  using (user_id = (select auth.uid()));
create policy "progresso: marcar" on public.progresso for insert
  with check (user_id = (select auth.uid()));
create policy "progresso: desmarcar" on public.progresso for delete
  using (user_id = (select auth.uid()));

-- --- mensagens: mural público, escrita só com conta -------------------
--  Deslogado, auth.uid() é NULL, o with check falha e o banco recusa o
--  INSERT. A regra "só quem tem conta escreve" mora aqui, não no JavaScript
--  — vale até para quem tentar bater direto na API com curl.
--  Continua sem policy de update/delete: mural append-only.
create policy "mural: leitura publica" on public.mensagens for select
  using (true);
create policy "mural: escrita autenticada" on public.mensagens for insert
  with check (user_id = (select auth.uid()));


-- =====================================================================
--  5. TRIGGER — quem cria conta ganha uma cópia do modelo
-- =====================================================================
--  Roda no momento do cadastro, antes de existir qualquer sessão. Por isso
--  precisa de SECURITY DEFINER: ele escreve em nome de um usuário que ainda
--  não tem JWT, então auth.uid() aqui seria NULL — usamos new.id.

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
    insert into public.temas (user_id, slug, nome, emoji, resumo, ordem)
    values (new.id, t.slug, t.nome, t.emoji, t.resumo, t.ordem)
    returning id into novo_id;

    insert into public.itens (user_id, tema_id, texto, detalhe, ordem)
    select new.id, novo_id, i.texto, i.detalhe, i.ordem
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

--  ⚠ Se esta função der erro, o CADASTRO INTEIRO falha e o usuário não
--  consegue entrar. Teste com uma conta descartável antes de divulgar.


-- =====================================================================
--  6. CONFERÊNCIA
-- =====================================================================
--  Esperado logo após a migração: 8 temas e 50 itens no modelo,
--  0 de usuários, e 0 no progresso.

select
  (select count(*) from public.temas where user_id is null)     as temas_modelo,
  (select count(*) from public.itens where user_id is null)     as itens_modelo,
  (select count(*) from public.temas where user_id is not null) as temas_de_usuarios,
  (select count(*) from public.progresso)                       as linhas_progresso;

--  E a conferência que importa de verdade: NENHUMA linha abaixo pode ter
--  qualificador "true" em temas, itens ou progresso. Se aparecer, sobrou uma
--  policy aberta e o banco está exposto.
select tablename, policyname, cmd, qual::text as usando, with_check::text as checando
from pg_policies
where schemaname = 'public'
  and tablename in ('temas','itens','mensagens','progresso')
order by tablename, cmd, policyname;
