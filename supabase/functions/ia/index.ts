/**
 * Edge Function "ia" — o único lugar onde a chave do modelo existe.
 * =====================================================================
 * A anon key do Supabase é pública de propósito: quem protege o banco são
 * as policies de RLS. A chave do Gemini NÃO tem nada atrás dela — quem
 * abrir o "ver fonte" gasta a sua cota. Por isso ela mora aqui, como
 * secret, e o navegador nunca a vê.
 *
 * Três decisões que sustentam o resto:
 *
 *  1. O CLIENTE MANDA IDS, NÃO CONTEÚDO. Esta função busca o tema, os
 *     itens e as anotações no banco usando o JWT de quem chamou — então o
 *     RLS continua valendo e ela só enxerga o que aquela conta enxergaria.
 *     Se o cliente mandasse o texto, ele poderia mandar o de outra pessoa.
 *
 *  2. O PROMPT MORA AQUI. O cliente escolhe entre ações conhecidas; ele
 *     não envia system prompt. Senão qualquer um com um JWT usaria a sua
 *     cota para o que quisesse.
 *
 *  3. O CONTADOR É ESCRITO COM A SERVICE_ROLE. O usuário só lê o próprio
 *     extrato: se pudesse escrever, zeraria o freio.
 *
 * POR QUE GEMINI E NÃO ANTHROPIC (2026-07-29): a conta da Anthropic exige
 * crédito mínimo pago. O Gemini tem camada gratuita. O contrato com o
 * index.html é EXATAMENTE o mesmo — "ping" devolve {ok,motivo,usadas,
 * limite}, as ações de proposta devolvem JSON e as de conversa devolvem
 * text/plain escrevendo — então o cliente não mudou uma linha.
 *
 * Sem SDK, fetch cru de propósito: o corpo é simples, e cada "npm:" a
 * menos é uma resolução a menos que pode falhar na hora do deploy.
 *
 * Deploy:
 *   supabase functions deploy ia
 *   supabase secrets set GEMINI_API_KEY=AIza...
 *   supabase secrets set GEMINI_MODELO=gemini-3.6-flash   # opcional
 */

import { createClient } from "npm:@supabase/supabase-js@2";

/* O modelo vem de secret com padrão razoável: se a camada gratuita deixar
   de servir este nome, é um "secrets set" e não um redeploy de código. */
const MODELO = Deno.env.get("GEMINI_MODELO") ?? "gemini-3.6-flash";
const API = "https://generativelanguage.googleapis.com/v1beta/models";

/* Busca na web DESLIGADA por padrão, e isto não é cautela: a camada
   gratuita do Gemini não inclui "Grounding with Google Search" — é
   "Not available", não cota baixa. Mandar a ferramenta junto faz TODA
   chamada de buscar_materiais morrer em 429, mesmo a primeira do dia.
   Fica atrás de secret para o dia em que houver faturamento na conta:
   "supabase secrets set GEMINI_BUSCA=1" e nada mais muda. */
const BUSCA_WEB = (Deno.env.get("GEMINI_BUSCA") ?? "0") === "1";
/* 12 e não 40: quando a chave era paga, o limite era dinheiro SEU por
   conta, e 40 era generoso. Na camada gratuita a cota diária é do Google
   sobre a CHAVE, compartilhada por todas as contas do app — há tier
   gratuito em 20 chamadas/dia. Em 40, este freio nunca chegava a frear:
   quem avisava era o erro do Google no meio de um pedido. */
const LIMITE_DIA = 12;          // chamadas por conta por dia
const ORIGENS = [
  "https://ricardocolombo01.github.io",
  "http://localhost:8765",
  "http://127.0.0.1:8765",
];

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");

/* ------------------------------ HTTP ------------------------------ */

