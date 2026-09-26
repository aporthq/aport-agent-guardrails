#!/usr/bin/env node
/*
 * Extract hook-facing Codex tool names from the upstream openai/codex source.
 *
 * This is intentionally source-derived: APort's own fixture is not an input.
 * The drift check uses this output to prove every provider tool name is
 * classified by the Codex hook adapter instead of guessed or left unknown.
 */

import fs from "node:fs";
import path from "node:path";

const root = process.argv[2];
if (!root) {
  console.error("usage: extract-codex-provider-tools.mjs <openai-codex-source-dir>");
  process.exit(2);
}

const absRoot = path.resolve(root);
const mustExist = path.join(absRoot, "codex-rs", "core", "src", "tools", "spec_plan.rs");
if (!fs.existsSync(mustExist)) {
  console.error(`not an openai/codex source tree: ${absRoot}`);
  process.exit(2);
}

const sourceRoots = [
  "codex-rs/code-mode-protocol/src",
  "codex-rs/tools/src",
  "codex-rs/core/src/tools",
  "codex-rs/ext/image-generation/src",
  "codex-rs/ext/web-search/src",
  "codex-rs/ext/memories/src",
  "codex-rs/ext/goal/src",
  "codex-rs/ext/skills/src/tools",
  "codex-rs/ext/history-notes/src",
  "codex-rs/ext/agent-message-board/src/tools",
];

function walk(dir, files = []) {
  if (!fs.existsSync(dir)) return files;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, files);
    } else if (entry.isFile() && entry.name.endsWith(".rs")) {
      const normalized = full.replaceAll(path.sep, "/");
      if (!/(_tests|tests)\.rs$/.test(normalized) && !normalized.includes("/tests/")) {
        files.push(full);
      }
    }
  }
  return files;
}

const files = sourceRoots.flatMap((dir) => walk(path.join(absRoot, dir)));

function productionText(text) {
  const cfgTest = text.search(/#\s*\[\s*cfg\s*\(\s*test\s*\)\s*\]/);
  return cfgTest >= 0 ? text.slice(0, cfgTest) : text;
}

const fileText = new Map(
  files.map((file) => [file, productionText(fs.readFileSync(file, "utf8"))]),
);

const globalConstValues = new Map();
const globalConstAmbiguous = new Set();
const globalConstExprs = new Map();
const constDeclRegex =
  /(?:pub(?:\([^)]*\))?\s+)?const\s+([A-Z][A-Z0-9_]*)\s*:\s*&str\s*=\s*([^;]+);/g;
const stringConstRegex =
  /(?:pub(?:\([^)]*\))?\s+)?const\s+([A-Z][A-Z0-9_]*)\s*:\s*&str\s*=\s*"([^"]+)"/g;

for (const text of fileText.values()) {
  for (const match of text.matchAll(constDeclRegex)) {
    const [, name, expr] = match;
    const value = expr.trim();
    if (!globalConstExprs.has(name)) globalConstExprs.set(name, new Set());
    globalConstExprs.get(name).add(value);
  }
}

function constIdent(expr) {
  const ident = expr.trim().match(/^(?:(?:crate|super|self|[A-Za-z_][A-Za-z0-9_]*)::)*([A-Z][A-Z0-9_]*)$/);
  return ident ? ident[1] : null;
}

function resolveConstExpr(expr, stack = []) {
  const value = expr.trim().replace(/^&/, "").trim();
  const string = value.match(/^"([^"]*)"$/);
  if (string) return string[1];
  const ident = constIdent(value);
  if (!ident || stack.includes(ident) || !globalConstExprs.has(ident)) return null;
  const resolved = new Set(
    [...globalConstExprs.get(ident)]
      .map((candidate) => resolveConstExpr(candidate, [...stack, ident]))
      .filter((candidate) => candidate != null),
  );
  return resolved.size === 1 ? [...resolved][0] : null;
}

for (const name of globalConstExprs.keys()) {
  const value = resolveConstExpr(name);
  if (value == null) continue;
  if (globalConstValues.has(name) && globalConstValues.get(name) !== value) {
    globalConstAmbiguous.add(name);
  } else {
    globalConstValues.set(name, value);
  }
}
for (const name of globalConstAmbiguous) {
  globalConstValues.delete(name);
}

function localConsts(text) {
  const values = new Map();
  for (const match of text.matchAll(stringConstRegex)) {
    values.set(match[1], match[2]);
  }
  return values;
}

function resolveExpr(expr, locals) {
  let value = expr.trim();
  value = value.replace(/^&/, "").replace(/\.to_string\(\)$/, "").trim();
  const string = value.match(/^"([^"]*)"$/);
  if (string) return string[1];
  const ident = constIdent(value);
  if (!ident) return null;
  return locals.get(ident) || globalConstValues.get(ident) || null;
}

function addTool(tools, name) {
  if (!name) return;
  if (name.includes("test_sync_tool")) return;
  if (name.startsWith("mcp__") || name.startsWith("mcp.")) return;
  tools.add(name);
}

const tools = new Set();
const namespacedWrappers = new Map();

for (const text of fileText.values()) {
  for (const match of text.matchAll(
    /fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*&str\s*\)\s*->\s*ToolName\s*\{([\s\S]*?)\n\}/g,
  )) {
    const [, fnName, paramName, body] = match;
    const namespaced = body.match(
      new RegExp(
        String.raw`ToolName::namespaced\(([^,\n]+),\s*${paramName}\s*\)`,
      ),
    );
    if (!namespaced) continue;
    const namespace = resolveExpr(namespaced[1], localConsts(text));
    if (namespace) namespacedWrappers.set(fnName, namespace);
  }
}

for (const [file, text] of fileText) {
  const locals = localConsts(text);

  for (const match of text.matchAll(/ToolName::plain\(([^)]+)\)/g)) {
    addTool(tools, resolveExpr(match[1], locals));
  }

  for (const match of text.matchAll(
    /ToolName::plain\(\s*match[\s\S]*?\{([\s\S]*?)\}\s*\)/g,
  )) {
    for (const arm of match[1].matchAll(/=>\s*([^,\n}]+)/g)) {
      addTool(tools, resolveExpr(arm[1], locals));
    }
  }

  for (const match of text.matchAll(/ToolName::namespaced\(([^,\n]+),\s*([^)]+)\)/g)) {
    const namespace = resolveExpr(match[1], locals);
    const name = resolveExpr(match[2], locals);
    if (namespace && name) addTool(tools, `${namespace}.${name}`);
  }

  for (const [fnName, namespace] of namespacedWrappers) {
    const call = new RegExp(String.raw`\b${fnName}\(([^)]+)\)`, "g");
    for (const match of text.matchAll(call)) {
      const name = resolveExpr(match[1], locals);
      if (name) addTool(tools, `${namespace}.${name}`);
    }
  }

  if (text.includes("HookToolName::bash()")) {
    addTool(tools, "Bash");
  }
  if (text.includes("HookToolName::apply_patch()")) {
    addTool(tools, "apply_patch");
  }
  if (text.includes("HookToolName::spawn_agent()")) {
    addTool(tools, "spawn_agent");
  }

  if (file.replaceAll(path.sep, "/").endsWith("ext/agent-message-board/src/tools/spec.rs")) {
    const names = text.match(/const\s+NAMES\s*:\s*\[&str;[^\]]+\]\s*=\s*\[([\s\S]*?)\];/);
    if (names) {
      for (const name of names[1].matchAll(/"([^"]+)"/g)) {
        addTool(tools, `collaboration.${name[1]}`);
      }
    }
  }
}

for (const name of [...tools].sort()) {
  console.log(name);
}
