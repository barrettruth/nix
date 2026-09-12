import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  chmodSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
  existsSync,
} from "node:fs";
import { Server } from "node:http";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, test } from "node:test";
import { OAuth2Client } from "google-auth-library";
import { z } from "zod";
import * as listTasks from "./build/tools/list-tasks.js";
import * as listTaskLists from "./build/tools/list-task-lists.js";

const temporary = mkdtempSync(join(tmpdir(), "mcp-gtasks-"));
process.env.GOOGLE_TASKS_MCP_TOKEN_PATH = join(
  temporary,
  "state",
  "tokens.json",
);
process.env.GOOGLE_OAUTH_CREDENTIALS = join(temporary, "oauth.json");
writeFileSync(
  process.env.GOOGLE_OAUTH_CREDENTIALS,
  JSON.stringify({
    installed: { client_id: "test-client", client_secret: "test-secret" },
  }),
);
after(() => rmSync(temporary, { recursive: true, force: true }));
const auth = await import("./build/auth.js");
const authenticate = await import("./build/tools/authenticate.js");
const testTokens = {
  access_token: "test-access",
  refresh_token: "test-refresh",
  expiry_date: Date.now() + 3600 * 1000,
};

function callback(flow, params) {
  const url = new URL(flow.redirectUri);
  url.search = new URLSearchParams(params).toString();
  return fetch(url);
}

async function flowFixture(t) {
  rmSync(auth.TOKEN_PATH, { force: true });
  const flow = await auth.startAuthFlow();
  void flow.completed.catch(() => {});
  t.after(async () => {
    flow.cancel();
    await flow.completed.catch(() => {});
  });
  return flow;
}

test("task pages preserve filters and expose continuation tokens", async () => {
  const args = z.object(listTasks.definition.inputSchema).parse({
    taskListId: "list",
    dueMin: "2026-09-01T00:00:00Z",
    dueMax: "2026-10-01T00:00:00Z",
    showCompleted: true,
    showHidden: true,
    pageToken: "page-2",
    maxResults: 20,
  });
  let params;
  const result = await listTasks.handler(args, {
    tasks: {
      list: async (input) => {
        params = input;
        return { data: { items: [{ id: "task" }], nextPageToken: "page-3" } };
      },
    },
  });
  assert.deepEqual(params, {
    tasklist: "list",
    dueMin: args.dueMin,
    dueMax: args.dueMax,
    showCompleted: true,
    showHidden: true,
    maxResults: 20,
    pageToken: "page-2",
  });
  assert.equal(result.nextPageToken, "page-3");
  assert.equal(result.totalCount, 1);
});

test("task-list pages expose and accept continuation tokens", async () => {
  const args = z.object(listTaskLists.definition.inputSchema).parse({
    pageToken: "page-2",
  });
  let params;
  const result = await listTaskLists.handler(args, {
    tasklists: {
      list: async (input) => {
        params = input;
        return { data: { items: [{ id: "list" }], nextPageToken: "page-3" } };
      },
    },
  });
  assert.deepEqual(params, { maxResults: 100, pageToken: "page-2" });
  assert.equal(result.nextPageToken, "page-3");
  assert.equal(result.totalCount, 1);
});

test("last pages omit continuation tokens and broad reads include undated tasks", async () => {
  const args = z.object(listTasks.definition.inputSchema).parse({});
  const result = await listTasks.handler(args, {
    tasks: {
      list: async (params) => {
        assert.equal(params.dueMin, undefined);
        assert.equal(params.dueMax, undefined);
        return { data: { items: [{ id: "undated" }] } };
      },
    },
  });
  assert.equal(result.tasks[0].id, "undated");
  assert.equal(result.nextPageToken, undefined);
  const empty = await listTaskLists.handler(
    {},
    {
      tasklists: { list: async () => ({ data: {} }) },
    },
  );
  assert.deepEqual(empty.taskLists, []);
  assert.equal(empty.nextPageToken, undefined);
});

test("OAuth is loopback-only, validates state, uses PKCE, and stores private tokens", async (t) => {
  const hosts = [];
  const listen = Server.prototype.listen;
  t.mock.method(Server.prototype, "listen", function (...args) {
    hosts.push(args[1]);
    return listen.apply(this, args);
  });
  let exchange;
  t.mock.method(OAuth2Client.prototype, "getToken", async (request) => {
    exchange = request;
    return { tokens: testTokens };
  });
  const flow = await flowFixture(t);
  const params = new URL(flow.authUrl).searchParams;
  const state = params.get("state");
  assert.ok(state.length >= 32);
  assert.equal(params.get("scope"), auth.SCOPES.join(" "));
  assert.equal(params.get("code_challenge_method"), "S256");
  assert.equal(params.get("redirect_uri"), flow.redirectUri);
  assert.ok(hosts.length >= 2);
  assert.ok(hosts.every((host) => host === "127.0.0.1"));

  for (const invalidState of [undefined, "invalid", "x".repeat(state.length)]) {
    const response = await callback(flow, {
      code: "test-code",
      ...(invalidState === undefined ? {} : { state: invalidState }),
    });
    assert.equal(response.status, 400);
  }
  assert.equal(exchange, undefined);
  assert.equal(existsSync(auth.TOKEN_PATH), false);

  const response = await callback(flow, { state, code: "test-code" });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  await flow.completed;
  assert.equal(exchange.code, "test-code");
  assert.equal(exchange.redirect_uri, flow.redirectUri);
  assert.equal(
    createHash("sha256").update(exchange.codeVerifier).digest("base64url"),
    params.get("code_challenge"),
  );
  assert.equal(auth.loadTokens().refresh_token, "test-refresh");
  assert.equal(statSync(auth.TOKEN_PATH).mode & 0o777, 0o600);
  assert.equal(statSync(dirname(auth.TOKEN_PATH)).mode & 0o777, 0o700);
  assert.deepEqual(readdirSync(dirname(auth.TOKEN_PATH)), ["tokens.json"]);
});

