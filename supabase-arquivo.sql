-- =====================================================================
--  Trilha de Estudos — IA & Dev  ·  arquivar em vez de excluir
-- =====================================================================
--  Roda DEPOIS do supabase-ia.sql. Ordem dos arquivos:
--    supabase.sql → supabase-contas.sql → supabase-evolucao.sql →
--    supabase-materiais.sql → supabase-ia.sql → ESTE
--
--  POR QUE ELE EXISTE
--  A cadeia temas → itens → progresso / ia_cartoes é toda "on delete
--  cascade", e progresso é a ÚNICA fonte da sequência de dias, do mapa de
--  atividade de 12 semanas e da data do selo. Excluir um item concluído
--  para "limpar a tela" apaga a prova de que se estudou naquele dia: a
--  sequência cai, o mapa perde quadradinhos e os cartões somem. Nenhum
--  aviso, nenhum erro — a tela passa a mostrar menos estudo do que houve.
--  Arquivar tira da lista de estudo sem apagar nada.
--
--  O QUE FAZ: uma coluna em itens e outra em temas.
--    NULL      = ativo, aparece na trilha
--    com data  = fora da lista de estudo, e AINDA contando no progresso
--
--  O QUE NÃO FAZ, DE PROPÓSITO:
--   · Nenhuma policy nova. As policies por dono de temas/itens já
--     autorizam UPDATE e não enumeram colunas; os grants deste projeto
--     são no nível da TABELA, então coluna nova entra junto.
--   · Nenhum "drop policy" em tabela existente. O RLS combina policies
--     com OU, e uma permissiva reintroduzida reabre o banco em silêncio,
--     sem erro e sem log, com o painel mostrando "RLS enabled" em verde.
--   · Não toca em criar_trilha_do_usuario(). O insert dela não lista
--     arquivado_em, então toda cópia nasce com NULL = ativa. Redefinir a
--     função aqui repetiria o acidente do supabase-materiais.sql.
--
--  ⚠ ANTES DE RODAR: abra o site e clique em "⤓ Exportar" para ter backup.
--
--  O index.html publicado AGUENTA rodar sem este SQL: ele sonda as DUAS
--  colunas e desliga o botão 🗄 sozinho se faltar qualquer uma. A ordem
--  entre este script e o git push não importa.
-- =====================================================================


-- =====================================================================
--  1. AS COLUNAS
-- =====================================================================
--  Sem "not null" e sem default: a AUSÊNCIA de data é o estado "ativo", e
--  é isso que faz cada linha que já existe continuar exatamente como está,
--  sem backfill nenhum.
--
--  timestamptz, e não boolean: guardar QUANDO custa os mesmos 8 bytes que
--  guardar SE, o filtro fica igualmente simples ("is null" = ativo), e é a
--  mesma convenção que a ideia "Desfazer" (excluido_em) vai usar. Duas
--  convenções para a mesma ideia no mesmo banco é o que se confunde depois.

alter table public.itens add column if not exists arquivado_em timestamptz;
alter table public.temas add column if not exists arquivado_em timestamptz;


-- =====================================================================
--  2. ÍNDICES PARCIAIS
-- =====================================================================
--  Só as linhas arquivadas entram no índice (são a minoria), e é
--  exatamente o que a tela #historico pergunta: "arquivado_em is not
--  null". A leitura da trilha pergunta o contrário ("is null"), que casa
--  com quase tudo e não se beneficia de índice nenhum — ela continua indo
--  pelos índices de dono que já existem.

create index if not exists itens_arquivado_idx on public.itens (user_id) where arquivado_em is not null;
create index if not exists temas_arquivado_idx on public.temas (user_id) where arquivado_em is not null;


-- =====================================================================
--  3. CONFERÊNCIA
-- =====================================================================
--  ⚠ O SQL Editor do Supabase mostra só o resultado do ÚLTIMO comando de
--  uma execução. Rodar o arquivo inteiro exibe apenas o select do fim
--  ("arquivados_por_anonimo"), e os de cima passam despercebidos como se
--  não tivessem rodado. Para ver cada um, cole-o SOZINHO numa query nova.
--
--  (Ainda assim, o último select já prova o principal: ele consulta
--  itens.arquivado_em, então se ele respondeu um número em vez de erro,
--  a coluna existe.)

--  As colunas existem nas DUAS tabelas? Tem que dar 2. O app só liga o
--  recurso com as duas: com meia migração, o filtro do nível de cima
--  responderia 400 e a trilha inteira cairia para o modo offline.
select count(*) as colunas_no_lugar
from information_schema.columns
where table_schema = 'public'
  and column_name  = 'arquivado_em'
  and table_name in ('itens','temas');

--  Quanto foi arquivado — e quanto do arquivado AINDA conta como estudo.
--  É o segundo número que prova que arquivar não é excluir:
select
  (select count(*) from public.itens where arquivado_em is not null) as itens_arquivados,
  (select count(*) from public.temas where arquivado_em is not null) as temas_arquivados,
  (select count(*) from public.progresso p
     join public.itens i on i.id = p.item_id
    where i.arquivado_em is not null)                                as conclusoes_preservadas;

--  Nenhuma linha abaixo pode ter qualificador "true":
select tablename, policyname, cmd, qual::text as usando, with_check::text as checando
from pg_policies
where schemaname = 'public'
  and tablename in ('temas','itens','progresso')
order by tablename, cmd, policyname;

--  E, no PowerShell, o teste que vale — "o que deveria falhar, falha?".
--
--  ⚠ ATENÇÃO À FORMA DO TESTE: um UPDATE barrado por RLS **não** devolve
--  erro. A cláusula USING apenas não casa com nenhuma linha, e a resposta
--  é 204 — que parece sucesso. Por isso este teste usa um id REAL e pede
--  "return=representation": o que prova o bloqueio é o corpo vir VAZIO.
--
--    $k  = "<anon key>"; $base = "https://zezzpdhjjgqavtlxmgsp.supabase.co/rest/v1"
--    $id = "<uuid de um item SEU, copiado do painel>"
--    $h  = @{ apikey=$k; Authorization="Bearer $k"; "Content-Type"="application/json";
--             Prefer="return=representation" }
--    (Invoke-WebRequest -Uri "$base/itens?id=eq.$id" -Method Patch -Headers $h `
--       -Body '{"arquivado_em":"2020-01-01T00:00:00Z"}').Content
--
--  TEM que sair "[]". Se sair a linha do item, PARE: qualquer pessoa
--  arquiva a trilha de qualquer outra. Repita trocando itens por temas.
--
--  E o de sempre, que já pegou uma exposição real aqui — escrita anônima
--  em temas TEM que dar 401:
--
--    Invoke-RestMethod -Uri "$base/temas" -Method Post -Headers $h `
--      -Body '{"slug":"__x__","nome":"x","ordem":99}'

--  Depois do teste acima, a confirmação pelo lado do banco (tem que ser 0):
select count(*) as arquivados_por_anonimo
from public.itens where arquivado_em = '2020-01-01T00:00:00Z';
