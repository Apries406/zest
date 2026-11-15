# Spec format reference

A spec is a YAML file describing one command. Field names follow the
[Fig spec format](https://fig.io/docs/reference), so existing Fig knowledge applies. The
[JSON Schema](../schema/spec.schema.json) has the same information for editors.

```
spec (= subcommand)
├─ subcommands: [subcommand]
├─ options: [option]
│   └─ args: arg | [arg]
└─ args: arg | [arg]
    ├─ suggestions: [suggestion]
    ├─ template: filepaths | folders
    └─ generators: generator | [generator]
```

Wherever a list is expected, a single value is also accepted: `name: commit` and
`name: [commit, ci]` both work, as do `args: {name: file}` and `args: [{name: src}, {name: dst}]`.

## Subcommand

The file itself is the top-level subcommand.

| Field | Type | Meaning |
| --- | --- | --- |
| `name` | string or list | The name, then aliases. The first name is shown and inserted; aliases also match what you type. **Required.** |
| `description` | string | Shown in the popup and in its footer. |
| `displayName` | string | Shown instead of the name. |
| `icon` | string | A [Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme/tree/main/icons) icon name such as `docker`, an emoji, or `fig://icon?type=<name>`. |
| `priority` | 0–100 | Sort order, default 50. Higher comes first. |
| `hidden` | bool | Shown only after two letters of its name are typed. |
| `deprecated` | bool | Struck through and sorted lower. |
| `insertValue` | string | Inserted instead of the name. `{cursor}` sets where the cursor ends up. |
| `subcommands` | list | Nested subcommands. |
| `options` | list | Options of this subcommand. |
| `args` | arg or list | Positional arguments, in order. |
| `loadSpec` | string | Load this subcommand from another file, e.g. `aws/s3` → `specs/aws/s3.yaml`. |
| `requiresSubcommand` | bool | The command does nothing without a subcommand. |
| `filterStrategy` | `prefix`, `fuzzy` | `prefix` turns off fuzzy matching for these items. |
| `parserDirectives.flagsArePosixNoncompliant` | bool | `-name` is one option, not `-n -a -m -e`. |
| `parserDirectives.optionArgSeparators` | string or list | Separators between an option and its value, default `=`. |
| `additionalSuggestions` | list of suggestions | Extra items shown with the subcommands. |

## Option

| Field | Type | Meaning |
| --- | --- | --- |
| `name` | string or list | All spellings: `[-m, --message]`. **Required.** |
| `description`, `displayName`, `icon`, `priority`, `hidden`, `deprecated`, `insertValue` | | As for subcommands. |
| `args` | arg or list | The option's value(s). Without `args` the option is a flag. |
| `isRepeatable` | bool or number | May be given more than once (`true`), or up to N times. Otherwise it is not suggested again once used. |
| `isPersistent` | bool | Also valid in every subcommand below. |
| `isRequired` | bool | Sorted a little higher. |
| `requiresSeparator` | bool or string | `true`: written as `--opt=value`, and `=` is inserted with it. A string sets another separator. |
| `exclusiveOn` | list | Not suggested when one of these options is already used. |
| `dependsOn` | list | Documentation only for now. |

## Arg

| Field | Type | Meaning |
| --- | --- | --- |
| `name` | string | What the argument is: `branch`, `file`. |
| `description` | string | |
| `isOptional` | bool | May be left out. |
| `isVariadic` | bool | Takes any number of values. |
| `isCommand` | bool | The rest of the line is a command of its own (`sudo`, `time`, `xargs`). |
| `isScript` | bool | A script file: files are suggested. |
| `template` | `filepaths`, `folders` or a list | Suggest files and folders, or folders only. |
| `suggestions` | list | Fixed values. |
| `generators` | generator or list | Values computed when needed. |
| `filterStrategy` | `prefix`, `fuzzy` | |
| `loadSpec` | string | Like `isCommand`. |
| `default`, `optionsCanBreakVariadicArg`, `suggestCurrentToken` | | Accepted for Fig compatibility. |

## Suggestion

Either a plain string, or:

| Field | Type | Meaning |
| --- | --- | --- |
| `name` | string or list | **Required.** |
| `description`, `displayName`, `icon`, `priority`, `hidden`, `deprecated`, `insertValue` | | As above. |
| `type` | string | `file` or `folder` gives the item a file or folder icon. |

## Generator

A generator produces suggestions while you type. Use one of `script` or `template`.

| Field | Type | Meaning |
| --- | --- | --- |
| `script` | string or list | A shell command run with `zsh -f -c` in the current folder, or an argv list run directly. Each output line becomes a suggestion. |
| `splitOn` | string | Split the output on this instead of newlines. |
| `template` | `filepaths`, `folders` | List files instead of running a script. |
| `filter.extensions` | list | With `template`: only files with these extensions, e.g. `[js, mjs]`. `tar.gz` works. |
| `filter.equals` | list | Only these file names, e.g. `[Makefile]`. |
| `filter.matches` | string | Only names matching this regular expression. |
| `filter.filterFolders` | bool | Apply the filter to folders too (by default folders always show, so you can navigate). |
| `cache.ttl` | seconds | How long results are reused. Default 10. |
| `cache.cacheByDirectory` | bool | Separate results per folder. |
| `scriptTimeout` | seconds | Stop the script after this long. Default 5. |
| `trigger` | string | Run again when this character is typed, e.g. `/` for paths. |
| `getQueryTerm` | string | Match only the text after the last occurrence of this string, e.g. `,` for `a,b,c`. |
| `js` | object | Set by the [Fig importer](fig-import.md) only: points to JavaScript functions in the spec's `.js` companion. |

Scripts run with `NO_COLOR=1`, `TERM=dumb` and no pager, and without your `~/.zshrc`.

## Ranking

Items are ordered by, in this order of weight:

1. How the query matches: a prefix match beats a match inside the name, which beats a fuzzy match
   (`gco` → `git-checkout`). Exact case wins ties (`-l` before `-L`).
2. `priority`.
3. How often and how recently you picked the item.
4. Their order in the spec.

History suggestions always come last.