test("OAuth denial and incomplete token responses do not persist credentials", async (t) => {
  t.mock.method(OAuth2Client.prototype, "getToken", async () => ({
    tokens: { access_token: "test-access" },
  }));
  for (const denied of [true, false]) {
    const flow = await flowFixture(t);
    const state = new URL(flow.authUrl).searchParams.get("state");
    const response = await callback(flow, {
      state,
      ...(denied ? { error: "access_denied" } : { code: "test-code" }),
    });
    assert.equal(response.status, denied ? 400 : 500);
    await assert.rejects(
      flow.completed,
      denied ? /authorization denied/ : /token exchange failed/,
    );
    assert.equal(existsSync(auth.TOKEN_PATH), false);
  }
});

test("MCP authentication shares one pending flow and uses the hardened callback", async (t) => {
  rmSync(auth.TOKEN_PATH, { force: true });
  t.mock.method(OAuth2Client.prototype, "getToken", async () => ({
    tokens: testTokens,
  }));
  const [first, second] = await Promise.all([
    authenticate.handler(),
    authenticate.handler(),
  ]);
  const flow = { redirectUri: first.callback_url };
  const params = new URL(first.auth_url).searchParams;
  const state = params.get("state");
  t.after(async () => {
    await callback(flow, { state, error: "access_denied" }).catch(() => {});
  });
  assert.equal(first.auth_url, second.auth_url);
  assert.equal(new URL(first.callback_url).hostname, "127.0.0.1");
  assert.equal(params.get("code_challenge_method"), "S256");
  assert.equal(
    (await callback(flow, { state: "wrong", code: "test-code" })).status,
    400,
  );
  assert.equal(
    (await callback(flow, { state, code: "test-code" })).status,
    200,
  );
  assert.equal((await authenticate.handler()).status, "authenticated");
});

test("refresh preserves the refresh token and replaces token files privately", async (t) => {
  writeFileSync(
    auth.TOKEN_PATH,
    JSON.stringify({ ...testTokens, expiry_date: 1 }),
    { mode: 0o644 },
  );
  chmodSync(auth.TOKEN_PATH, 0o644);
  t.mock.method(OAuth2Client.prototype, "refreshAccessToken", async () => ({
    credentials: {
      access_token: "test-refreshed",
      expiry_date: Date.now() + 3600 * 1000,
    },
  }));
  const client = await auth.getAuthenticatedClient();
  assert.equal(client.credentials.refresh_token, "test-refresh");
  assert.equal(
    JSON.parse(readFileSync(auth.TOKEN_PATH, "utf8")).access_token,
    "test-refreshed",
  );
  assert.equal(statSync(auth.TOKEN_PATH).mode & 0o777, 0o600);
});

test("MCP discovery is available without credentials and exposes pagination", async (t) => {
  rmSync(auth.TOKEN_PATH, { force: true });
  const { GoogleTasksMcpServer } = await import("./build/server.js");
  const { Client } = await import("@modelcontextprotocol/sdk/client/index.js");
  const { InMemoryTransport } =
    await import("@modelcontextprotocol/sdk/inMemory.js");
  const server = new GoogleTasksMcpServer();
  await server.initialize();
  const client = new Client({ name: "test-client", version: "1" });
  const [clientTransport, serverTransport] =
    InMemoryTransport.createLinkedPair();
  t.after(async () => {
    await client.close();
    await server.getServer().close();
  });
  await Promise.all([
    server.getServer().connect(serverTransport),
    client.connect(clientTransport),
  ]);
  const { tools } = await client.listTools();
  assert.equal(tools.length, 8);
  for (const name of ["list-tasks", "list-task-lists"]) {
    assert.ok(
      tools.find((tool) => tool.name === name).inputSchema.properties.pageToken,
    );
  }
  assert.equal(
    tools.find((tool) => tool.name === "authenticate").annotations.readOnlyHint,
    false,
  );
  assert.equal(
    (await client.callTool({ name: "list-tasks", arguments: {} })).isError,
    true,
  );
  assert.equal(existsSync(auth.TOKEN_PATH), false);
});
