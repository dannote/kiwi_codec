defmodule KiwiCodec.RustlerGenerator.Sparse do
  @moduledoc """
  Generates generic sparse Kiwi schema decoders for Rustler native backends.

  Sparse decoders return maps containing only fields present in the payload plus
  a `__kiwi_module__` key identifying the generated Elixir schema module.
  """

  alias KiwiCodec.RustlerGenerator.RustExpr
  alias KiwiCodec.Schema.Enum, as: SchemaEnum
  alias KiwiCodec.Schema.{Message, Struct}
  alias RustQ.Rust

  @spec fragments([KiwiCodec.Schema.definition()], String.t(), map()) :: [RustQ.Rust.Fragment.t()]
  def fragments(definitions, module_prefix, definition_map) do
    Enum.map(definitions, &definition(&1, module_prefix, definition_map))
  end

  defp definition(%Struct{name: name, fields: fields}, module_prefix, definition_map) do
    field_entries =
      fields
      |> Enum.map(&field_entry(&1, definition_map))
      |> Enum.intersperse("\n")

    sparse_struct(name, module_prefix, length(fields) + 1, field_entries)
  end

  defp definition(%SchemaEnum{name: name, variants: variants}, _module_prefix, _definition_map) do
    variant_entries =
      variants
      |> Enum.with_index()
      |> Enum.map(fn {field, index} ->
        [
          Integer.to_string(field.value),
          " => ",
          enum_static(name, index),
          ", ",
          inspect(Macro.underscore(field.name)),
          ";"
        ]
      end)
      |> Enum.intersperse("\n")

    Rust.item([
      "kiwi_sparse_enum_decoder! {\n",
      "    fn decode_sparse_",
      RustExpr.ident(name),
      "_from_decoder;\n",
      "    env env;\n",
      "    decoder decoder;\n",
      "    variants [\n",
      RustExpr.indent(variant_entries, 8),
      "\n    ]\n",
      "}"
    ])
  end

  defp definition(%Message{name: name, fields: fields}, module_prefix, definition_map) do
    field_entries =
      fields
      |> Enum.map(fn field ->
        [Integer.to_string(field.id), " => ", field_entry(field, definition_map)]
      end)
      |> Enum.intersperse("\n")

    Rust.item([
      "kiwi_sparse_message_decoder! {\n",
      "    fn decode_sparse_",
      RustExpr.ident(name),
      "_from_decoder;\n",
      "    env env;\n",
      "    decoder decoder;\n",
      "    module ",
      inspect(module_name(module_prefix, name)),
      ";\n",
      "    definition ",
      inspect(name),
      ";\n",
      "    capacity ",
      Integer.to_string(length(fields) + 1),
      ";\n",
      "    fields [\n",
      RustExpr.indent(field_entries, 8),
      "\n    ]\n",
      "}"
    ])
  end

  defp sparse_struct(name, module_prefix, capacity, field_entries) do
    Rust.item([
      "kiwi_sparse_struct_decoder! {\n",
      "    fn decode_sparse_",
      RustExpr.ident(name),
      "_from_decoder;\n",
      "    env env;\n",
      "    decoder decoder;\n",
      "    module ",
      inspect(module_name(module_prefix, name)),
      ";\n",
      "    capacity ",
      Integer.to_string(capacity),
      ";\n",
      "    fields [\n",
      RustExpr.indent(field_entries, 8),
      "\n    ]\n",
      "}"
    ])
  end

  defp field_entry(field, definition_map) do
    [
      inspect(Macro.underscore(field.name)),
      ": ",
      field_expr(field, definition_map),
      ";"
    ]
  end

  defp field_expr(%{array?: true, type: "byte"}, _definition_map) do
    "decoder.read_byte_array(env)?"
  end

  defp field_expr(%{array?: true} = field, definition_map) do
    inner = scalar_expr(%{field | array?: false}, definition_map)
    ["decoder.read_repeated(|decoder| Ok(", inner, "))?.encode(env)"]
  end

  defp field_expr(field, definition_map) do
    [scalar_expr(field, definition_map), ".encode(env)"]
  end

  defp scalar_expr(%{type: type}, definition_map) do
    cond do
      primitive = RustExpr.primitive(type) ->
        primitive

      Map.has_key?(definition_map, type) ->
        ["decode_sparse_", RustExpr.ident(type), "_from_decoder(env, decoder)?"]
    end
  end

  defp enum_static(name, index), do: "#{String.upcase(Macro.underscore(name))}_ATOM_#{index}"

  defp module_name(module_prefix, name), do: "Elixir.#{module_prefix}.#{name}"
end
