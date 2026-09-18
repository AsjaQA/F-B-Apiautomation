#!/usr/bin/env node
/**
 * dev-mock-server.js
 *
 * A tiny, dependency-free mock of the Catalog/Console APIs, used only to
 * smoke-test this automation pipeline (variable chaining, report
 * generation, exit codes) without needing real credentials or a live
 * environment. It is NOT part of the CI workflow and should never be
 * pointed at from a real base_url — it always returns synthetic data.
 *
 * Behavior:
 *   - POST            -> 201, body echoed back with an "id" (and "data.id")
 *                         added so both APIs' id-capture scripts succeed.
 *   - PUT / PATCH     -> 200, body echoed back the same way.
 *   - GET             -> 200, a small synthetic list/object.
 *   - DELETE          -> 204, no body.
 *
 * Usage: node scripts/dev-mock-server.js [port]   (default port 4000)
 */
const http = require("http");

const port = Number(process.argv[2] || 4000);
let counter = 1000;

function nextId() {
  counter += 1;
  return counter;
}

function readBody(req) {
  return new Promise((resolve) => {
    let raw = "";
    req.on("data", (chunk) => (raw += chunk));
    req.on("end", () => {
      if (!raw) return resolve({});
      try {
        resolve(JSON.parse(raw));
      } catch (e) {
        resolve({});
      }
    });
  });
}

const server = http.createServer(async (req, res) => {
  const method = req.method.toUpperCase();
  const body = await readBody(req);

  if (method === "DELETE") {
    res.writeHead(204);
    return res.end();
  }

  if (method === "GET") {
    res.writeHead(200, { "content-type": "application/json" });
    return res.end(
      JSON.stringify({
        data: [{ ...body, id: nextId() }],
        page: 1,
        size: 20,
        total: 1,
      })
    );
  }

  // POST / PUT / PATCH
  const status = method === "POST" ? 201 : 200;
  const id = nextId();
  const echoed = { ...body, id, code: body.code || `CODE${id}` };
  const responseBody = { ...echoed, data: echoed };
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(responseBody));
});

server.listen(port, () => {
  console.log(`dev-mock-server listening on http://localhost:${port}`);
});