function cabecalhosCors(origem: string | null) {
  const permitida = origem && ORIGENS.includes(origem) ? origem : ORIGENS[0];
  return {
    "Access-Control-Allow-Origin": permitida,
    /* Tem que listar TODO cabeçalho que o navegador vai mandar. Um que
       falte aqui — foi o "apikey" — faz o preflight recusar e o pedido
       nem sai: o console mostra erro de CORS e o app parece morto, sem
       nenhum registro do lado do servidor. */
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function json(status: number, corpo: unknown, origem: string | null) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...cabecalhosCors(origem), "Content-Type": "application/json; charset=utf-8" },
  });
}

/* --------------------------- Contexto ---------------------------- */
/* O que a IA sabe que um chat genérico não sabe: o que você já concluiu,
   o que anotou e o que salvou. É isto que transforma "como estudar Git"
   em "o que estudar em Git, no seu ponto". */

type Ctx = { titulo: string; texto: string };

async function montarContexto(supa: any, temaId: string | null, itemId: string | null): Promise<Ctx> {
  if (!temaId) return { titulo: "", texto: "" };

  const { data: temas, error } = await supa
    .from("temas")
    .select("id,nome,resumo,itens(id,texto,detalhe,nota,ordem),materiais(titulo,url,tipo,ordem)")
    .eq("id", temaId)
    .limit(1);

  /* Erro aqui quase sempre é a coluna "nota" ou a tabela "materiais" não
     existirem ainda (migrações opcionais). Tenta o mínimo antes de desistir. */
  let tema = temas?.[0];
  if (error || !tema) {
    const { data } = await supa
      .from("temas").select("id,nome,resumo,itens(id,texto,detalhe,ordem)")
      .eq("id", temaId).limit(1);
    tema = data?.[0];
  }
  if (!tema) return { titulo: "", texto: "" };

  const itens = (tema.itens ?? []).sort((a: any, b: any) => a.ordem - b.ordem);
  const { data: prog } = await supa.from("progresso").select("item_id,concluido_em");
  const feitos = new Map<string, string>((prog ?? []).map((p: any) => [p.item_id, p.concluido_em]));

  const linhas = itens.map((i: any) => {
    const quando = feitos.get(i.id);
    const marca = quando ? `[x] concluído em ${String(quando).slice(0, 10)}` : "[ ] pendente";
    const foco = i.id === itemId ? "  <<< ITEM EM FOCO" : "";
    const nota = i.nota ? `\n      anotação da pessoa: ${i.nota}` : "";
    const det = i.detalhe ? ` (${i.detalhe})` : "";
    return `  - ${marca} ${i.texto}${det}${foco}${nota}`;
  });

  const mats = (tema.materiais ?? []).map((m: any) => `  - [${m.tipo}] ${m.titulo} ${m.url || ""}`.trim());

  const texto = [
    `Tema: ${tema.nome}`,
    tema.resumo ? `Resumo do tema: ${tema.resumo}` : "",
    "",
    "Itens da trilha desta pessoa:",
    ...linhas,
    mats.length ? "\nMateriais que ela já salvou neste tema:" : "",
    ...mats,
  ].filter(Boolean).join("\n");

  return { titulo: tema.nome, texto };
}

/* ---------------------------- Prompts ---------------------------- */

const BASE =
  "Você ajuda uma pessoa a estudar programação e IA, dentro do app de trilha de estudos dela. " +
  "Responda em português do Brasil. Seja direto e específico: ela não quer um panorama do assunto, " +
  "quer o próximo passo dela. Use o contexto abaixo — o que ela já concluiu, o que anotou e o que " +
  "salvou — em vez de dar conselho genérico. Não invente item, data ou progresso que não esteja no contexto.";

/* Sem busca, o risco muda de lugar: o modelo não erra o ASSUNTO, erra o
   ENDEREÇO. Link profundo inventado é o pior resultado possível aqui —
   entra na lista parecendo bom e só se revela morto semanas depois, na
   hora de estudar. Endereço vazio é honesto e ainda serve: o título já é
   o suficiente para achar. Por isso a instrução manda deixar vazio. */
