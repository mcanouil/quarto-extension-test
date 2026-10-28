# Changelog

## Unreleased

- fix: Run the actions of the release a consumer pins the reusable workflow to. The pins had stayed at `0.1.2`, and now follow each release. (#38)

## 0.2.0 (2026-10-18)

- feat: Read test cases from the `_quarto.tests` block that q2 uses, in place of the `test:` block, which is removed.
- feat: Fail the render of a test document on a logged warning by default. Use `noErrors` to allow warnings. Generated smoke documents and the demo `example.qmd` still allow warnings.
- feat: Check the content of an output with `ensureFileRegexMatches`, `ensureTypstFileRegexMatches`, `ensureDocxRegexMatches`, `printsMessage`, and `fileExists`.
- feat: Check how many times a message appears with `count` in `printsMessage`, and reject warnings a document does not expect with `warnings: exhaustive`.
- feat: Run a check command of your own after the assertions of each format pass, with `check` under `run.extension-test`. The reusable workflow can set up Node.js and Playwright for it with `node-version` and `playwright-browsers`.
- feat: Run the test documents on q2 as well, with `q2-channels` in the reusable workflow. The runner gains `--stage` and `--unstage`, and leaves out the documents whose verdict q2 cannot share.
- feat: Keep the console output of a render that fails with no diagnostic output, and name it as `output` in the case failure. (#33)
- fix: Report a `printsMessage` count that is too large to be a whole number, such as `1e308`, as an invalid assertion. The render no longer crashes on it.
- fix: Fail a check that prints `Bail out!`, read `# SKIP:` and `# TODO:` with a colon as directives, and reject a `check` that holds only whitespace. Timeout messages now print whole seconds, such as `6` in place of `6.0`. (#26)
- fix: Reject a `timeout` over `86400` seconds as an invalid option. A huge value such as `1e308` no longer stops the render layer. (#27)
- fix: Fail a `fileExists` entry that names a directory, as q2 does. (#29)
- fix: Kill a render or check command that ignores SIGTERM, 10 seconds after its timeout. (#30)
- fix: Read a warning whose `(W)` marker and text reach the render log in separate records as one warning. A document that warns no longer passes the default rule by chance. (#34)

## 0.1.2 (2026-09-23)

### Bug Fixes

- fix: Remove the placeholder extension schema, which offered an `example-option` that the extension never read. (#14)

### Documentation

- docs: Document the `test:` front matter, the runner options, each layer, and the result format on the website. (#14)

## 0.1.1 (2026-09-23)

### Refactoring

- build: Fetch the schema validator from a Quarto Wizard release asset rather than a raw path inside its repository, which a refactor could move without notice. The vendored file is unchanged. (#11)

## 0.1.0 (2026-09-06)

### New Features

- feat: Initial release.
