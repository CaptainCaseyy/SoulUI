// Static checks for SoulUI against the Midnight rules in docs/research/midnight-api.md.
// This does not load the game. It only reads our Lua.
//   node tools/audit.mjs
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..");

function walk(dir, out) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) {
      if (name === "Libs" || name === "node_modules") continue;
      walk(p, out);
    } else if (name.endsWith(".lua") || name.endsWith(".toc")) out.push(p);
  }
  return out;
}

const files = readdirSync(repo)
  .filter((d) => d.startsWith("SoulUI") && statSync(join(repo, d)).isDirectory())
  .flatMap((d) => walk(join(repo, d), []));

let problems = 0;
function fail(file, line, message) {
  console.log(`${relative(repo, file)}:${line}: ${message}`);
  problems++;
}

function codeOf(src) {
  return src.split(/\r?\n/).map((line) => {
    const cut = line.indexOf("--");
    return cut === -1 ? line : line.slice(0, cut);
  });
}

for (const file of files) {
  const src = readFileSync(file, "utf8");
  const rel = relative(repo, file);
  if (file.endsWith(".toc")) {
    const first = src.split(/\r?\n/).find((line) => line.trim().length > 0) || "";
    if (!first.startsWith("## Interface: 120105")) {
      fail(file, 1, "toc must start with ## Interface: 120105");
    }
    const isCore = rel.replace(/\\/g, "/").startsWith("SoulUI/SoulUI.toc") || rel === "SoulUI\\SoulUI.toc";
    if (!isCore && /SavedVariables/.test(src)) {
      fail(file, 1, "child addon must not declare SavedVariables");
    }
    if (!isCore && !/## Dependencies: SoulUI/.test(src)) {
      fail(file, 1, "child addon must depend on SoulUI");
    }
    continue;
  }
  const base = rel.split(/[/\\]/).pop();
  if (base === "Gate.lua") continue;
  const lines = src.split(/\r?\n/);
  const first = lines.find((line) => line.trim().length > 0) || "";
  if (!first.startsWith("if SoulUI_Blocked")) {
    fail(file, 1, "file must start with the client gate");
  }
  const code = codeOf(src);
  code.forEach((line, index) => {
    const n = index + 1;
    if (/COMBAT_LOG_EVENT/.test(line)) fail(file, n, "combat log is not available to addons");
    if (/table\.sort\s*\(/.test(line) && /DamageMeters|GroupFrames|ActionBars|ResourceBars|Nameplates|UnitFrames/.test(rel)) {
      fail(file, n, "do not sort secret combat data");
    }
    if (/:SetCooldown\s*\(/.test(line)) fail(file, n, "use SetCooldownFromDurationObject, not SetCooldown");
    if (/CallMethod/.test(line)) fail(file, n, "secure page snippets must not CallMethod");
    if (/tostring\s*\(\s*Unit/.test(line)) fail(file, n, "tostring on a unit API can throw on a secret");
    if (/type\s*\(\s*[A-Za-z_][\w.:]*\s*\(/.test(line)) {
      fail(file, n, "type() on a call forwards zero returns and throws; capture the return first");
    }
    if (/UnitHealth(Max|Percent)?\s*\(/.test(line) && /[\+\*\/]/.test(line)) {
      fail(file, n, "no arithmetic on health values");
    }
    if (/\bHide\s*\(/.test(line) && /MultiBar|MainActionBar|MainMenuBar|CompactRaid|PartyFrame/.test(line)) {
      fail(file, n, "do not Hide() a Blizzard protected bar or raid frame");
    }
  });
}

function mustInclude(rel, needles) {
  const file = join(repo, rel);
  const src = readFileSync(file, "utf8");
  for (const needle of needles) {
    if (!src.includes(needle)) {
      fail(file, 1, `missing expected API: ${needle}`);
    }
  }
}

mustInclude("SoulUI_GroupFrames/GroupFrames.lua", [
  "SecureGroupHeaderTemplate",
  "UnitHealthPercent",
  "CustomAuraContainerTemplate",
  "RegisterStateDriver",
]);
mustInclude("SoulUI_ActionBars/ActionBars.lua", [
  "GetActionCooldownDuration",
  "SetCooldownFromDurationObject",
  "SecureHandlerStateTemplate",
  "SetFrameRef",
  "ChildUpdate",
]);
mustInclude("SoulUI_ResourceBars/ResourceBars.lua", [
  "SetMinMaxValues",
  "GetSpellCooldownDuration",
  "Soul.CastBar.New",
]);
mustInclude("SoulUI/Core/CastBar.lua", [
  "UnitCastingDuration",
  "UnitChannelDuration",
  "SetTimerDuration",
]);
mustInclude("SoulUI_DamageMeters/DamageMeters.lua", [
  "GetCombatSessionFromType",
  "damageMeterEnabled",
  "Soul:Abbrev",
]);

console.log(`${files.length} files audited, ${problems} problem(s)`);
process.exit(problems ? 1 : 0);
