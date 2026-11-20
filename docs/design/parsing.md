# TODO (Anthony): write this note

Facts and decisions for the parsing design note. Bullets only; turn them into prose.

## Decision

- Keep slicing kubectl's default table text (and `-o wide`). Do not switch resources to `-o json` under the hood.
- Add a typed overlay: columns named in one explicit map (`$script:KubectlColumnKinds` in `src/private/ConvertTo-KubectlValue.ps1`) become `KubectlValue` objects; every other cell stays a string.
- A `KubectlValue` holds `Text` (exactly what kubectl printed) and `Value` (long, double, or TimeSpan). `ToString()` returns `Text`, so the default table, `Format-List`, `Export-Csv`, `-match` and string interpolation show kubectl's text.
- Anything that does not parse stays the plain string kubectl printed. Parsing never throws.

## Why slicing, not JSON

- "True to source" is the main constraint: the cells are what kubectl shows, including its server-side printer columns (`READY`, `RESTARTS` with `(5m ago)`, `STATUS` reasons, `AGE`). `-o json` has no such columns; each would be recomputed in PowerShell and could drift from kubectl's version.
- JSON means one shape per resource kind (and per CRD), a second code path per resource, and a larger surface for version drift. Slicing is one generic converter plus a fixture per view.
- Format views are generated from fixtures (the header line), so a new resource costs a `formats.json` entry plus fixtures, no new code.
- JSON would carry more data (labels, owner references, full status), but that is what `-o json | ConvertFrom-Json` already gives users.

## Alternatives considered for typing

- Typed properties (int, TimeSpan) with the format view rendering the original text: right-aligns numeric columns in `Format-Table` (the table would no longer look like kubectl's), and the original text would need a second hidden property.
- Chosen: a small class with `IComparable`. Left-aligned like text, same cell text, sorts by value.
- Tested in PowerShell 7.4: `Sort-Object`, `-gt/-lt/-ge/-le/-eq` against numbers and `[TimeSpan]`, `Measure-Object -Sum/-Average` (via `IConvertible`), `Export-Csv`, `Format-List` all work.
- PowerShell converts the right-hand operand to the left operand's type before comparing; that is why the class has constructors for number, TimeSpan and string.

## Type map (column -> value)

- RESTARTS: `3` and `3 (5m ago)` -> 3 (the "ago" text is kept in `Text`, not parsed).
- AGE, LAST SEEN, DURATION: kubectl durations (`45s`, `5m12s`, `3h15m`, `3d13h`, `120d`, `2y45d`) -> TimeSpan; a year is 365 days.
- READY, COMPLETIONS: `1/2` -> 0.5 (ready / total; `0/0` counts as 1). `2/4` and `1/2` compare equal.
- UP-TO-DATE, AVAILABLE, DATA: integer.
- CPU(cores): `250m` -> 250 (millicores); bare cores `2` -> 2000.
- MEMORY(bytes), CAPACITY: `128Mi` -> bytes (binary suffixes 1024-based, `k/M/G/T/P/E` 1000-based).
- CPU(%), MEMORY(%): `26%` -> 26.
- `<unknown>`, `<invalid>`, `<none>`, `<nil>` in a typed column: typed cell with no `Value`; it sorts after every real value, so `-lt` filters leave it out and `-gt` filters include it.
- Empty cells (e.g. an unbound PVC's CAPACITY) stay `''`, a plain string.

## Known limits

- Cells containing `;` or `"`: rows are split with an inserted `;` and read by `ConvertFrom-Csv -Delimiter ';'`, so such a cell breaks its row or its quoting. Seen only in free text columns (events MESSAGE) so far; not seen in the allow-listed columns.
- Wide Unicode (CJK, emoji) in names: kubectl pads by rune count, not display width; column starts come from the header, so alignment can shift.
- kubectl layout changes: columns come from the header line, so added or reordered columns work, a renamed column silently loses its type (string). Fixtures pin one kubectl version (1.31); refresh with `repoScripts/Update-Fixtures.ps1` and review the diff.
- Column names are mapped globally, not per resource; a future resource that reuses a typed name for something else (`READY`, `DATA`, `CAPACITY`) would be mis-typed. Check when adding resources.
- `Group-Object` groups by the cell's text, so `3` and `3 (5m ago)` are separate groups although `-eq` says they are equal.
- `ConvertTo-Json` shows `{Value, Text}` per typed cell (and a full TimeSpan object); there is no hook to serialize the plain value. `Export-Csv` writes the text.
- String right-hand sides: `-lt '1h'` does not parse kubectl durations; use a `[TimeSpan]`. `-gt '3'` works (numeric strings are read).
- `k` only converts default tables and `-o wide`. `-o json/yaml`, `-w`, `--no-headers`, comma lists (`pods,svc`) and unknown verbs/resources go straight to kubectl untouched.
- `--` is lost for simple functions (README). `k exec -- ...` style commands need `kubectl` directly.
- After a failed `k`: a non-terminating error (`KubectlFailed`) is written and `$LASTEXITCODE` is the real exit code. `$?` stays true after a script function returns, whatever it wrote to the error stream, so `$?` is not a failure signal; with `$global:ErrorActionPreference = 'Stop'` the error throws.

## Open questions for the owner

- Should the READY fraction expose the pieces (`Ready`, `Total`) as well?
- Is "unknown sorts last" the right call, or should it sort first?
- Worth shipping a proper type/format extension so `Value` could be hidden from `ConvertTo-Json`?
