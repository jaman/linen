defmodule Linen.CreationTest do
  use ExUnit.Case, async: true

  alias Linen.Test.Fixtures

  describe "new/0" do
    test "returns a blank single-sheet workbook" do
      assert {:ok, book} = Linen.new()
      assert Linen.sheet_names(book) == ["Sheet1"]
      assert {:ok, nil} = Linen.get_cell(book, "Sheet1", "A1")
    end

    test "new + save + reopen round-trips" do
      out = Fixtures.tmp_path("from_scratch.xlsx")
      on_exit(fn -> File.rm(out) end)

      {:ok, book} = Linen.new()
      {:ok, book} = Linen.put_cell(book, "Sheet1", "A1", "Hello")
      {:ok, book} = Linen.put_cell(book, "Sheet1", "B1", 42)

      :ok = Linen.save(book, out)
      {:ok, reopened} = Linen.open(out)

      assert Linen.sheet_names(reopened) == ["Sheet1"]
      assert Linen.get_cell(reopened, "Sheet1", "A1") == {:ok, "Hello"}
      assert Linen.get_cell(reopened, "Sheet1", "B1") == {:ok, 42}
    end
  end

  describe "add_sheet/2" do
    test "appends a new empty sheet" do
      {:ok, book} = Linen.new()
      {:ok, book} = Linen.add_sheet(book, "Inventory")

      assert Linen.sheet_names(book) == ["Sheet1", "Inventory"]
      assert {:ok, nil} = Linen.get_cell(book, "Inventory", "A1")
    end

    test "multiple sheets can be added" do
      {:ok, book} = Linen.new()
      {:ok, book} = Linen.add_sheet(book, "A")
      {:ok, book} = Linen.add_sheet(book, "B")
      {:ok, book} = Linen.add_sheet(book, "C")

      assert Linen.sheet_names(book) == ["Sheet1", "A", "B", "C"]
    end

    test "rejects a duplicate name" do
      {:ok, book} = Linen.new()
      assert {:error, :duplicate_sheet_name} = Linen.add_sheet(book, "Sheet1")
    end

    test "added sheets accept cell writes that survive save+reopen" do
      out = Fixtures.tmp_path("added_sheets.xlsx")
      on_exit(fn -> File.rm(out) end)

      {:ok, book} = Linen.new()
      {:ok, book} = Linen.add_sheet(book, "Data")
      {:ok, book} = Linen.add_sheet(book, "Summary")
      {:ok, book} = Linen.put_cell(book, "Data", "A1", "row1")
      {:ok, book} = Linen.put_cell(book, "Summary", "B2", 3.14)

      :ok = Linen.save(book, out)
      {:ok, reopened} = Linen.open(out)

      assert Linen.sheet_names(reopened) == ["Sheet1", "Data", "Summary"]
      assert Linen.get_cell(reopened, "Data", "A1") == {:ok, "row1"}
      assert Linen.get_cell(reopened, "Summary", "B2") == {:ok, 3.14}
    end
  end

  describe "rename_sheet/3" do
    test "changes the sheet name while preserving its contents" do
      out = Fixtures.tmp_path("renamed.xlsx")
      on_exit(fn -> File.rm(out) end)

      {:ok, book} = Linen.new()
      {:ok, book} = Linen.put_cell(book, "Sheet1", "A1", "kept")
      {:ok, book} = Linen.rename_sheet(book, "Sheet1", "Main")

      :ok = Linen.save(book, out)
      {:ok, reopened} = Linen.open(out)

      assert Linen.sheet_names(reopened) == ["Main"]
      assert Linen.get_cell(reopened, "Main", "A1") == {:ok, "kept"}
      assert {:error, :unknown_sheet} = Linen.get_cell(reopened, "Sheet1", "A1")
    end

    test "rejects renaming an unknown sheet" do
      {:ok, book} = Linen.new()
      assert {:error, :unknown_sheet} = Linen.rename_sheet(book, "Ghost", "Main")
    end

    test "rejects a rename that collides with another sheet" do
      {:ok, book} = Linen.new()
      {:ok, book} = Linen.add_sheet(book, "Target")

      assert {:error, :duplicate_sheet_name} =
               Linen.rename_sheet(book, "Sheet1", "Target")
    end

    test "renaming to the same name is a no-op" do
      {:ok, book} = Linen.new()
      assert {:ok, ^book} = Linen.rename_sheet(book, "Sheet1", "Sheet1")
    end
  end

  describe "remove_sheet/2" do
    test "drops the sheet from the workbook" do
      {:ok, book} = Linen.new()
      {:ok, book} = Linen.add_sheet(book, "Temp")
      {:ok, book} = Linen.add_sheet(book, "Keep")
      {:ok, book} = Linen.remove_sheet(book, "Temp")

      assert Linen.sheet_names(book) == ["Sheet1", "Keep"]
    end

    test "removes the worksheet part and its manifest entries" do
      out = Fixtures.tmp_path("removed.xlsx")
      on_exit(fn -> File.rm(out) end)

      {:ok, book} = Linen.new()
      {:ok, book} = Linen.add_sheet(book, "Scratch")
      {:ok, book} = Linen.put_cell(book, "Scratch", "A1", "will vanish")

      # Grab the path of the scratch sheet before removal
      {:ok, scratch_path} = Linen.sheet_path(book, "Scratch")
      {:ok, book} = Linen.remove_sheet(book, "Scratch")

      :ok = Linen.save(book, out)
      {:ok, reopened} = Linen.open(out)

      refute Map.has_key?(reopened.parts, scratch_path)

      refute Enum.any?(
               reopened.content_types.overrides,
               &(&1.part_name == "/" <> scratch_path)
             )

      refute Enum.any?(
               reopened.workbook_rels.entries,
               &String.ends_with?(&1.target, Path.basename(scratch_path))
             )

      assert Linen.sheet_names(reopened) == ["Sheet1"]
    end

    test "rejects removing an unknown sheet" do
      {:ok, book} = Linen.new()
      assert {:error, :unknown_sheet} = Linen.remove_sheet(book, "Ghost")
    end

    test "rejects removing the last remaining sheet" do
      {:ok, book} = Linen.new()
      assert {:error, :last_sheet} = Linen.remove_sheet(book, "Sheet1")
    end
  end

  describe "full creation workflow" do
    test "build a multi-sheet template from scratch and round-trip it" do
      out = Fixtures.tmp_path("full_template.xlsx")
      on_exit(fn -> File.rm(out) end)

      {:ok, book} = Linen.new()
      {:ok, book} = Linen.rename_sheet(book, "Sheet1", "Summary")
      {:ok, book} = Linen.add_sheet(book, "Data A")
      {:ok, book} = Linen.add_sheet(book, "Data B")
      {:ok, book} = Linen.add_sheet(book, "Formulas")
      {:ok, book} = Linen.put_cell(book, "Data A", "A1", "alpha")
      {:ok, book} = Linen.put_cell(book, "Data B", "A1", 100)

      {:ok, book} =
        Linen.put_cell(book, "Formulas", "A1", {:formula, "=SUM('Data B'!A1:A10)"})

      {:ok, book} = Linen.merge_cells(book, "Summary", "A1:C1", preserve_values: true)

      :ok = Linen.save(book, out)
      {:ok, reopened} = Linen.open(out)

      assert Linen.sheet_names(reopened) == ["Summary", "Data A", "Data B", "Formulas"]
      assert Linen.get_cell(reopened, "Data A", "A1") == {:ok, "alpha"}
      assert Linen.get_cell(reopened, "Data B", "A1") == {:ok, 100}
      assert {:ok, "=SUM('Data B'!A1:A10)"} = Linen.get_formula(reopened, "Formulas", "A1")
      assert {:ok, ["A1:C1"]} = Linen.merged_ranges(reopened, "Summary")
    end
  end
end
