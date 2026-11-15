# Importing Fig specs

Most built-in specs come from [withfig/autocomplete](https://github.com/withfig/autocomplete)
(MIT license), the spec collection Fig, Amazon Q and Kiro CLI use. They are written in TypeScript;
[`tools/import-fig`](../tools/import-fig) converts them to YAML.

You only need this to re-import or to bring in a new Fig spec. To add a command, write YAML by hand:
see [Adding a command](adding-a-command.md).

## Running the importer

```bash
git clone --depth 1 https://github.com/withfig/autocomplete.git /tmp/fig
cd tools/import-fig
npm ci --ignore-scripts
node import.mjs --out ../../specs /tmp/fig/src [more folders…]
```

Later folders override earlier ones, so you can add a folder of compiled `.js` Fig specs after the
withfig sources. The importer overwrites files in `specs/`; review the diff with git before
committing, because hand edits to imported specs are lost on re-import.

Then check the result:

```bash
swift run -c release zest validate --quiet specs
node tools/import-fig/check-schema.mjs
```

## What happens to each spec

1. **esbuild** bundles the spec with its imports into one script.
2. The script runs in a Node `vm` sandbox; the exported object is the spec.
3. Static fields become YAML. Unknown fields are dropped, as are features zest does not support
   (`generateSpec`, `loadSpec` functions); the importer prints how many.
4. `filepaths()` and `folders()` from `@fig/autocomplete-generators` are replaced by native
   `template` generators with a `filter` (see `fig-generators-shim.mjs`), so the most common
   generator needs no JavaScript.
5. Other functions (`postProcess`, `custom`, `script` functions, …) cannot be YAML. The bundled script
   is saved next to the YAML as `<name>.js`, and the generator refers to a function by number:

   ```yaml
   generators:
     script: [git, branch, --no-color]
     js: { postProcess: 3 }
   ```

   The number is the function's position in a depth-first walk of the spec object. zest evaluates
   the `.js` file with JavaScriptCore and walks the object the same way (`JSRuntime.collectScript`
   and `collectFunctions` in `import.mjs` must stay identical).
6. Versioned specs (a folder with `index.ts` and version files) keep only the newest version.
7. Strings are cleaned of characters that break YAML 1.1 parsers (U+2028, control characters),
   and duplicate subcommands or options keep the first definition.

## JavaScript at runtime

The `.js` companions run inside JavaScriptCore with no access to files or the network. They can run
shell commands only through `executeShellCommand`, which zest implements with the same timeout as
other generators. About 250 of the 1,500 specs have a companion.
