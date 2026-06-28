defmodule KiwiCodec.RustlerGenerator.Sparse do
  @moduledoc """
  Generates generic sparse Kiwi schema decoders for Rustler native backends.

  Sparse decoders return maps containing only fields present in the payload plus
  a `__kiwi_module__` key identifying the generated Elixir schema module.
  """

  alias KiwiCodec.RustlerGenerator.DecoderMacro
  alias KiwiCodec.RustlerGenerator.Name
  alias KiwiCodec.RustlerGenerator.RustExpr
  alias KiwiCodec.Schema.Enum, as: SchemaEnum
  alias KiwiCodec.Schema.{Message, Struct}
  alias RustQ.Rust

  @spec fragments([KiwiCodec.Schema.definition()], String.t(), map(), keyword()) :: [
          RustQ.Rust.Fragment.t()
        ]
  def fragments(definitions, module_prefix, definition_map, opts \\ []) do
    full? = Keyword.get(opts, :full?, false)
    Enum.map(definitions, &definition(&1, module_prefix, definition_map, full?))
  end

  defp definition(%Struct{name: name, fields: fields}, module_prefix, definition_map, _full?) do
    field_entries =
      fields
      |> Enum.map(&field_entry(&1, definition_map))
      |> Enum.intersperse("\n")

    DecoderMacro.sparse_struct_decoder(
      name,
      module_name(module_prefix, name),
      length(fields) + 1,
      field_entries
    )
  end

  defp definition(%SchemaEnum{name: name}, _module_prefix, _definition_map, true) do
    Rust.item([
      "fn decode_sparse_",
      RustExpr.ident(name),
      "_from_decoder<'a>(env: Env<'a>, decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {\n",
      "    ",
      RustExpr.ident(Name.decoder_function(name)),
      "(env, decoder)\n",
      "}"
    ])
  end

  defp definition(
         %SchemaEnum{name: name, variants: variants},
         _module_prefix,
         _definition_map,
         false
       ) do
    DecoderMacro.sparse_enum_decoder(name, variants)
  end

  defp definition(%Message{name: name, fields: fields}, module_prefix, definition_map, _full?) do
    field_entries =
      fields
      |> Enum.map(fn field ->
        [Integer.to_string(field.id), " => ", field_entry(field, definition_map)]
      end)
      |> Enum.intersperse("\n")

    DecoderMacro.sparse_message_decoder(
      name,
      module_name(module_prefix, name),
      length(fields) + 1,
      field_entries
    )
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
    inner = array_scalar_expr(%{field | array?: false}, definition_map)
    ["decoder.read_repeated(|decoder| ", inner, ")?.encode(env)"]
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

  defp array_scalar_expr(%{type: type}, definition_map) do
    cond do
      primitive = RustExpr.primitive(type) ->
        String.trim_trailing(primitive, "?")

      Map.has_key?(definition_map, type) ->
        ["decode_sparse_", RustExpr.ident(type), "_from_decoder(env, decoder)"]
    end
  end

  defp module_name(module_prefix, name), do: "Elixir.#{module_prefix}.#{name}"
end
