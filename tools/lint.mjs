// Lua lint for SoulUI: syntax check (Lua 5.1, which WoW uses) + leaked global writes.
//   npm install --prefix tools   (once)
//   node tools/lint.mjs
// Exit code 1 on any problem, so it can gate commits.
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const luaparse = require("luaparse");
const repo = join(dirname(fileURLToPath(import.meta.url)), "..");

// Globals we intentionally create.
const allowedGlobalWrite = /^(SoulUI\w*|SLASH_\w+|BINDING_\w+)$/;

function walk(dir, out) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) {
      if (name === "Libs" || name === "node_modules") continue; // third-party
      walk(p, out);
    } else if (name.endsWith(".lua")) out.push(p);
  }
  return out;
}

const files = readdirSync(repo)
  .filter((d) => d.startsWith("SoulUI") && statSync(join(repo, d)).isDirectory())
  .flatMap((d) => walk(join(repo, d), []));

let problems = 0;
for (const file of files) {
  const src = readFileSync(file, "utf8");
  const rel = relative(repo, file);
  let ast;
  try {
    ast = luaparse.parse(src, { luaVersion: "5.1", locations: true, scope: true, comments: false });
  } catch (e) {
    console.log(`${rel}:${e.line}:${e.column}: syntax: ${e.message}`);
    problems++;
    continue;
  }
  // Find assignments to globals.
  const visit = (node) => {
    if (!node || typeof node !== "object") return;
    if (node.type === "AssignmentStatement") {
      for (const v of node.variables) {
        if (v.type === "Identifier" && v.isLocal === false && !allowedGlobalWrite.test(v.name)) {
          console.log(`${rel}:${v.loc.start.line}: global write: ${v.name}`);
          problems++;
        }
      }
    }
    if (node.type === "FunctionDeclaration" && node.identifier && node.identifier.type === "Identifier"
        && !node.isLocal && !allowedGlobalWrite.test(node.identifier.name)) {
      console.log(`${rel}:${node.loc.start.line}: global function: ${node.identifier.name}`);
      problems++;
    }
    for (const k in node) {
      if (k === "loc" || k === "range") continue;
      const c = node[k];
      if (Array.isArray(c)) c.forEach(visit);
      else if (c && typeof c === "object" && c.type) visit(c);
    }
  };
  visit(ast);
}
console.log(`${files.length} files checked, ${problems} problem(s)`);
process.exit(problems ? 1 : 0);
