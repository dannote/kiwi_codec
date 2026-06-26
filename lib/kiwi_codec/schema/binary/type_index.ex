defmodule KiwiCodec.Schema.Binary.TypeIndex do
  @moduledoc """
  Encodes and decodes type references in Kiwi's compact binary schema format.

  Binary schemas encode primitive types as bitwise-negated primitive indexes and
  user-defined schema types as non-negative indexes into the definition list.
  """

  alias KiwiCodec.Schema.Field

  @spec encode(Field.t(), %{String.t() => non_neg_integer()}) :: integer()
  def encode(%Field{type: type}, definition_index) do
    case KiwiCodec.PrimitiveType.binary_schema_index(type) do
      nil -> Map.fetch!(definition_index, type)
      primitive_index -> Bitwise.bnot(primitive_index)
    end
  end

  @spec decode(integer(), [KiwiCodec.Schema.definition()]) :: String.t()
  def decode(encoded_type, _definitions) when is_integer(encoded_type) and encoded_type < 0 do
    encoded_type
    |> Bitwise.bnot()
    |> KiwiCodec.PrimitiveType.binary_schema_name!()
  end

  def decode(encoded_type, definitions) when is_integer(encoded_type) do
    definitions
    |> Enum.fetch!(encoded_type)
    |> Map.fetch!(:name)
  end
end
