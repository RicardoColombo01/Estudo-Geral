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

const CACHE = "trilha-casco-v3";

/* Só o que tem endereço fixo e é pequeno. O index.html não entra aqui:
   ele é guardado no primeiro acesso pelo próprio redePrimeiro(), então um
   arquivo faltando nunca derruba a instalação inteira. */
const CASCO = ["./manifest.json", "./icon-192.png", "./icon-512.png"];

self.addEventListener("install", (e) => {
  e.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    /* allSettled, não addAll: se um ícone falhar, o resto ainda instala. */
    await Promise.allSettled(CASCO.map((u) => cache.add(u)));
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

  const url = new URL(req.url);
  /* Outra origem = Supabase (dados, auth, realtime) ou o CDN do SDK.
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

/* Ícones e manifest quase nunca mudam: servir do cache é instantâneo, e
   quando mudarem o CACHE novo (v4, v5…) invalida tudo de uma vez. */
async function cachePrimeiro(req) {
  const cache = await caches.open(CACHE);
  const guardado = await cache.match(req);
  if (guardado) return guardado;
  const resp = await fetch(req);
  if (resp && resp.ok) cache.put(req, resp.clone());
  return resp;
}
