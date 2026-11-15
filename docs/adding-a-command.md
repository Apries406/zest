# Adding a command

A command's suggestions come from its **spec**: a YAML file that lists its subcommands, options and
arguments. This guide adds one step by step. For every field, see the [spec format reference](spec-format.md).

## 1. Decide where the spec goes

| You want to… | Put the file in |
| --- | --- |
| Try it out, or a tool only you use | `~/.config/zest/specs/<command>.yaml` |
| Share it with everyone | `specs/<command>.yaml` in this repository, then open a pull request |

A spec in `~/.config/zest/specs` replaces a built-in spec with the same name, so you can also fix a
built-in spec there first and send the fix later.

The file name is the command name: `kubectl.yaml` is used when you type `kubectl`.

## 2. Start from the help text (optional)

```bash
zest gen mytool
```

This runs `mytool --help` (and `mytool <subcommand> --help` for two levels) and writes a draft to
`~/.config/zest/specs/mytool.yaml`. Help texts have no standard format, so check the result:
descriptions may be cut or merged, and some options may be missing. Subcommands that might change
something (`install`, `delete`, `push`, …) are listed but never run.

Use `--depth 0` to read only the top level, `--out specs` to write into the repository.

## 3. Write or edit the spec

A small but complete example:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/rostik32/zest/main/schema/spec.schema.json
name: notes
description: Keep notes in plain text

options:
  - name: [-h, --help]
    description: Show help
    isPersistent: true          # also valid after any subcommand

subcommands:
  - name: [new, n]              # `n` is an alias: it matches, but `new` is shown and inserted
    description: Create a note
    args:
      name: title

  - name: open
    description: Open a note in $EDITOR
    args:
      name: note
      template: filepaths       # suggest files and folders
      generators:
        template: filepaths
        filter:
          extensions: [md, txt] # only .md and .txt files (folders are always shown)

  - name: tag
    description: Add a tag to a note
    options:
      - name: --color
        description: Tag color
        requiresSeparator: true # inserted as `--color=`
        args:
          name: color
          suggestions: [red, green, blue]
    args:
      - name: note
        template: filepaths
      - name: tags
        isVariadic: true        # any number of tags
        generators:
          script: notes tags --plain   # one suggestion per output line
          cache: { ttl: 30 }
```

What to keep in mind:

- **Descriptions** are one short sentence, starting with a capital letter, without a final period:
  `Create a note`, not `creates a new note.`
- **Order matters.** Suggestions are shown in the order of the file when nothing is typed. Put the
  most used subcommands first, or give them `priority: 80` (default 50).
- **Generators run real commands** in the current folder, with a 5 second limit. Make them fast,
  read-only and quiet: `git branch --format=…`, not `git branch -v`.
- Editors with the YAML extension (VS Code, Cursor) check the file as you type thanks to the
  `yaml-language-server` line at the top. In this repository it is set up already.

## 4. Check it

```bash
zest validate ~/.config/zest/specs/notes.yaml   # finds unknown fields, typos, wrong types
zest validate --deep ~/.config/zest/specs/notes.yaml   # also types `notes `, `notes -`, … and checks the suggestions
zest complete 'notes '                          # what the popup shows
zest complete 'notes tag --color='
zest complete 'notes open '
```

Then try it in a terminal. zest picks up changed files on its own; if it does not, use
**Reload Specs** in the menu bar.

## 5. Share it

1. Fork the repository and copy the file to `specs/notes.yaml`.
2. Run the checks:
   ```bash
   swift run zest validate specs/notes.yaml
   ```
3. Open a pull request. Say what tool the spec is for and link to its documentation.

CI checks every spec on each pull request.

## Tips

- **A big CLI?** Split it: `subcommands: [{name: s3, loadSpec: aws/s3}]` loads `specs/aws/s3.yaml`
  only when you type `aws s3`.
- **`sudo`-like commands** that take another command use `args: {name: command, isCommand: true}`.
- **Options with a value** (`-o file`) need `args`; otherwise the value is read as a subcommand
  or an argument.
- **Single-dash long options** (`-name` in `find`) need
  `parserDirectives: {flagsArePosixNoncompliant: true}`, so `-name` is not read as `-n -a -m -e`.
