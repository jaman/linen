defmodule Linen.InsertRowTest do
  use ExUnit.Case, async: true

  alias Linen.Test.Fixtures

  setup do
    out = Fixtures.tmp_path("insert_row.xlsx")
    on_exit(fn -> File.rm(out) end)
    %{out: out}
  end

  describe "insert_row/4 — basic cell shift" do
    test "cells at or below the insert point move down", %{out: out} do
      {:ok, book} = Linen.new()
      {:ok, book} = Linen.put_cell(book, "Sheet1", "A1", "header")
      {:ok, book} = Linen.put_cell(book, "Sheet1", "A3", "row3")
      {:ok, book} = Linen.put_cell(book, "Sheet1", "A5", "row5")

      {:ok, book} = Linen.insert_row(book, "Sheet1", 3)

      :ok = Linen.save(book, out)
      {:ok, reopened} = Linen.open(out)

      assert Linen.get_cell(reopened, "Sheet1", "A1") == {:ok, "header"}
      assert Linen.get_cell(reopened, "Sheet1", "A3") == {:ok, nil}
      assert Linen.get_cell(reopened, "Sheet1", "A4") == {:ok, "row3"}
      assert Linen.get_cell(reopened, "Sheet1", "A6") == {:ok, "row5"}
    end

    test "inserting multiple rows at once", %{out: out} do
      {:ok, book} = Linen.new()
      {:ok, book} = Linen.put_cell(book, "Sheet1", "A5", "five")
      {:ok, book} = Linen.insert_row(book, "Sheet1", 3, 3)

      :ok = Linen.save(book, out)
      {:ok, reopened} = Linen.open(out)

      assert Linen.get_cell(reopened, "Sheet1", "A8") == {:ok, "five"}
    end
  end

  describe "insert_row/4 — other sheets" do
    test "cells on other sheets stay where they are", %{out: out} do
      {:ok, book} = Linen.new()
      {:ok, book} = Linen.add_sheet(book, "Other")
      {:ok, book} = Linen.put_cell(book, "Other", "A5", "keep")
      {:ok, book} = Linen.merge_cells(book, "Other", "B5:C6")
      {:ok, book} = Linen.put_cell(book, "Sheet1", "A5", "move")

      {:ok, book} = Linen.insert_row(book, "Sheet1", 2)

      :ok = Linen.save(book, out)
      {:ok, reopened} = Linen.open(out)

      assert Linen.get_cell(reopened, "Other", "A5") == {:ok, "keep"}
      assert Linen.merged_ranges(reopened, "Other") == {:ok, ["B5:C6"]}
      assert Linen.get_cell(reopened, "Sheet1", "A6") == {:ok, "move"}
    end

    test "formulas on other sheets that point at the shifted sheet update", %{out: out} do
      {:ok, book} = Linen.new()
      {:ok, book} = Linen.add_sheet(book, "Other")
      {:ok, book} = Linen.put_cell(book, "Other", "A1", {:formula, "=Sheet1!A5+A5"})

      {:ok, book} = Linen.insert_row(book, "Sheet1", 2)

      :ok = Linen.save(book, out)
      {:ok, reopened} = Linen.open(out)

      assert Linen.get_formula(reopened, "Other", "A1") == {:ok, "=Sheet1!A6+A5"}
    end
  end

  describe "insert_row/4 — formula rewriting" do
    test "formulas referencing shifted cells update", %{out: out} do
      {:ok, book} = Linen.new()
      {:ok, book} = Linen.put_cell(book, "Sheet1", "A5", 10)
      {:ok, book} = Linen.put_cell(book, "Sheet1", "B1", {:formula, "=A5+1"})

      {:ok, book} = Linen.insert_row(book, "Sheet1", 3)

      :ok = Linen.save(book, out)
      {:ok, reopened} = Linen.open(out)

      assert Linen.get_formula(reopened, "Sheet1", "B1") == {:ok, "=A6+1"}
    end

    test "range formulas expand", %{out: out} do
      {:ok, book} = Linen.new()
      {:ok, book} = Linen.put_cell(book, "Sheet1", "B1", {:formula, "=SUM(A1:A10)"})
      {:ok, book} = Linen.insert_row(book, "Sheet1", 5, 2)

      :ok = Linen.save(book, out)
      {:ok, reopened} = Linen.open(out)

      assert Linen.get_formula(reopened, "Sheet1", "B1") == {:ok, "=SUM(A1:A12)"}
    end

    test "formulas referencing cells above the insert point are unchanged", %{out: out} do
      {:ok, book} = Linen.new()
      {:ok, book} = Linen.put_cell(book, "Sheet1", "B1", {:formula, "=A1+A2"})
      {:ok, book} = Linen.insert_row(book, "Sheet1", 5)

      :ok = Linen.save(book, out)
      {:ok, reopened} = Linen.open(out)

      assert Linen.get_formula(reopened, "Sheet1", "B1") == {:ok, "=A1+A2"}
    end
  end

  describe "insert_row/4 — merged cells" do
    test "merged range below the insert shifts down", %{out: out} do
      {:ok, book} = Linen.new()
      {:ok, book} = Linen.merge_cells(book, "Sheet1", "A5:B7")
      {:ok, book} = Linen.insert_row(book, "Sheet1", 3, 2)

      :ok = Linen.save(book, out)
      {:ok, reopened} = Linen.open(out)

      assert {:ok, ["A7:B9"]} = Linen.merged_ranges(reopened, "Sheet1")
    end

    test "merged range above the insert is unchanged", %{out: out} do
      {:ok, book} = Linen.new()
      {:ok, book} = Linen.merge_cells(book, "Sheet1", "A1:B2")
      {:ok, book} = Linen.insert_row(book, "Sheet1", 5)

      :ok = Linen.save(book, out)
      {:ok, reopened} = Linen.open(out)

      assert {:ok, ["A1:B2"]} = Linen.merged_ranges(reopened, "Sheet1")
    end
  end

  describe "insert_row/4 — defined names" do
    test "defined names referencing shifted cells update", %{out: out} do
      {:ok, book} = Linen.new()
      {:ok, book} = Linen.define_name(book, "Total", "Sheet1!$A$5")
      {:ok, book} = Linen.insert_row(book, "Sheet1", 3)

      :ok = Linen.save(book, out)
      {:ok, reopened} = Linen.open(out)

      assert [%{name: "Total", reference: "Sheet1!$A$6"}] = Linen.defined_names(reopened)
    end
  end

  describe "delete_row/4" do
    test "removes rows in the deletion span and shifts below up", %{out: out} do
      {:ok, book} = Linen.new()
      {:ok, book} = Linen.put_cell(book, "Sheet1", "A1", "keep")
      {:ok, book} = Linen.put_cell(book, "Sheet1", "A3", "drop")
      {:ok, book} = Linen.put_cell(book, "Sheet1", "A5", "survive")
      {:ok, book} = Linen.delete_row(book, "Sheet1", 3)

      :ok = Linen.save(book, out)
      {:ok, reopened} = Linen.open(out)

      assert Linen.get_cell(reopened, "Sheet1", "A1") == {:ok, "keep"}
      assert Linen.get_cell(reopened, "Sheet1", "A3") == {:ok, nil}
      assert Linen.get_cell(reopened, "Sheet1", "A4") == {:ok, "survive"}
    end

    test "formulas referencing deleted rows become #REF!", %{out: out} do
      {:ok, book} = Linen.new()
      {:ok, book} = Linen.put_cell(book, "Sheet1", "A5", 10)
      {:ok, book} = Linen.put_cell(book, "Sheet1", "B1", {:formula, "=A5+1"})
      {:ok, book} = Linen.delete_row(book, "Sheet1", 5)

      :ok = Linen.save(book, out)
      {:ok, reopened} = Linen.open(out)

      assert {:ok, formula} = Linen.get_formula(reopened, "Sheet1", "B1")
      assert formula =~ "#REF!"
    end
  end

  describe "insert_column/4" do
    test "cells right of the insert column shift right", %{out: out} do
      {:ok, book} = Linen.new()
      {:ok, book} = Linen.put_cell(book, "Sheet1", "A1", "a")
      {:ok, book} = Linen.put_cell(book, "Sheet1", "C1", "c")
      {:ok, book} = Linen.insert_column(book, "Sheet1", 2)

      :ok = Linen.save(book, out)
      {:ok, reopened} = Linen.open(out)

      assert Linen.get_cell(reopened, "Sheet1", "A1") == {:ok, "a"}
      assert Linen.get_cell(reopened, "Sheet1", "D1") == {:ok, "c"}
    end
  end

  describe "errors" do
    test "rejects an unknown sheet" do
      {:ok, book} = Linen.new()
      assert {:error, :unknown_sheet} = Linen.insert_row(book, "Ghost", 1)
    end
  end
end
