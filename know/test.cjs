const assert = require("node:assert/strict");
const test = require("node:test");
const { createServer } = require("./index");

test("GET /health returns an OK status", async (t) => {
  const server = createServer();

  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => server.close());

  const { port } = server.address();
  const response = await fetch(`http://127.0.0.1:${port}/health`);

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "ok" });
});