const REGRA_SEM_BUSCA =
  "\n\nATENÇÃO: você NÃO tem acesso à internet nesta chamada. Então sugira apenas materiais " +
  "consagrados, que você tem certeza de que existem. No campo url, escreva SÓ um endereço " +
  "principal do qual tenha certeza — a página inicial do site, do canal ou da editora. " +
  "É MELHOR DEIXAR url VAZIO do que arriscar: nunca escreva link profundo, isto é, endereço " +
  "de vídeo específico, de aula específica ou com código de identificação. Sempre que url " +
  "ficar vazio, comece o campo nota com o que a pessoa deve procurar, no formato " +
  "\"procure por ... no YouTube\".";

const REGRA_COM_BUSCA =
  "\n\nPesquise na web e traga, em url, o endereço real encontrado na pesquisa — nunca um " +
  "endereço inventado ou adivinhado.";

const PROMPTS: Record<string, string> = {
  explicar:
    BASE + "\n\nExplique o ITEM EM FOCO no nível de quem já concluiu os itens marcados e ainda não " +
    "concluiu os pendentes. Comece pela ideia central em uma frase, depois o porquê, depois um exemplo " +
    "concreto e pequeno. Se houver anotação da pessoa sobre o item, corrija o que estiver errado nela " +
    "e complete o que faltar. No máximo uns 300 palavras.",

  chat:
    BASE + "\n\nVocê está numa conversa sobre este tema. Responda o que foi perguntado, sem preâmbulo " +
    "e sem repetir a pergunta. Se a pergunta for ampla demais para uma resposta útil, faça UMA pergunta " +
    "de volta em vez de despejar tudo.",

  buscar_materiais:
    BASE + "\n\nSugira materiais de estudo para este tema: cursos, vídeos, artigos e livros. " +
    "Priorize material em português quando a qualidade for equivalente, e material gratuito. " +
    "NÃO sugira nada que já esteja na lista de materiais salvos. Traga entre 3 e 6 sugestões." +
    (BUSCA_WEB ? REGRA_COM_BUSCA : REGRA_SEM_BUSCA),

  cartoes:
    BASE + "\n\nGere cartões de revisão (pergunta e resposta) a partir dos itens concluídos e, " +
    "principalmente, das anotações da pessoa — o valor está em revisar o que ELA registrou, não o " +
    "assunto em geral. Pergunta curta e específica; resposta de duas a quatro frases. " +
    "Entre 4 e 10 cartões. Se houver ITEM EM FOCO, gere só sobre ele.",
};

const ESQUEMAS: Record<string, unknown> = {
  buscar_materiais: {
    type: "object",
    properties: {
      sugestoes: {
        type: "array",
        items: {
          type: "object",
          properties: {
            titulo: { type: "string" },
            url: { type: "string" },
            tipo: { type: "string", enum: ["video", "curso", "artigo", "livro", "outro"] },
            nota: { type: "string", description: "Uma frase: por que vale a pena para esta pessoa." },
          },
          required: ["titulo", "url", "tipo", "nota"],
          additionalProperties: false,
        },
      },
    },
    required: ["sugestoes"],
    additionalProperties: false,
  },
  cartoes: {
    type: "object",
    properties: {
      cartoes: {
        type: "array",
        items: {
          type: "object",
          properties: {
            pergunta: { type: "string" },
            resposta: { type: "string" },
            item_id: { type: "string", description: "Id do item da trilha, ou vazio se for do tema todo." },
          },
          required: ["pergunta", "resposta", "item_id"],
          additionalProperties: false,
        },
      },
    },
    required: ["cartoes"],
    additionalProperties: false,
  },
};

/* ---------------------------- Gemini ----------------------------- */

/* "additionalProperties" existe nos nossos esquemas porque a Anthropic
   exigia. O Gemini 3 aceita, mas as gerações 2.x recusam com 400 — e o
   modelo é configurável por secret, então este arquivo tem que servir a
   qualquer uma delas. Cai fora sem perda: campo a mais que o modelo
   inventasse seria ignorado na leitura de qualquer jeito. */
