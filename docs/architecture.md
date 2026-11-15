# Architecture

zest has three parts that talk over a Unix socket:

```
┌──────────── terminal app (Terminal, VS Code, Cursor) ────────────┐
│  zsh                                                             │
│   └─ shell/zest.zsh  (ZLE hooks and key bindings)                │
└───────────┬──────────────────────────────────────────────────────┘
            │  ~/Library/Application Support/zest/zest.sock
            ▼
┌──────────── Zest.app (menu bar, Sources/ZestApp) ────────────────┐
│  SocketServer ─► CompletionController ─► Engine ─► SpecStore     │
│                        │                    ├─ GeneratorRunner   │
│                        │                    │   └─ JSRuntime     │
│                        ▼                    └─ UsageStore        │
│                  PopupController ◄─ CaretLocator (Accessibility) │
└──────────────────────────────────────────────────────────────────┘
```

## Why not a terminal proxy

Fig, Amazon Q and Kiro CLI start a pseudo-terminal between the terminal app and the shell
(`kiro-cli-term`) and parse everything the shell prints to know the command line. That works with
any shell, but adds a process to every terminal tab.

zsh already knows the command line: ZLE exposes it as `$BUFFER` and `$CURSOR`, and lets a plugin bind
keys. So zest's shell part is a ~200-line zsh script and nothing sits in the data path of your
terminal. The price is that only zsh is supported.

## The zsh script

[`shell/zest.zsh`](../shell/zest.zsh) does three things:

1. **Sends the line.** A `line-pre-redraw` hook sends `$BUFFER`, `$CURSOR` and `$PWD` whenever they
   change. It does not wait for an answer.
2. **Asks about keys.** Tab, ↑, ↓, Enter and Esc are bound to small widgets. Each asks the app what
   to do and waits up to 250 ms for one of three answers: *pass* (do what the key normally does;
   the widget calls the key's previous binding), *consumed* (the popup used the key) or *set* (replace
   the line and cursor).
3. **Ghost text.** The grey rest-of-the-line suggestion comes from zsh's own `$history`, in the shell,
   without the app.

If the app is not running, the script tries to connect at most every 3 seconds and otherwise stays
out of the way. A closed socket cannot kill the shell: writes run with `SIGPIPE` ignored locally.

## Socket protocol

One message per line. Fields are separated by `U+001F`; newlines inside the command line are sent as
`U+001E`. See [`ShellProtocol.swift`](../Sources/ZestCore/ShellProtocol.swift).

| From | Message | Fields |
| --- | --- | --- |
| zsh | `hello` | session id, shell pid, terminal bundle id (or `$TERM_PROGRAM`), history file |
| zsh | `aliases` | session id, `name=value`… |
| zsh | `line` | session id, folder, cursor, line |
| zsh | `key` | sequence number, `tab`/`up`/`down`/`enter`/`escape`, session id, folder, cursor, line |
| zsh | `end` | session id (the line was run or cancelled) |
| zsh | `exec` | session id, command (for history suggestions) |
| app | `r` | sequence number, `pass` / `ok` / `set`, [cursor, line] — the answer to `key` |

The socket file is created with mode `0600` in a folder only you can read.

## The engine (Sources/ZestCore)

`ZestCore` has no UI code, so it is fully covered by unit tests.

- **`Lexer`** splits the line like a shell would: quotes, backslashes, `|`, `&&`, `;`, `$(`, redirections.
  It finds the command the cursor is in and the word being typed. Offsets count Unicode scalars,
  the unit zsh uses for `$CURSOR`.
- **`Engine`** walks the words through the spec: subcommands, options (including `-abc`,
  `--opt=value`, persistent options), positional arguments, `isCommand` arguments such as
  `sudo <command>`. Then it collects candidates for the current word from the spec, generators, files
  and history.
- **`Matcher`** scores candidates: prefix > substring > fuzzy, with bonuses for word starts.
- **`Collector`** applies priorities and usage counts, removes duplicates and sorts.
- **`SpecStore`** finds spec files (your folder first, then the built-in ones) and parses them on first
  use. The app ships specs as JSON, compiled from the YAML at build time, because JSON loads much
  faster. Changed files are reloaded automatically.
- **`GeneratorRunner`** runs generator scripts in the background with a timeout and caches their output.
  When a result arrives, the popup updates.
- **`JSRuntime`** runs the JavaScript functions of specs imported from Fig, with the
  JavaScriptCore framework that comes with macOS. See [Fig import](fig-import.md).
- **`CompletionController`** is the popup's state machine: what is shown, which item is selected,
  what each key does. Also UI-free and tested.

## The app (Sources/ZestApp)

- **`CaretLocator`** asks the focused app, through the Accessibility API, where its text cursor is.
  Terminal.app reports the bounds of the insertion point. VS Code and Cursor (Electron) build their
  accessibility tree only after `AXManualAccessibility` is set; the focused element is then xterm.js'
  hidden text area, which sits on the cursor.
- **`PopupController`** shows a borderless, non-activating `NSPanel` under the cursor (or above it
  near the bottom of the screen), aligned with the start of the word. The panel never takes keyboard
  focus. It is only shown while the terminal that sent the line is the frontmost app.
- **`Updater`** checks GitHub Releases once a day. Before installing it verifies the SHA-256 checksum
  and that the new app is signed with the same certificate as the running one.

## Files

| Path | What |
| --- | --- |
| `~/Library/Application Support/zest/zest.sock` | The socket |
| `~/Library/Application Support/zest/zest.zsh` | The zsh script, copied from the app on every launch |
| `~/Library/Application Support/zest/settings.zsh` | Settings the shell reads at startup |
| `~/Library/Application Support/zest/usage.json` | How often you picked each suggestion |
| `~/.config/zest/specs/` | Your specs |
| `defaults read io.github.rostik32.zest` | App settings |
