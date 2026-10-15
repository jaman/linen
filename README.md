# Linen

A pure-Elixir library for reading and editing existing
`.xlsx` and `.xlsm` files with round-trip fidelity — no Rust, no Python, no
NIFs, no second runtime in your deployment.

```elixir
# Create from scratch
{:ok, book} = Linen.new()
{:ok, book} = Linen.rename_sheet(book, "Sheet1", "Summary")
{:ok, book} = Linen.add_sheet(book, "Data")
{:ok, book} = Linen.put_cell(book, "Data", "A1", "alpha")
:ok = Linen.save(book, "new.xlsx")

# Or open an existing workbook
{:ok, book} = Linen.open("inventory.xlsx")

# Read
Linen.sheet_names(book)                           #=> ["Sheet1", "Sheet2"]
Linen.get_cell(book, "Sheet1", "A1")              #=> {:ok, "widget"}
Linen.get_cell(book, "Sheet1", "B2")              #=> {:ok, 42}
Linen.get_cell(book, "Sheet1", "C3")              #=> {:ok, ~D[2024-01-15]}
Linen.get_formula(book, "Sheet1", "D4")           #=> {:ok, "=SUM(B2:B10)"}
Linen.get_style(book, "Sheet1", "A1")             #=> {:ok, %Linen.Style{...}}

# Write
{:ok, book} = Linen.put_cell(book, "Sheet1", "D1", "Updated")
{:ok, book} = Linen.put_cell(book, "Sheet1", "D2", 3.14)
{:ok, book} = Linen.put_cell(book, "Sheet1", "D3", true)
{:ok, book} = Linen.put_cell(book, "Sheet1", "D4", ~D[2024-06-01])
{:ok, book} = Linen.put_cell(book, "Sheet1", "D5", {:formula, "=SUM(A1:A10)"})

# Coordinates accept both A1 refs and {row, col} integer tuples
Linen.get_cell(book, "Sheet1", {2, 3})            #=> same as Linen.get_cell(book, "Sheet1", "C2")
{:ok, book} = Linen.put_cell(book, "Sheet1", {10, 5}, "tuple write")

# Merge / unmerge
{:ok, book} = Linen.merge_cells(book, "Sheet1", "A1:B2")
{:ok, ["A1:B2"]} = Linen.merged_ranges(book, "Sheet1")
{:ok, book} = Linen.unmerge_cells(book, "Sheet1", "A1:B2")

# Excel tables
{:ok, book} = Linen.add_table(book, "Sheet1", "A1:C10", name: "Sales")
{:ok, %Linen.Table{columns: ["Region", "Qty", "Amount"]}} = Linen.table(book, "Sales")
{:ok, book} = Linen.append_table_rows(book, "Sales", [["West", 4, 12.5]])
{:ok, book} = Linen.put_table_totals_row(book, "Sales", Amount: :sum)
{:ok, rows} = Linen.table_records(book, "Sales")  #=> [%{"Region" => "North", ...}, ...]

# Save
:ok = Linen.save(book, "inventory.xlsx")
```

## Why

The Elixir ecosystem has `Elixlsx` (write-only) and `xlsx_reader` (read-only),
but nothing that *edits existing* spreadsheets. Every team that
needs this today reaches for Python (`openpyxl`) or a Rust NIF — which drags
a second runtime into the deployment.

Linen fills that gap in pure Elixir.

## Status

**v0.1 — pre-alpha.** Core read/write/round-trip is solid and externally
validated against [umya-spreadsheet](https://crates.io/crates/umya-spreadsheet)
(Rust). 346 tests, zero credo issues, zero compile warnings.

### What works

- **Create** new `.xlsx` workbooks from scratch (`new/0`, `add_sheet/2`,
  `rename_sheet/3`, `remove_sheet/2`)
- Open `.xlsx` and `.xlsm` files
- Round-trip identity on untouched content (unknown XML, custom parts, VBA
  macros all pass through byte-for-byte)
- Read cell values: strings (shared + inline), numbers, booleans, dates,
  date-times, formula results, cell errors
- Read cell styles: font, fill, border, alignment, number format
- Write cell values: strings (through the SST with automatic dedup),
  numbers, booleans, `nil` (clear), `Date`, `NaiveDateTime`, formulas (with
  or without cached value)
- Sheet navigation: `sheet_names/1`, `sheet_path/2`
- Bulk reads: `cells/2` (map), `each_cell/2` (stream in row-major order)
- Get cell formula: `get_formula/3`
- Merge / unmerge cells with configurable overlap and value-preservation
  behaviour (`merge_cells/3,4`, `unmerge_cells/3,4`, `merged_ranges/2`)
- Style mutation (`put_style/4` — fluent font / fill / border / alignment
  / number-format merge)
- Defined names (`define_name/4`, `defined_names/1`, `remove_defined_name/3`)
- Structural row/column mutation (`insert_row/4`, `delete_row/4`,
  `insert_column/4`, `delete_column/4`). Cascades through formulas,
  merged ranges, defined names, conditional formatting, data validations,
  auto-filters, comments, tables, and drawing anchors — so formulas,
  charts, and comments keep pointing at the same logical cells after
  the shift. Structural changes touch only the target sheet; other sheets
  have just their formulas rewritten
- Excel tables (`add_table/4`, `tables/1,2`, `table/2`, `remove_table/2`,
  `rename_table/3`, `rename_table_column/4`, `resize_table/3`,
  `put_table_style/3`, `put_table_totals_row/3`,
  `remove_table_totals_row/2`, `table_rows/2`, `table_records/2`,
  `append_table_rows/3`). Structured references (`Sales[Amount]`,
  `[@Qty]`) are never rewritten by row/column shifts; column and table
  renames rewrite them everywhere; removing a table converts them to
  plain ranges

### Not yet

- Charts, pivot tables (pass through untouched but no mutation API)
- Embedded images (pass through untouched)

## Installation

```elixir
def deps do
  [{:linen, "~> 0.3"}]
end
```

Linen was published as `ex_v_ex` (`ExVEx`) up to 0.2.2. To move over, replace
`{:ex_v_ex, ...}` with `{:linen, "~> 0.3"}` and `ExVEx` with `Linen` in module names.

## Design

Three commitments drive the design:

1. **Lazy raw parts.** The archive is read into a flat `%{path => bytes}`
   map. Parts you never touch are written back byte-identical on save.
2. **Immutable functional API.** Every mutating operation returns a new
   `%Linen.Workbook{}`. No GenServers, no mutable references.
3. **Preserve over re-serialize.** When a part is mutated (a worksheet with
   a written cell; the styles.xml when a date write adds an xf; the
   sharedStrings.xml when a new string is interned), Linen surgically edits
   just the changed sub-tree and leaves the surrounding XML alone —
   namespaces, unknown attributes, and extension elements survive.

This is the same strategy used by [umya-spreadsheet](https://crates.io/crates/umya-spreadsheet)
(Rust), and stronger than [edit-xlsx](https://crates.io/crates/edit-xlsx)'s
full-deserialize-reserialize approach. It's also the only way to preserve
`.xlsm` VBA binaries byte-for-byte, which Linen verifies in its test suite.

## License

MIT. See [LICENSE](LICENSE).