function esquemaGemini(no: any): any {
  if (Array.isArray(no)) return no.map(esquemaGemini);
  if (!no || typeof no !== "object") return no;
  const saida: any = {};
  for (const [k, v] of Object.entries(no)) {
    if (k === "additionalProperties") continue;
    saida[k] = esquemaGemini(v);
  }
  return saida;
}

/* O Gemini chama o interlocutor de "model", não de "assistant". Traduzir
   aqui e não no cliente: o histórico que o index.html guarda é o dele. */
function conteudos(mensagens: { role: string; content: string }[]) {
  return mensagens.map((m) => ({
    role: m.role === "assistant" ? "model" : "user",
    parts: [{ text: m.content }],
  }));
}

type Pedido = {
  system: string;
  mensagens: { role: string; content: string }[];
  maxTokens: number;
  esquema?: unknown;
  buscarNaWeb?: boolean;
};

function corpoGemini(p: Pedido) {
  const corpo: any = {
    systemInstruction: { parts: [{ text: p.system }] },
    contents: conteudos(p.mensagens),
    /* Folga proposital no teto: o raciocínio do modelo é cobrado deste
       mesmo orçamento. Apertado, a resposta termina em MAX_TOKENS com
       texto vazio — falha muda, que parece "a IA não respondeu". Teto
       alto não custa nada quando não é usado. */
    generationConfig: { maxOutputTokens: p.maxTokens },
  };
  if (p.esquema) {
    corpo.generationConfig.responseMimeType = "application/json";
    corpo.generationConfig.responseSchema = esquemaGemini(p.esquema);
  }
  /* Só entra com GEMINI_BUSCA=1, ou seja, com faturamento na conta. A
     busca roda no servidor do Google: nada de scraping nosso e nada de
     chave de buscador. */
  if (p.buscarNaWeb) corpo.tools = [{ google_search: {} }];
  return corpo;
}

function cabecalhosGemini() {
  /* Chave no cabeçalho e não em "?key=": query string entra em log de
     proxy e em histórico de erro, cabeçalho não. */
  return {
    "x-goog-api-key": GEMINI_API_KEY!,
    "Content-Type": "application/json",
  };
}

/* Erro do Gemini vem em {error:{message,status}}. Sem isto, o app
   mostraria só "502" e não "modelo inexistente" ou "cota estourada". */
async function erroGemini(r: Response): Promise<Error> {
  let msg = `${r.status}`;
  try {
    const j = JSON.parse(await r.text());
    if (j?.error?.message) msg = j.error.message;
  } catch { /* corpo não era JSON; fica o status */ }
  const e = new Error(msg);
  (e as any).status = r.status;
  return e;
}

/* O raciocínio do modelo chega como parte irmã do texto, marcada com
   thought:true. Não filtrar vaza o rascunho dentro da resposta. */
function textoDasPartes(partes: any[]): string {
  return (partes ?? [])
    .filter((p: any) => p?.thought !== true && typeof p?.text === "string")
    .map((p: any) => p.text)
    .join("");
}

function usoDe(resp: any) {
  const u = resp?.usageMetadata ?? {};
  return { entrada: u.promptTokenCount ?? 0, saida: u.candidatesTokenCount ?? 0 };
}

/* SAFETY / blockReason é recusa, não falha: o cliente já tem uma tela
   para "a IA recusou". Distinguir evita mostrar erro técnico. */
function recusa(resp: any): string | null {
  const bloqueio = resp?.promptFeedback?.blockReason;
  if (bloqueio) return String(bloqueio);
  const fim = resp?.candidates?.[0]?.finishReason;
  if (fim && ["SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII"].includes(String(fim))) {
    return String(fim);
  }
  return null;
}

async function gerar(corpo: unknown): Promise<any> {
  const r = await fetch(`${API}/${MODELO}:generateContent`, {
    method: "POST",
    headers: cabecalhosGemini(),
    body: JSON.stringify(corpo),
  });
  if (!r.ok) throw await erroGemini(r);
  return r.json();
}

