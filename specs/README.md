# Specs

Each file describes one command: `git.yaml` is used when you type `git`. Folders hold parts of big
specs loaded with `loadSpec` (e.g. `aws/s3.yaml`).

- To add or fix a command, see [Adding a command](../docs/adding-a-command.md).
- Every field is described in the [spec format reference](../docs/spec-format.md).
- Most files were imported from [withfig/autocomplete](https://github.com/withfig/autocomplete)
  (MIT, see [LICENSE-fig.txt](LICENSE-fig.txt)) and can be edited like any other spec. A `.js` file
  next to a spec holds JavaScript imported from Fig; see [Fig import](../docs/fig-import.md).

Check your changes with:

```bash
swift run zest validate specs/<command>.yaml
```
