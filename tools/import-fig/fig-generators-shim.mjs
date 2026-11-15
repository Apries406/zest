// Replaces `filepaths` and `folders` from @fig/autocomplete-generators while importing.
// Instead of JavaScript generators they return a marker that import.mjs turns into a
// native `template` generator with a `filter`, which zest handles without JavaScript.
import * as real from "@fig/autocomplete-generators/lib/index.js";

const marker = (options) => {
  const fn = () => marker(options);
  fn.__zestFiles = options;
  return fn;
};

export const filepaths = Object.assign((options = {}) => marker(options), { __zestFiles: {} });
export const folders = Object.assign(() => marker({ showFolders: "only" }), { __zestFiles: { showFolders: "only" } });
export const { keyValue, keyValueList, valueList, ai } = real;