/* Cada "data:" do SSE é um GenerateContentResponse completo. O corte é
   por linha inteira: pedaço que chegou partido no meio de um JSON fica
   no buffer até fechar, em vez de virar erro de parse. */
async function* fluxoGemini(corpo: unknown): AsyncGenerator<any> {
  const r = await fetch(`${API}/${MODELO}:streamGenerateContent?alt=sse`, {
    method: "POST",
    headers: cabecalhosGemini(),
    body: JSON.stringify(corpo),
  });
  /* O fetch já resolveu os cabeçalhos aqui, então uma chave errada ou um
     modelo inexistente é pego ANTES de abrir a resposta para o cliente —
     e vira um 502 com mensagem, não um texto truncado no meio da tela. */
  if (!r.ok) throw await erroGemini(r);

  const leitor = r.body!.getReader();
  const dec = new TextDecoder();
  let buffer = "";
  while (true) {
    const { done, value } = await leitor.read();
    if (done) break;
    buffer += dec.decode(value, { stream: true });
    let corte: number;
    while ((corte = buffer.indexOf("\n")) >= 0) {
      const linha = buffer.slice(0, corte).trim();
      buffer = buffer.slice(corte + 1);
      if (!linha.startsWith("data:")) continue;
      const cru = linha.slice(5).trim();
      if (!cru || cru === "[DONE]") continue;
      try { yield JSON.parse(cru); } catch { /* não fechou: ignora */ }
    }
  }
}

/* ---------------------------- Handler ---------------------------- */

