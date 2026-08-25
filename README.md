# Extension Test Extension For Quarto

`extension-test` is an extension for Quarto that tests another Quarto extension against the Quarto CLI, in three layers: it checks the extension's schema, renders its test documents, and generates more documents from what that schema declares.

A render is not a test. An extension that fails to load writes a warning and still exits 0, so a check that reads the exit code alone reports success.

## Installation

Install it inside a `tests` directory, so it never mixes with the extension under test:

```bash
mkdir -p tests
cd tests && quarto add mcanouil/quarto-extension-test
```

Make `tests` a Quarto project, which is what lets a render resolve the extension under test:

```yaml
# tests/_quarto.yml
project:
  type: extension-test
```

Add `tests` to `.quartoignore`, so `quarto use template` never copies it into a reader's project.

If you are using version control, you will want to check in the `tests` directory.

## Usage

```bash
quarto pandoc lua tests/_extensions/*/extension-test/run.lua
```

It exits non-zero when a case fails, writes TAP to standard output, and writes JSON to `tests/_results/results.json`. Pass `--layer` to run one layer, and `--severity lenient` to report a finding rather than fail on it.

Write your own cases as `tests/*.qmd`, each with a `test:` block in its front matter. A repository with none still gets the other two layers.

## Documentation

The full documentation lives at <https://m.canouil.dev/quarto-extension-test/>: the `test:` front matter, what each layer checks, and the result format.

## Licence

[MIT](https://github.com/mcanouil/quarto-extension-test?tab=MIT-1-ov-file#readme).
