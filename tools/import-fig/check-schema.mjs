#!/usr/bin/env node
// Checks every YAML spec against schema/spec.schema.json (the schema editors use).
//   node tools/import-fig/check-schema.mjs [specs dir]
import Ajv from "ajv";
import fs from "node:fs";
import path from "node:path";
import YAML from "yaml";

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const dir = path.resolve(process.argv[2] || path.join(root, "specs"));
const ajv = new Ajv({ allErrors: true, strict: false });
const validate = ajv.compile(JSON.parse(fs.readFileSync(path.join(root, "schema/spec.schema.json"), "utf8")));

let count = 0;
let failed = 0;
(function walk(d) {
  for (const entry of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, entry.name);
    if (entry.isDirectory()) walk(p);
    else if (/\.ya?ml$/.test(p)) {
      count++;
      const doc = YAML.parse(fs.readFileSync(p, "utf8"), { version: "1.1" });
      if (!validate(doc)) {
        failed++;
        console.log(`${path.relative(root, p)}: ${validate.errors[0].instancePath || "/"} ${validate.errors[0].message}`);
      }
    }
  }
})(dir);
console.log(`${count} specs checked against the schema, ${failed} invalid.`);
process.exit(failed ? 1 : 0);
