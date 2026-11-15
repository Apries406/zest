var __zestSpec = (function () {
  const describe = (n) => "item " + n;
  return {
    name: "jst",
    subcommands: [
      { name: "post", args: { generators: { script: "list-items",
        postProcess: function (out) { return out.split(",").map((n) => ({ name: n, description: describe(n) })); } } } },
      { name: "custom", args: { generators: {
        custom: async function (tokens, exec) {
          const r = await exec({ command: "other-items", args: [] });
          return r.stdout.split(",").map((n) => ({ name: n }));
        } } } },
    ],
  };
})();
