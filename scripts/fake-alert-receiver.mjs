#!/usr/bin/env node
/**
 * Local loopback webhook receiver for verifying the Grafana alert delivery
 * path (OTel plan 阶段 6). Prints each incoming Grafana webhook payload to
 * stdout and keeps a rolling count, so an alert firing is observable without
 * any external channel (飞书/微信/Slack) — those URLs are external creds.
 *
 * Usage: node scripts/fake-alert-receiver.mjs [port]   (default 9099)
 */
import http from "node:http";

const port = Number(process.argv[2] ?? 9099);
let count = 0;

const server = http.createServer((req, res) => {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", () => {
    count += 1;
    const now = new Date().toISOString();
    console.log(`[${now}] #${count} ${req.method} ${req.url}`);
    try {
      const parsed = JSON.parse(body);
      const alerts = parsed.alerts ?? [parsed];
      for (const a of alerts) {
        console.log(
          `  status=${a.status} labels=${JSON.stringify(a.labels ?? {})} ` +
            `summary=${JSON.stringify(a.annotations?.summary ?? a.title ?? "")}`,
        );
      }
    } catch {
      console.log(`  (non-JSON body, ${body.length} bytes)`);
    }
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ ok: true, count }));
  });
});

server.listen(port, "127.0.0.1", () => {
  console.log(`fake-alert-receiver listening on http://127.0.0.1:${port}`);
});
