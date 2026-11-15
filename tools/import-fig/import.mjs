#!/usr/bin/env node
// Converts Fig completion specs to zest YAML specs.
//
//   node import.mjs --out ../../specs <source> [<source> ...]
//
// A source is a folder of Fig specs: the `src` folder of a withfig/autocomplete
// checkout (TypeScript) or a folder of compiled `.js` specs. Later sources win
// when two define the same spec.
//
// Static parts of a spec become YAML. JavaScript functions (generators with
// `postProcess`, `custom`, ...) cannot be expressed in YAML, so the bundled spec is
// written next to the YAML as `<name>.js` and generators refer to its functions by
// number. zest runs them with JavaScriptCore. See docs/fig-import.md.

import { build } from "esbuild";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import YAML from "yaml";

const args = process.argv.slice(2);
const outIndex = args.indexOf("--out");
if (outIndex < 0 || args.length < 3) {
  console.error("usage: node import.mjs --out <specs dir> <source> [<source> ...]");
  process.exit(2);
}
const outDir = path.resolve(args[outIndex + 1]);
const sources = args.filter((_, i) => i !== outIndex && i !== outIndex + 1).map((s) => path.resolve(s));

const header = (source) =>
  `# Imported from ${source}. You can edit this file; see docs/adding-a-command.md.\n`;

const stats = { specs: 0, withJS: 0, failed: [], dropped: {} };
const drop = (what) => (stats.dropped[what] = (stats.dropped[what] || 0) + 1);

// --- Finding spec files -------------------------------------------------------

function listSpecs(dir) {
  const result = [];
  (function walk(rel) {
    for (const entry of fs.readdirSync(path.join(dir, rel), { withFileTypes: true })) {
      const relPath = path.join(rel, entry.name);
      if (entry.isDirectory()) {
        walk(relPath);
      } else if (/\.(ts|js)$/.test(entry.name) && !/\.(d|test)\.ts$/.test(entry.name)) {
        result.push({ name: relPath.replace(/\.(ts|js)$/, ""), file: path.join(dir, relPath) });
      }
    }
  })("");
  return result;
}

// --- Bundling and evaluating ----------------------------------------------------

const here = path.dirname(new URL(import.meta.url).pathname);
const figGeneratorsShim = {
  name: "fig-generators-shim",
  setup(b) {
    b.onResolve({ filter: /^@fig\/autocomplete-generators$/ }, (a) =>
      a.importer.endsWith("fig-generators-shim.mjs") ? undefined : { path: path.join(here, "fig-generators-shim.mjs") });
  },
};

async function bundle(file) {
  const result = await build({
    entryPoints: [file],
    bundle: true,
    write: false,
    format: "iife",
    globalName: "__zestModule",
    platform: "neutral",
    // Resolve @fig/* helpers from this folder, wherever the specs live.
    nodePaths: [path.join(path.dirname(new URL(import.meta.url).pathname), "node_modules")],
    mainFields: ["module", "main"],
    target: "es2020",
    minify: true,
    legalComments: "none",
    logLevel: "silent",
    plugins: [figGeneratorsShim],
    // Some specs import Node modules for build-time helpers; they are never called at runtime.
    external: ["node:*", "fs", "path", "os", "child_process"],
  });
  return result.outputFiles[0].text;
}

function evaluate(code) {
  const context = vm.createContext({ console: { log() {}, warn() {}, error() {} } });
  vm.runInContext(code + "\n;globalThis.__zestSpec = __zestModule.default;", context, { timeout: 2000 });
  return context.__zestSpec;
}

// Must match JSRuntime.collectScript in Sources/ZestCore/JSRuntime.swift.
function collectFunctions(root) {
  const out = [];
  const seen = new Set();
  (function walk(v) {
    if (typeof v === "function") {
      if (!seen.has(v)) {
        seen.add(v);
        out.push(v);
      }
      return;
    }
    if (v === null || typeof v !== "object" || seen.has(v)) return;
    seen.add(v);
    if (Array.isArray(v)) {
      for (const x of v) walk(x);
      return;
    }
    for (const k of Object.keys(v)) walk(v[k]);
  })(root);
  return out;
}

