<!--
AGENT GUIDELINES:
This README is a landing page, not the documentation. The configuration
reference, worked examples, and limitations belong on the website under docs/.

Required updates:
1. Replace %%placeholders%% with actual values.
2. Write a description that says what the extension does, in one or two
   sentences, starting from the reader's problem rather than the feature.
3. Replace the usage snippet with the smallest configuration that does
   something useful. Not every option; the reference page covers those.
4. Say which output formats apply, and what happens in the others.
5. Update or remove the Acknowledgements section.

Keep this file to roughly 40 lines. Anything longer belongs on the website.
Do not link rendered example output: examples are rendered in CI as a check and
are not deployed.
-->

# Extension Test

A Quarto extension.

**[Documentation](https://m.canouil.dev/quarto-extension-test)** &middot; [Reference](https://m.canouil.dev/quarto-extension-test/reference.html) &middot; [Examples](https://m.canouil.dev/quarto-extension-test/examples.html) &middot; [Changelog](https://m.canouil.dev/quarto-extension-test/changelog.html)

## Installation

```bash
quarto add mcanouil/quarto-extension-test
```

This will install the extension under the `_extensions` subdirectory.
If you are using version control, you will want to check in this directory.

## Usage

Add the metadata extension to your project's `_quarto.yml`:

```yaml
metadata-files:
  - _extensions/mcanouil/extension-test/_extension.yml
```

AGENT GUIDELINES: replace this with however the extension is actually consumed, and list the keys it provides.

See the [reference](https://m.canouil.dev/quarto-extension-test/reference.html) for every option.

