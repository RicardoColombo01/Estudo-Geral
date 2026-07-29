/**
 * Edge Function "ia" — o único lugar onde a chave da Anthropic existe.
 * =====================================================================
 * A anon key do Supabase é pública de propósito: quem protege o banco são
 * as policies de RLS. A chave da Anthropic NÃO tem nada atrás dela — quem
 * abrir o "ver fonte" gasta o seu dinheiro. Por isso ela mora aqui, como
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
 *     chave para o que quisesse.
 *
 *  3. O CONTADOR É ESCRITO COM A SERVICE_ROLE. O usuário só lê o próprio
 *     extrato: se pudesse escrever, zeraria o freio.
 *
 * Deploy:
 *   supabase functions deploy ia
 *   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
 */

import Anthropic from "npm:@anthropic-ai/sdk";
import { createClient } from "npm:@supabase/supabase-js@2";

const MODELO = "claude-opus-5";
const LIMITE_DIA = 40;          // chamadas por conta por dia
const ORIGENS = [
  "https://ricardocolombo01.github.io",
  "http://localhost:8765",
  "http://127.0.0.1:8765",
];

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");

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
    BASE + "\n\nPesquise na web materiais de estudo para este tema: cursos, vídeos, artigos e livros. " +
    "Priorize material em português quando a qualidade for equivalente, e material gratuito. " +
    "NÃO sugira nada que já esteja na lista de materiais salvos. Traga entre 3 e 6 sugestões, " +
    "cada uma com o endereço real encontrado na pesquisa — nunca um endereço inventado ou adivinhado.",

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

/* ---------------------------- Handler ---------------------------- */

Deno.serve(async (req) => {
  const origem = req.headers.get("Origin");
  if (req.method === "OPTIONS") return new Response("ok", { headers: cabecalhosCors(origem) });
  if (req.method !== "POST") return json(405, { erro: "Use POST." }, origem);

  /* 1. Quem é. Sem conta, sem IA — a chave é paga. */
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
      ok: Boolean(ANTHROPIC_API_KEY),
      motivo: ANTHROPIC_API_KEY ? null : "sem_chave",
      usadas,
      limite: LIMITE_DIA,
    }, origem);
  }

  if (!PROMPTS[acao]) return json(400, { erro: "Ação desconhecida." }, origem);
  if (!ANTHROPIC_API_KEY) {
    return json(503, { erro: "A chave da Anthropic ainda não foi configurada nesta função." }, origem);
  }

  /* 3. Freio por conta, depois de saber que é uma ação que gasta. */
  if (usadas >= LIMITE_DIA) {
    return json(429, { erro: `Limite de ${LIMITE_DIA} usos da IA por dia atingido. Volta amanhã.` }, origem);
  }

  const temaId = corpo?.temaId ? String(corpo.temaId) : null;
  const itemId = corpo?.itemId ? String(corpo.itemId) : null;
  const ctx = await montarContexto(supaUsuario, temaId, itemId);
  if (temaId && !ctx.texto) return json(404, { erro: "Tema não encontrado nesta conta." }, origem);

  const anthropic = new Anthropic({ apiKey: ANTHROPIC_API_KEY });
  const system = `${PROMPTS[acao]}\n\n=== CONTEXTO ===\n${ctx.texto}`;
  const registrar = (u: any) =>
    admin.rpc("registrar_uso_ia", {
      p_user: user.id,
      p_entrada: u?.input_tokens ?? 0,
      p_saida: u?.output_tokens ?? 0,
    }).then(() => {}, () => {});

  /* ----- Ações que devolvem JSON: proposta para você aceitar ----- */
  if (acao === "buscar_materiais" || acao === "cartoes") {
    const pedido: any = {
      model: MODELO,
      max_tokens: 8000,
      system,
      output_config: { effort: "medium", format: { type: "json_schema", schema: ESQUEMAS[acao] } },
      messages: [{ role: "user", content: acao === "buscar_materiais"
        ? "Pesquise e sugira materiais para este tema."
        : "Gere os cartões de revisão." }],
    };
    /* A busca na web roda no servidor da Anthropic: nada de scraping nosso
       e nada de chave de buscador. A filtragem já vem embutida nesta
       versão da ferramenta — declarar code_execution junto só confundiria
       o modelo com dois ambientes. */
    if (acao === "buscar_materiais") {
      pedido.tools = [
        { type: "web_search_20260209", name: "web_search", max_uses: 5 },
        { type: "web_fetch_20260209", name: "web_fetch", max_uses: 3 },
      ];
    }

    let resposta: any;
    try {
      resposta = await anthropic.messages.create(pedido);
    } catch (e) {
      /* Rede de segurança para uma incompatibilidade que só aparece em
         produção: o formato estruturado não convive com o recurso de
         citações, e a busca na web traz citações junto. Se der 400,
         repete sem o formato e pede o JSON no próprio texto. */
      const msg = (e as Error).message || "";
      const ehQuatrocentos = (e as any)?.status === 400 || /\b400\b/.test(msg);
      if (!ehQuatrocentos) {
        return json(502, { erro: "A IA não respondeu: " + msg }, origem);
      }
      try {
        delete pedido.output_config.format;
        pedido.system = pedido.system +
          "\n\nResponda APENAS com um objeto JSON válido, sem texto antes ou depois, " +
          "no formato: " + JSON.stringify(ESQUEMAS[acao]);
        resposta = await anthropic.messages.create(pedido);
      } catch (e2) {
        return json(502, { erro: "A IA não respondeu: " + (e2 as Error).message }, origem);
      }
    }
    await registrar(resposta.usage);

    if (resposta.stop_reason === "refusal") {
      return json(200, { recusado: true, erro: "A IA recusou este pedido." }, origem);
    }

    const texto = (resposta.content ?? [])
      .filter((b: any) => b.type === "text").map((b: any) => b.text).join("").trim();
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

  const fluxo = anthropic.messages.stream({
    model: MODELO,
    max_tokens: 4000,
    system,
    output_config: { effort: "medium" },
    messages: mensagens,
  });

  /* Texto puro em vez de SSE: o cliente só precisa ir concatenando os
     pedaços, sem parser de eventos. Menos código dos dois lados. */
  const corrente = new ReadableStream({
    async start(controller) {
      const enc = new TextEncoder();
      try {
        for await (const ev of fluxo) {
          if (ev.type === "content_block_delta" && (ev as any).delta?.type === "text_delta") {
            controller.enqueue(enc.encode((ev as any).delta.text));
          }
        }
        const final = await fluxo.finalMessage();
        await registrar(final.usage);
      } catch (e) {
        controller.enqueue(enc.encode("\n\n[a resposta foi interrompida: " + (e as Error).message + "]"));
      } finally {
        controller.close();
      }
    },
  });

  return new Response(corrente, {
    headers: { ...cabecalhosCors(origem), "Content-Type": "text/plain; charset=utf-8" },
  });
});
