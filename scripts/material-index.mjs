// Writes assets/icons/material.json (name → icon lookups) and copies the SVGs it uses.
// Called by scripts/update-icons.sh.
import fs from "node:fs";
import path from "node:path";

const [pkg, out] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(path.join(pkg, "dist/material-icons.json"), "utf8"));
const used = new Set([manifest.file, manifest.folder]);
const keep = (map) => {
  const result = {};
  for (const [key, icon] of Object.entries(map || {})) {
    if (icon.endsWith("_light") || icon.endsWith("-open")) continue;
    result[key.toLowerCase()] = icon;
    used.add(icon);
  }
  return result;
};
const index = {
  file: manifest.file,
  folder: manifest.folder,
  fileExtensions: keep(manifest.fileExtensions),
  fileNames: keep(manifest.fileNames),
  folderNames: keep(manifest.folderNames),
};
// Every icon is also available by its own name, e.g. `git`, `docker`, `nodejs`.
for (const name of Object.keys(manifest.iconDefinitions)) {
  if (!name.endsWith("_light") && !name.endsWith("-open") && !name.includes("folder")) used.add(name);
}
let copied = 0;
for (const name of used) {
  const def = manifest.iconDefinitions[name];
  if (!def) continue;
  const src = path.join(pkg, "dist", def.iconPath);
  if (!fs.existsSync(src)) continue;
  fs.copyFileSync(src, path.join(out, "material", name + ".svg"));
  copied++;
}
fs.writeFileSync(path.join(out, "material.json"), JSON.stringify(index));
console.log(`material.json: ${Object.keys(index.fileExtensions).length} extensions, ${Object.keys(index.fileNames).length} file names, ${Object.keys(index.folderNames).length} folder names; ${copied} icons`);