// --- Converting -------------------------------------------------------------------

function convertSpec(spec, functions) {
  const ctx = { functions, usesJS: false };
  return { spec: subcommand(spec, ctx), usesJS: ctx.usesJS };
}

// U+2028 and friends break YAML parsers that follow YAML 1.1 line-break rules.
const sanitize = (v) => v.replace(/[\u2028\u2029\u0085]/g, " ").replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "");
const str = (v) => (typeof v === "string" ? sanitize(v) : undefined);
const bool = (v) => (typeof v === "boolean" ? v : undefined);
const num = (v) => (typeof v === "number" && Number.isFinite(v) ? v : undefined);
const names = (v) => {
  if (typeof v === "string") return v.trim() ? sanitize(v) : undefined;
  if (Array.isArray(v)) {
    const list = v.filter((x) => typeof x === "string" && x.trim()).map(sanitize);
    return list.length === 1 ? list[0] : list.length ? list : undefined;
  }
  return undefined;
};
const deprecated = (v) => (v ? true : undefined);
const many = (v, f) => {
  if (v === undefined || v === null) return undefined;
  const list = (Array.isArray(v) ? v : [v]).map(f).filter((x) => x !== undefined);
  if (!list.length) return undefined;
  return list.length === 1 ? list[0] : list;
};
const list = (v, f) => {
  if (!Array.isArray(v)) return undefined;
  const out = v.map(f).filter((x) => x !== undefined);
  return out.length ? out : undefined;
};
// Some upstream specs define the same subcommand or option twice; keep the first.
const unique = (items) => {
  if (!items) return items;
  const seen = new Set();
  const out = items.filter((x) => {
    const key = Array.isArray(x.name) ? x.name[0] : x.name;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
  return out.length ? out : undefined;
};

function clean(o) {
  for (const k of Object.keys(o)) if (o[k] === undefined) delete o[k];
  return o;
}

function common(node) {
  return {
    displayName: str(node.displayName),
    description: str(node.description),
    icon: str(node.icon),
    priority: num(node.priority),
    hidden: bool(node.hidden),
    deprecated: deprecated(node.deprecated),
    insertValue: str(node.insertValue),
  };
}

function subcommand(node, ctx) {
  if (typeof node !== "object" || node === null) return undefined;
  const name = names(node.name);
  if (name === undefined) return undefined;
  if (node.generateSpec) drop("generateSpec");
  let loadSpec = str(node.loadSpec);
  let inline = {};
  if (typeof node.loadSpec === "object" && node.loadSpec !== null) {
    // An inline spec: merge it into this subcommand.
    inline = subcommand({ ...node.loadSpec, name: node.name }, ctx) || {};
  } else if (typeof node.loadSpec === "function") {
    drop("loadSpec function");
  }
  return clean({
    name,
    ...common(node),
    subcommands: unique(list(node.subcommands, (s) => subcommand(s, ctx))),
    options: unique(list(node.options, (o) => option(o, ctx))),
    args: many(node.args, (a) => arg(a, ctx)),
    loadSpec,
    requiresSubcommand: bool(node.requiresSubcommand),
    filterStrategy: str(node.filterStrategy),
    parserDirectives: directives(node.parserDirectives),
    additionalSuggestions: list(node.additionalSuggestions, suggestion),
    ...inline,
  });
}

function directives(d) {
  if (!d || typeof d !== "object") return undefined;
  const out = clean({
    flagsArePosixNoncompliant: bool(d.flagsArePosixNoncompliant),
    optionsMustPrecedeArguments: bool(d.optionsMustPrecedeArguments),
    optionArgSeparators: names(d.optionArgSeparators),
  });
  return Object.keys(out).length ? out : undefined;
}

function option(node, ctx) {
  if (typeof node !== "object" || node === null) return undefined;
  const name = names(node.name);
  if (name === undefined) return undefined;
  let separator = node.requiresSeparator ?? node.requiresEquals;
  if (typeof separator !== "boolean" && typeof separator !== "string") separator = undefined;
  if (separator === false) separator = undefined;
  let repeatable = node.isRepeatable;
  if (typeof repeatable !== "boolean" && typeof repeatable !== "number") repeatable = undefined;
  return clean({
    name,
    ...common(node),
    args: many(node.args, (a) => arg(a, ctx)),
    isRepeatable: repeatable,
    isPersistent: bool(node.isPersistent),
    isRequired: bool(node.isRequired),
    requiresSeparator: separator,
    exclusiveOn: list(node.exclusiveOn, str),
    dependsOn: list(node.dependsOn, str),
  });
}

function arg(node, ctx) {
  if (typeof node !== "object" || node === null) return undefined;
  if (typeof node.loadSpec === "function") drop("arg loadSpec function");
  return clean({
    name: str(node.name),
    description: str(node.description),
    isOptional: bool(node.isOptional),
    isVariadic: bool(node.isVariadic),
    optionsCanBreakVariadicArg: bool(node.optionsCanBreakVariadicArg),
    isCommand: bool(node.isCommand),
    isScript: bool(node.isScript),
    template: template(node.template),
    suggestions: list(node.suggestions, suggestion),
    generators: many(node.generators, (g) => generator(g, ctx)),
    default: str(node.default),
    filterStrategy: str(node.filterStrategy),
    loadSpec: str(node.loadSpec),
    suggestCurrentToken: bool(node.suggestCurrentToken),
  });
}

// `filepaths({extensions: ["js"]})` from @fig/autocomplete-generators (see the shim).
const strings = (v) => {
  if (v === undefined || v === null) return undefined;
  const list = (Array.isArray(v) ? v : [v]).map(String);
  return list.length ? list : undefined;
};
function filesGenerator(o) {
  if (o.showFolders === "only") return { template: "folders" };
  const filter = clean({
    extensions: strings(o.extensions),
    equals: strings(o.equals),
    matches: o.matches instanceof RegExp ? o.matches.source : typeof o.matches === "string" ? o.matches : undefined,
    filterFolders: o.filterFolders === true ? true : undefined,
  });
  if (o.editFileSuggestions || o.editFolderSuggestions || o.rootDirectory) drop("filepaths options");
  return clean({ template: "filepaths", filter: Object.keys(filter).length ? filter : undefined });
}

const templates = new Set(["filepaths", "folders", "history", "help"]);
function template(v) {
  return many(v, (t) => (templates.has(t) ? t : undefined));
}

function suggestion(node) {
  if (typeof node === "string") return node;
  if (typeof node !== "object" || node === null) return undefined;
  const name = names(node.name);
  if (name === undefined) return undefined;
  const out = clean({ name, ...common(node), type: str(node.type) });
  return Object.keys(out).length === 1 ? (typeof name === "string" ? name : out) : out;
}

function generator(node, ctx) {
  if (node && node.__zestFiles) return filesGenerator(node.__zestFiles);
  if (typeof node !== "object" || node === null) return undefined;
  const js = {};
  const ref = (key, value) => {
    if (typeof value !== "function") return undefined;
    const index = ctx.functions.indexOf(value);
    if (index < 0) return undefined;
    js[key] = index;
    ctx.usesJS = true;
    return undefined;
  };
  let script;
  if (typeof node.script === "string") script = node.script;
  else if (Array.isArray(node.script)) script = node.script.filter((x) => typeof x === "string");
  else ref("script", node.script);
  ref("postProcess", node.postProcess);
  ref("custom", node.custom);
  ref("trigger", node.trigger);
  ref("getQueryTerm", node.getQueryTerm);
  ref("filterTemplateSuggestions", node.filterTemplateSuggestions);
  if (node.trigger && typeof node.trigger === "object") drop("trigger object");

  const cache = node.cache && typeof node.cache === "object"
    ? clean({
        ttl: num(node.cache.ttl) !== undefined ? node.cache.ttl / 1000 : undefined,
        cacheByDirectory: node.cache.cacheByDirectory === true ? true : undefined,
      })
    : undefined;

  const out = clean({
    script,
    splitOn: str(node.splitOn),
    template: template(node.template),
    cache: cache && Object.keys(cache).length ? cache : undefined,
    scriptTimeout: num(node.scriptTimeout) !== undefined ? node.scriptTimeout / 1000 : undefined,
    trigger: str(node.trigger),
    getQueryTerm: str(node.getQueryTerm),
    js: Object.keys(js).length ? js : undefined,
  });
  return Object.keys(out).length ? out : undefined;
}

function isWithfig(source) {
  try {
    const pkg = JSON.parse(fs.readFileSync(path.join(source, "..", "package.json"), "utf8"));
    return pkg.name === "@withfig/autocomplete";
  } catch {
    return false;
  }
}

// --- Main ------------------------------------------------------------------------

const all = new Map();
for (const source of sources) {
  for (const spec of listSpecs(source)) all.set(spec.name, { ...spec, source });
}

fs.mkdirSync(outDir, { recursive: true });
for (const [name, { file, source }] of [...all.entries()].sort()) {
  let code, spec;
  try {
    code = await bundle(file);
    spec = evaluate(code);
  } catch (error) {
    const detail = error.errors?.[0]?.text || String(error.message || error).split("\n")[0];
    stats.failed.push(`${name}: ${detail}`);
    continue;
  }
  if (!spec || typeof spec !== "object" || !spec.name) {
    stats.failed.push(`${name}: no spec object exported`);
    continue;
  }
  const functions = collectFunctions(spec);
  const { spec: converted, usesJS } = convertSpec(spec, functions);
  const target = path.join(outDir, name);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const origin = isWithfig(source) ? "withfig/autocomplete (MIT)" : "a Fig spec";
  const yaml = YAML.stringify(converted, { version: "1.1", lineWidth: 0, aliasDuplicateObjects: false });
  fs.writeFileSync(target + ".yaml", header(origin) + yaml);
  const jsFile = target + ".js";
  if (usesJS) {
    fs.writeFileSync(jsFile, code + "\nvar __zestSpec = __zestModule.default;\n");
    stats.withJS++;
  } else if (fs.existsSync(jsFile)) {
    fs.unlinkSync(jsFile);
  }
  stats.specs++;
}

// Versioned specs (`heroku/index` exports a function that picks a version file):
// use the newest version file as the spec and drop the others.
const semver = /^\d+(\.\d+)*$/;
const compareVersions = (a, b) => {
  const pa = a.split(".").map(Number);
  const pb = b.split(".").map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) - (pb[i] || 0);
  }
  return 0;
};
stats.failed = stats.failed.filter((line) => {
  const name = line.split(":")[0];
  if (!name.endsWith("/index")) return true;
  const dir = path.join(outDir, path.dirname(name));
  if (!fs.existsSync(dir)) return true;
  const versions = fs.readdirSync(dir)
    .filter((f) => f.endsWith(".yaml") && semver.test(f.slice(0, -5)))
    .map((f) => f.slice(0, -5))
    .sort(compareVersions);
  const latest = versions.at(-1);
  if (!latest) return true;
  const target = path.join(outDir, path.dirname(name));
  fs.renameSync(path.join(dir, latest + ".yaml"), target + ".yaml");
  if (fs.existsSync(path.join(dir, latest + ".js"))) fs.renameSync(path.join(dir, latest + ".js"), target + ".js");
  for (const v of versions.slice(0, -1)) {
    for (const ext of [".yaml", ".js"]) fs.rmSync(path.join(dir, v + ext), { force: true });
    stats.specs--;
  }
  if (!fs.readdirSync(dir).length) fs.rmdirSync(dir);
  return false;
});
// Helper modules that are not specs.
stats.failed = stats.failed.filter((line) => !/: no spec object exported$/.test(line) || !/\/(shared|generators|regions|index)$/.test(line.split(":")[0]));

console.log(`Imported ${stats.specs} specs (${stats.withJS} with JavaScript generators).`);
if (Object.keys(stats.dropped).length) console.log("Dropped unsupported features:", stats.dropped);
if (stats.failed.length) {
  console.log(`Failed (${stats.failed.length}):`);
  for (const f of stats.failed) console.log("  " + f);
}
