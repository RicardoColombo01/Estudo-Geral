-- =====================================================================
--  Trilha de Estudos — IA & Dev  ·  materiais de estudo
-- =====================================================================
--  Roda DEPOIS do supabase-evolucao.sql. Ordem dos arquivos:
--    supabase.sql → supabase-contas.sql → supabase-evolucao.sql → ESTE
--
--  O que faz: guarda links de estudo por tema (cursos, vídeos, artigos,
--  livros), seguindo exatamente o mesmo padrão de dono, RLS e origem_id
--  que temas e itens já usam. Nada aqui é regra nova — é o padrão
--  existente aplicado a uma tabela a mais.
--
--  ⚠ REGRA DO PROJETO: este script só ADICIONA policies. O RLS combina
--  policies com OU, e uma permissiva reintroduzida reabre o banco em
--  silêncio. Os únicos "drop policy" abaixo são das policies da tabela
--  NOVA, que ninguém mais usa.
--
--  ⚠ ANTES DE RODAR: "⤓ Exportar" no site, para ter backup.
--
--  O index.html publicado AGUENTA rodar sem este SQL: ele sonda a tabela
--  e desliga o recurso sozinho se não existir. A ordem entre este script
--  e o git push não importa.
-- =====================================================================


-- =====================================================================
--  1. A TABELA
-- =====================================================================

create table if not exists public.materiais (
  id        uuid        primary key default gen_random_uuid(),
  user_id   uuid        default auth.uid() references auth.users(id) on delete cascade,
  tema_id   uuid        not null references public.temas(id) on delete cascade,
  titulo    text        not null check (char_length(titulo) between 1 and 120),
  url       text        not null default '' check (char_length(url) <= 500),
  tipo      text        not null default 'outro'
                        check (tipo in ('video','curso','artigo','livro','outro')),
  nota      text        not null default '' check (char_length(nota) <= 500),
  ordem     integer     not null default 0,
  origem_id uuid        references public.materiais(id) on delete set null,
  criado_em timestamptz not null default now()
);

--  user_id nulo = linha do modelo oficial, igual a temas e itens.
--  O default auth.uid() faz o banco carimbar o dono sozinho, então o app
--  não precisa mandar user_id em nenhum POST — só no modo modelo, onde
--  ele manda null explícito para vencer o default.

--  O "on delete cascade" do tema_id é o que faz excluir um tema levar os
--  materiais dele junto, sem nenhuma linha de JavaScript.

create index if not exists materiais_user_idx   on public.materiais (user_id);
create index if not exists materiais_tema_idx   on public.materiais (tema_id);
create index if not exists materiais_origem_idx on public.materiais (origem_id);

alter table public.materiais enable row level security;

grant select                         on public.materiais to anon;
grant select, insert, update, delete on public.materiais to authenticated;


-- =====================================================================
--  2. POLICIES — espelham exatamente as de itens
-- =====================================================================
--  Nota de performance: (select auth.uid()) faz o Postgres avaliar a
--  função uma vez por query em vez de uma vez por linha.

drop policy if exists "materiais: ver o modelo e os meus" on public.materiais;
drop policy if exists "materiais: criar os meus"          on public.materiais;
drop policy if exists "materiais: editar os meus"         on public.materiais;
drop policy if exists "materiais: excluir os meus"        on public.materiais;
drop policy if exists "materiais: admin edita o modelo"   on public.materiais;

create policy "materiais: ver o modelo e os meus" on public.materiais for select
  using (user_id is null or user_id = (select auth.uid()));
create policy "materiais: criar os meus" on public.materiais for insert
  with check (user_id = (select auth.uid()));
create policy "materiais: editar os meus" on public.materiais for update
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "materiais: excluir os meus" on public.materiais for delete
  using (user_id = (select auth.uid()));

--  Policy ADICIONAL: admin escreve nas linhas do modelo. Reaproveita a
--  função public.eh_admin() criada no supabase-evolucao.sql.
create policy "materiais: admin edita o modelo" on public.materiais for all
  using      (user_id is null and public.eh_admin())
  with check (user_id is null and public.eh_admin());


-- =====================================================================
--  3. O TRIGGER DE CADASTRO PASSA A COPIAR OS MATERIAIS
-- =====================================================================
--  ⚠ Esta função é a MESMA do supabase-evolucao.sql, com um insert a
--  mais. Se algum dia você rodar o supabase-evolucao.sql de novo, ele
--  recria a versão SEM materiais e contas novas nascem sem os links —
--  sem erro nenhum, só faltando. Rodou aquele? Rode este em seguida.
--
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

    insert into public.materiais (user_id, tema_id, titulo, url, tipo, nota, ordem, origem_id)
    select new.id, novo_id, m.titulo, m.url, m.tipo, m.nota, m.ordem, m.id
    from public.materiais m
    where m.tema_id = t.id;
  end loop;
  return new;
end;
$$;

drop trigger if exists ao_criar_usuario on auth.users;
create trigger ao_criar_usuario
after insert on auth.users
for each row execute function public.criar_trilha_do_usuario();


-- =====================================================================
--  4. CONFERÊNCIA
-- =====================================================================

select
  (select count(*) from public.materiais where user_id is null)     as materiais_modelo,
  (select count(*) from public.materiais where user_id is not null) as materiais_de_usuarios,
  (select count(*) from pg_trigger where tgname = 'ao_criar_usuario') as trigger_no_lugar;

--  A conferência que importa: nenhuma linha abaixo pode ter qualificador
--  "true" em materiais, temas, itens ou progresso.
select tablename, policyname, cmd, qual::text as usando, with_check::text as checando
from pg_policies
where schemaname = 'public'
  and tablename in ('materiais','temas','itens','progresso')
order by tablename, cmd, policyname;

--  E, no PowerShell, o teste que já pegou uma exposição real aqui —
--  escrita anônima TEM que dar 401:
--
--    $k = "<anon key>"; $base = "https://zezzpdhjjgqavtlxmgsp.supabase.co/rest/v1"
--    $h = @{ apikey=$k; Authorization="Bearer $k"; "Content-Type"="application/json" }
--    Invoke-RestMethod -Uri "$base/materiais" -Method Post -Headers $h `
--      -Body '{"tema_id":"00000000-0000-0000-0000-000000000000","titulo":"x"}'
