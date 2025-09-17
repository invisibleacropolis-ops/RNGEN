# Test Assets

This folder hosts data fixtures consumed by automated test suites.

- `wordlist_basic.tres` – Minimal `WordListResource` used by the hybrid strategy
  tests.
- `syllable_basic.tres` – Basic `SyllableSetResource` providing a short prefix /
  suffix catalogue.
- `markov_basic.tres` – Tiny `MarkovModelResource` that emits deterministic
  syllable pairs for integration scenarios.

Add additional resources here when future suites need richer datasets.
