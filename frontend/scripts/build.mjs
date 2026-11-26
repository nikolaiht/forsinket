// Builds the app into dist/: the compiled Elm, the page that loads it, the
// style sheet and the fonts. `--dev` skips optimisation, which keeps Elm's
// debug-friendly output and is quicker.
import { execFileSync } from "node:child_process";
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import UglifyJS from "uglify-js";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dist = join(root, "dist");
const optimise = !process.argv.includes("--dev");

rmSync(dist, { recursive: true, force: true });
mkdirSync(join(dist, "fonts"), { recursive: true });

const compiled = join(dist, "elm.js");
execFileSync(
  join(root, "node_modules", ".bin", "elm"),
  ["make", "src/Main.elm", ...(optimise ? ["--optimize"] : []), `--output=${compiled}`],
  { cwd: root, stdio: "inherit" },
);

if (optimise) {
  // The two passes and their flags are the ones the Elm guide gives:
  // https://guide.elm-lang.org/optimization/asset_size.html
  // They are only safe because Elm functions have no side effects.
  const pureFunctions = "F2,F3,F4,F5,F6,F7,F8,F9,A2,A3,A4,A5,A6,A7,A8,A9".split(",");
  const compressed = UglifyJS.minify(readFileSync(compiled, "utf8"), {
    compress: { pure_funcs: pureFunctions, pure_getters: true, keep_fargs: false, unsafe_comps: true, unsafe: true },
    mangle: false,
  });
  if (compressed.error) throw compressed.error;
  const mangled = UglifyJS.minify(compressed.code, { compress: false, mangle: true });
  if (mangled.error) throw mangled.error;
  writeFileSync(compiled, mangled.code);
}

cpSync(join(root, "static"), dist, { recursive: true });

// Barlow, under the SIL Open Font License, from the @fontsource packages.
const fonts = [
  ["barlow", "barlow-latin-400-normal.woff2"],
  ["barlow", "barlow-latin-500-normal.woff2"],
  ["barlow", "barlow-latin-600-normal.woff2"],
  ["barlow-semi-condensed", "barlow-semi-condensed-latin-600-normal.woff2"],
];
for (const [family, file] of fonts) {
  cpSync(join(root, "node_modules", "@fontsource", family, "files", file), join(dist, "fonts", file));
}

console.log(`Built ${optimise ? "optimised" : "development"} app in dist/`);
