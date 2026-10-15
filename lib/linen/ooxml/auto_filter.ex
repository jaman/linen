defmodule Linen.OOXML.AutoFilter do
  @moduledoc """
  Cascades a `%Linen.Mutation.Shift{}` through an `<autoFilter>` node by
  rewriting its `ref` attribute (a single rectangular range).
  """

  alias Linen.Mutation.Shift, as: MutShift
  alias Linen.OOXML.SqrefShift

  @type node_tuple :: {String.t(), list(), list()}

  @spec shift_node(node_tuple(), MutShift.t()) :: node_tuple()
  def shift_node({"autoFilter", attrs, children}, %MutShift{} = shift) do
    new_attrs = Enum.map(attrs, &shift_ref(&1, shift))
    {"autoFilter", new_attrs, children}
  end

  defp shift_ref({"ref", value}, shift), do: {"ref", SqrefShift.shift(value, shift)}
  defp shift_ref(other, _shift), do: other
end