Deno.serve(async (req) => {
  const origem = req.headers.get("Origin");
  if (req.method === "OPTIONS") return new Response("ok", { headers: cabecalhosCors(origem) });
  if (req.method !== "POST") return json(405, { erro: "Use POST." }, origem);

  /* 1. Quem é. Sem conta, sem IA — a cota é sua. */
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json(401, { erro: "Entre com a sua conta para usar a IA." }, origem);

  const supaUsuario = createClient(SUPABASE_URL, ANON, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const { data: { user } } = await supaUsuario.auth.getUser();
  if (!user) return json(401, { erro: "Sessão inválida ou expirada. Entre de novo." }, origem);

  const admin = createClient(SUPABASE_URL, SERVICE, { auth: { persistSession: false } });
  const hoje = new Date().toISOString().slice(0, 10);
  const { data: uso } = await admin
    .from("ia_uso").select("chamadas").eq("user_id", user.id).eq("dia", hoje).maybeSingle();
  const usadas = uso?.chamadas ?? 0;

  /* 2. O que foi pedido. */
  let corpo: any;
  try { corpo = await req.json(); } catch { return json(400, { erro: "Corpo inválido." }, origem); }
  const acao = String(corpo?.acao ?? "");

  /* "ping" não chama a IA e não gasta token nenhum: é como o app descobre
     se a função existe, se a chave está configurada e quanto do limite do
     dia ainda resta. Sem ele, o único jeito de saber seria tentar uma ação
     de verdade — e pagar por ela para descobrir que não dava.
     Responde 200 mesmo com o limite estourado: a resposta É o aviso. */
  if (acao === "ping") {
    return json(200, {
      ok: Boolean(GEMINI_API_KEY),
      motivo: GEMINI_API_KEY ? null : "sem_chave",
      usadas,
      limite: LIMITE_DIA,
    }, origem);
  }

  if (!PROMPTS[acao]) return json(400, { erro: "Ação desconhecida." }, origem);
  if (!GEMINI_API_KEY) {
    return json(503, { erro: "A chave do Gemini ainda não foi configurada nesta função." }, origem);
  }

  /* 3. Freio por conta, depois de saber que é uma ação que gasta.
     ┌─ DECISÃO EM ABERTO (ver conversa de 2026-07-29) ────────────────┐
     │ Este freio é por conta. Na camada gratuita a cota diária é da    │
     │ CHAVE, compartilhada por todo mundo que usa o app — uma conta     │
     │ sozinha ainda pode secar o dia dos outros sem estourar o seu 40.  │
     │ Se você quiser um teto global, ele entra aqui: soma chamadas de   │
     │ ia_uso no dia (sem filtrar user_id) e recusa acima do teto.       │
     └──────────────────────────────────────────────────────────────────┘ */
  if (usadas >= LIMITE_DIA) {
    return json(429, { erro: `Limite de ${LIMITE_DIA} usos da IA por dia atingido. Volta amanhã.` }, origem);
  }

  const temaId = corpo?.temaId ? String(corpo.temaId) : null;
  const itemId = corpo?.itemId ? String(corpo.itemId) : null;
  const ctx = await montarContexto(supaUsuario, temaId, itemId);
  if (temaId && !ctx.texto) return json(404, { erro: "Tema não encontrado nesta conta." }, origem);

  const system = `${PROMPTS[acao]}\n\n=== CONTEXTO ===\n${ctx.texto}`;
  const registrar = (u: { entrada: number; saida: number }) =>
    admin.rpc("registrar_uso_ia", {
      p_user: user.id,
      p_entrada: u.entrada,
      p_saida: u.saida,
    }).then(() => {}, () => {});

  /* ----- Ações que devolvem JSON: proposta para você aceitar ----- */
  if (acao === "buscar_materiais" || acao === "cartoes") {
    const pedido: Pedido = {
      system,
      maxTokens: 16000,
      esquema: ESQUEMAS[acao],
      buscarNaWeb: acao === "buscar_materiais" && BUSCA_WEB,
      mensagens: [{
        role: "user",
        content: acao === "buscar_materiais"
          ? "Pesquise e sugira materiais para este tema."
          : "Gere os cartões de revisão.",
      }],
    };

    let resposta: any;
    try {
      resposta = await gerar(corpoGemini(pedido));
    } catch (e) {
      /* Rede de segurança para uma incompatibilidade que depende do
         modelo: no Gemini 3 o formato estruturado convive com a busca,
         nas gerações 2.x não. Se der 400, repete sem o esquema e pede o
         JSON no próprio texto — o leitor tolerante abaixo dá conta. */
      const msg = (e as Error).message || "";
      /* 429 com a busca ligada tem uma causa só, e a mensagem do Google
         não conta qual: a camada gratuita não inclui grounding. Sem esta
         dica, o sintoma parece "estourei meu limite de uso". */
      if ((e as any)?.status === 429 && pedido.buscarNaWeb) {
        return json(502, {
          erro: "A busca na web não está incluída no plano gratuito do Gemini. " +
                "Desligue com: supabase secrets set GEMINI_BUSCA=0",
        }, origem);
      }
      if ((e as any)?.status !== 400) {
        return json(502, { erro: "A IA não respondeu: " + msg }, origem);
      }
      try {
        delete pedido.esquema;
        pedido.system += "\n\nResponda APENAS com um objeto JSON válido, sem texto antes ou depois, " +
          "no formato: " + JSON.stringify(ESQUEMAS[acao]);
        resposta = await gerar(corpoGemini(pedido));
      } catch (e2) {
        return json(502, { erro: "A IA não respondeu: " + (e2 as Error).message }, origem);
      }
    }
    await registrar(usoDe(resposta));

    if (recusa(resposta)) {
      return json(200, { recusado: true, erro: "A IA recusou este pedido." }, origem);
    }

    const cand = resposta?.candidates?.[0];
    const texto = textoDasPartes(cand?.content?.parts).trim();
    if (!texto && cand?.finishReason === "MAX_TOKENS") {
      return json(502, { erro: "A IA gastou o limite de tokens pensando e não sobrou resposta. Tente de novo." }, origem);
    }

    let dados: any = null;
    try {
      dados = JSON.parse(texto);
    } catch {
      /* Rede de segurança: com ferramenta de busca no meio, às vezes sobra
         texto em volta do JSON. Pega do primeiro { ao último }. */
      const i = texto.indexOf("{"), f = texto.lastIndexOf("}");
      if (i >= 0 && f > i) { try { dados = JSON.parse(texto.slice(i, f + 1)); } catch { /* desiste */ } }
    }
    if (!dados) return json(502, { erro: "A IA respondeu num formato que não consegui ler." }, origem);
    return json(200, dados, origem);
  }

  /* ----- Ações em texto: chegam escrevendo, como uma conversa ----- */
  const mensagens = acao === "chat"
    ? (Array.isArray(corpo?.mensagens) ? corpo.mensagens : [])
        .filter((m: any) => (m?.role === "user" || m?.role === "assistant") && typeof m?.content === "string")
        .slice(-12)                                   // história curta: o contexto pesado já vai no system
        .map((m: any) => ({ role: m.role, content: String(m.content).slice(0, 4000) }))
    : [{ role: "user", content: "Explique o item em foco." }];

  if (!mensagens.length) return json(400, { erro: "Nada a responder." }, origem);

  /* Abre o fluxo ANTES de montar a resposta: erro de chave ou de modelo
     ainda pode virar um JSON de erro aqui. Depois de começar a escrever
     no cliente, só resta avisar dentro do próprio texto. */
  const gerador = fluxoGemini(corpoGemini({ system, mensagens, maxTokens: 8000 }));
  let primeiro: any;
  try {
    const inicio = await gerador.next();
    if (inicio.done) return json(502, { erro: "A IA não respondeu nada." }, origem);
    primeiro = inicio.value;
  } catch (e) {
    return json(502, { erro: "A IA não respondeu: " + (e as Error).message }, origem);
  }

  /* Recusa aqui sai em TEXTO, não em JSON: quem chama é o iaStream(), que
     só concatena bytes. Um {"recusado":true} apareceria cru na tela — o
     contrato de uma ação de conversa é texto do começo ao fim. */
  if (recusa(primeiro)) {
    return new Response("A IA recusou responder isto.", {
      headers: { ...cabecalhosCors(origem), "Content-Type": "text/plain; charset=utf-8" },
    });
  }

  /* Texto puro em vez de SSE: o cliente só precisa ir concatenando os
     pedaços, sem parser de eventos. Menos código dos dois lados. */
  const corrente = new ReadableStream({
    async start(controller) {
      const enc = new TextEncoder();
      let uso = usoDe(primeiro);
      let fim = primeiro?.candidates?.[0]?.finishReason;
      try {
        controller.enqueue(enc.encode(textoDasPartes(primeiro?.candidates?.[0]?.content?.parts)));
        for await (const ev of gerador) {
          /* O usageMetadata é cumulativo: vale o do último pedaço. */
          const u = usoDe(ev);
          if (u.entrada || u.saida) uso = u;
          fim = ev?.candidates?.[0]?.finishReason ?? fim;
          controller.enqueue(enc.encode(textoDasPartes(ev?.candidates?.[0]?.content?.parts)));
        }
        /* Corte no meio do caminho é silencioso: o fluxo simplesmente para
           e a frase fica pela metade, sem nada indicando por quê. Uma
           linha explicando vale mais que uma resposta que parece completa. */
        if (fim && fim !== "STOP") {
          controller.enqueue(enc.encode(
            fim === "MAX_TOKENS"
              ? "\n\n[a resposta foi cortada no limite de tamanho]"
              : `\n\n[a resposta foi interrompida: ${fim}]`
          ));
        }
      } catch (e) {
        controller.enqueue(enc.encode("\n\n[a resposta foi interrompida: " + (e as Error).message + "]"));
      } finally {
        await registrar(uso);
        controller.close();
      }
    },
  });

  return new Response(corrente, {
    headers: { ...cabecalhosCors(origem), "Content-Type": "text/plain; charset=utf-8" },
  });
});
