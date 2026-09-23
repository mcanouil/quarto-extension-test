# Changelog

## Unreleased

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
