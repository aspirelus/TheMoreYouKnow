const http = require("node:http");

function createServer() {
  return http.createServer((request, response) => {
    if (request.url === "/health") {
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify({ status: "ok" }));
      return;
    }

    response.writeHead(200, { "content-type": "text/plain" });
    response.end("Hello from the CircleCI demo!\n");
  });
}

if (require.main === module) {
  createServer().listen(3000, "0.0.0.0", () => {
    console.log("Demo app listening on port 3000");
  });
}

module.exports = { createServer };