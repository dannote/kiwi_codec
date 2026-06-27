defmodule KiwiCodec.RustlerGenerator.Skip do
  @moduledoc """
  Generates generic Kiwi schema skip decoders for Rustler native backends.

  Skip decoders consume encoded values without allocating decoded Elixir terms.
  They are schema-generic and intended for callers that project only selected
  fields from a Kiwi payload.
  """

  alias KiwiCodec.RustlerGenerator.RustExpr
  alias KiwiCodec.Schema.Enum, as: SchemaEnum
  alias KiwiCodec.Schema.{Message, Struct}
  alias RustQ.Rust

  @spec fragments([KiwiCodec.Schema.definition()], map()) :: [RustQ.Rust.Fragment.t()]
  def fragments(definitions, definition_map) do
    Enum.map(definitions, &definition(&1, definition_map))
  end

  @spec field_expr(map(), map()) :: iodata()
  def field_expr(%{array?: true, type: "byte"}, _definition_map),
    do: "kiwi_skip_bytes_value(decoder)?"

  def field_expr(%{array?: true, type: type}, definition_map) do
    ["kiwi_skip_repeated(decoder, ", scalar_skip_function(type, definition_map), ")?"]
  end

  def field_expr(%{type: type}, definition_map),
    do: [scalar_skip_function(type, definition_map), "(decoder)?"]

  @spec message_arm(map(), map()) :: RustQ.Rust.Fragment.t()
  def message_arm(field, definition_map) do
    Rust.arm([Integer.to_string(field.id), " => { ", field_expr(field, definition_map), "; },"])
  end

  defp definition(%SchemaEnum{name: name}, _definition_map) do
    Rust.item([
      "kiwi_skip_enum_decoder! {\n",
      "    fn skip_",
      RustExpr.ident(name),
      "_from_decoder;\n",
      "    decoder decoder;\n",
      "}"
    ])
  end

  defp definition(%Struct{name: name, fields: fields}, definition_map) do
    field_kinds =
      fields
      |> Enum.map(&[field_skip_kind(&1, definition_map), ";"])
      |> Enum.intersperse("\n")

    Rust.item([
      "kiwi_skip_struct_decoder! {\n",
      "    fn skip_",
      RustExpr.ident(name),
      "_from_decoder;\n",
      "    decoder decoder;\n",
      "    fields [\n",
      RustExpr.indent(field_kinds, 8),
      "\n    ]\n",
      "}"
    ])
  end

  defp definition(%Message{name: name, fields: fields}, definition_map) do
    field_entries =
      fields
      |> Enum.map(fn field ->
        [Integer.to_string(field.id), " => ", field_skip_kind(field, definition_map), ";"]
      end)
      |> Enum.intersperse("\n")

    Rust.item([
      "kiwi_skip_message_decoder! {\n",
      "    fn skip_",
      RustExpr.ident(name),
      "_from_decoder;\n",
      "    decoder decoder;\n",
      "    definition ",
      inspect(name),
      ";\n",
      "    fields [\n",
      RustExpr.indent(field_entries, 8),
      "\n    ]\n",
      "}"
    ])
  end

  defp field_skip_kind(%{array?: true, type: "byte"}, _definition_map),
    do: "bytes kiwi_skip_bytes_value"

  defp field_skip_kind(%{array?: true, type: type}, definition_map) do
    ["repeated ", scalar_skip_function(type, definition_map)]
  end

  defp field_skip_kind(%{type: type}, definition_map) do
    ["one ", scalar_skip_function(type, definition_map)]
  end

  defp scalar_skip_function(type, definition_map) do
    cond do
      KiwiCodec.PrimitiveType.name?(type) ->
        ["kiwi_skip_", RustExpr.ident(type), "_value"]

      Map.has_key?(definition_map, type) ->
        ["skip_", RustExpr.ident(type), "_from_decoder"]
    end
  end
end
