/* Service worker da Trilha de Estudos.
   =====================================================================
   A regra que organiza este arquivo: ele cuida do CASCO (o HTML, o
   manifest, os ícones) e NUNCA dos dados.

   Toda chamada ao Supabase e ao CDN do SDK é de outra origem, e a
   primeira linha do handler de fetch devolve essas requisições ao
   navegador sem tocar nelas. Dado servido de cache seria pior que dado
   nenhum: você veria progresso velho achando que é o atual.

   E o documento é *network-first* de propósito. Um cache-first aqui
   serviria o HTML antigo depois de um git push, e a queixa seria "meu
   app não atualizou" — o erro mais fácil de cometer com service worker.
   ===================================================================== */

const CACHE = "trilha-casco-v4";

/* Só o que tem endereço fixo e é pequeno. O index.html não entra aqui:
   ele é guardado no primeiro acesso pelo próprio redePrimeiro(), então um
   arquivo faltando nunca derruba a instalação inteira. */
const CASCO = ["./manifest.json", "./icon-192.png", "./icon-512.png"];

/* A ÚNICA exceção à regra de não tocar em outra origem.
   O SDK do Supabase é CÓDIGO, não dado — e é ele que guarda e restaura a
   sessão. Sem ele o app instalado abre deslogado toda vez que a rede
   titubeia, e aí não sabe nem de quem é a trilha que tem guardada.
   supabase.co (dados e autenticação) continua sempre indo à rede. */
const SDK = "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2";

self.addEventListener("install", (e) => {
  e.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    /* allSettled, não addAll: se um ícone falhar, o resto ainda instala. */
    await Promise.allSettled([
      ...CASCO.map((u) => cache.add(u)),
      baixarSdk(cache, new Request(SDK)),
    ]);
    self.skipWaiting();
  })());
});

self.addEventListener("activate", (e) => {
  e.waitUntil((async () => {
    const nomes = await caches.keys();
    await Promise.all(nomes.filter((n) => n !== CACHE).map((n) => caches.delete(n)));
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;

  /* O SDK vem antes da checagem de origem — é a exceção descrita lá em cima. */
  if (req.url.startsWith(SDK)) { e.respondWith(sdkPrimeiroDoCache(e, req)); return; }

  const url = new URL(req.url);
  /* Qualquer outra origem = Supabase (dados, auth, realtime).
     Não interceptar: deixa passar exatamente como o navegador faria. */
  if (url.origin !== self.location.origin) return;

  const ehAsset = /\.(png|ico|svg|webmanifest)$/i.test(url.pathname) ||
                  url.pathname.endsWith("manifest.json");

  e.respondWith(ehAsset ? cachePrimeiro(req) : redePrimeiro(req));
});

/* Documento e demais arquivos da própria origem: tenta a rede, guarda a
   cópia boa, e só cai no cache quando a rede falha de verdade. */
async function redePrimeiro(req) {
  const cache = await caches.open(CACHE);
  try {
    const resp = await fetch(req);
    if (resp && resp.ok) cache.put(req, resp.clone());
    return resp;
  } catch (err) {
    const guardado = await cache.match(req);
    if (guardado) return guardado;
    /* Navegação offline para uma rota ainda não visitada: serve o
       documento que já temos. As rotas do app são hash, então o mesmo
       index.html atende #resumo, #mural e todos os temas. */
    if (req.mode === "navigate") {
      const idx = (await cache.match("./index.html")) || (await cache.match("./"));
      if (idx) return idx;
    }
    throw err;
  }
}

/* SDK: serve a cópia local na hora e atualiza atrás. Assim o app abre
   rápido, abre sem rede, e mesmo assim não fica preso numa versão velha —
   a próxima abertura já usa a que baixou agora. */
async function sdkPrimeiroDoCache(e, req) {
  const cache = await caches.open(CACHE);
  const guardado = await cache.match(req);
  if (guardado) {
    e.waitUntil(baixarSdk(cache, req).catch(() => {}));
    return guardado;
  }
  const resp = await fetch(req);
  e.waitUntil(guardarSdk(cache, req, resp.clone()).catch(() => {}));
  return resp;
}

async function baixarSdk(cache, req) {
  const resp = await fetch(req);
  return guardarSdk(cache, req, resp);
}

/* Reembala a resposta antes de guardar: o jsdelivr responde com um
   redirecionamento para o arquivo com versão, e o Cache API se recusa a
   guardar resposta redirecionada. Copiar o corpo tira essa marca. */
async function guardarSdk(cache, req, resp) {
  if (!resp || !resp.ok) return;
  const corpo = await resp.blob();
  await cache.put(req, new Response(corpo, {
    status: 200,
    headers: { "Content-Type": resp.headers.get("Content-Type") || "text/javascript" },
  }));
}

/* Ícones e manifest quase nunca mudam: servir do cache é instantâneo, e
   quando mudarem o CACHE novo (v5, v6…) invalida tudo de uma vez. */
async function cachePrimeiro(req) {
  const cache = await caches.open(CACHE);
  const guardado = await cache.match(req);
  if (guardado) return guardado;
  const resp = await fetch(req);
  if (resp && resp.ok) cache.put(req, resp.clone());
  return resp;
}
