defmodule KiwiCodec.RustlerGenerator.Sparse do
  @moduledoc """
  Generates generic sparse Kiwi schema decoders for Rustler native backends.

  Sparse decoders return maps containing only fields present in the payload plus
  a `__kiwi_module__` key identifying the generated Elixir schema module.
  """

  alias KiwiCodec.RustlerGenerator.DecoderMacro
  alias KiwiCodec.RustlerGenerator.Name
  alias KiwiCodec.RustlerGenerator.RustExpr
  alias KiwiCodec.RustlerGenerator.Skip
  alias KiwiCodec.Schema.Enum, as: SchemaEnum
  alias KiwiCodec.Schema.{Message, Struct}
  alias RustQ.Rust

  @spec fragments([KiwiCodec.Schema.definition()], String.t(), map(), keyword()) :: [
          RustQ.Rust.Fragment.t()
        ]
  def fragments(definitions, module_prefix, definition_map, opts \\ []) do
    full? = Keyword.get(opts, :full?, false)
    struct_mode = Keyword.get(opts, :struct_mode, :match)
    message_mode = Keyword.get(opts, :message_mode, :match)

    Enum.map(
      definitions,
      &definition(&1, module_prefix, definition_map, full?, struct_mode, message_mode)
    )
  end

  defp definition(
         %Struct{name: name, fields: fields},
         module_prefix,
         definition_map,
         _full?,
         :match,
         _message_mode
       ) do
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

  defp definition(
         %Struct{name: name, fields: fields},
         module_prefix,
         definition_map,
         _full?,
         :descriptor,
         _message_mode
       ) do
    field_entries =
      fields
      |> Enum.map(&struct_descriptor_field_entry(&1, definition_map))
      |> Enum.intersperse("\n")

    DecoderMacro.sparse_struct_descriptor_decoder(
      name,
      module_name(module_prefix, name),
      length(fields) + 1,
      field_entries
    )
  end

  defp definition(
         %SchemaEnum{name: name},
         _module_prefix,
         _definition_map,
         true,
         _struct_mode,
         _message_mode
       ) do
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
         false,
         _struct_mode,
         _message_mode
       ) do
    DecoderMacro.sparse_enum_decoder(name, variants)
  end

  defp definition(
         %Message{name: name, fields: fields},
         module_prefix,
         definition_map,
         _full?,
         _struct_mode,
         :match
       ) do
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

  defp definition(
         %Message{name: name, fields: fields},
         module_prefix,
         definition_map,
         _full?,
         _struct_mode,
         :descriptor_with_skip
       ) do
    field_entries =
      fields
      |> Enum.sort_by(& &1.id)
      |> Enum.map(fn field ->
        [
          Integer.to_string(field.id),
          " => ",
          descriptor_field_entry(field, definition_map),
          " ",
          Skip.field_kind(field, definition_map),
          ";"
        ]
      end)
      |> Enum.intersperse("\n")

    ident = RustExpr.ident(name)

    Rust.item([
      "kiwi_sparse_skip_message_descriptor_decoder! {\n",
      "    sparse_fn decode_sparse_",
      ident,
      "_from_decoder;\n",
      "    skip_fn skip_",
      ident,
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

  defp definition(
         %Message{name: name, fields: fields},
         module_prefix,
         definition_map,
         _full?,
         _struct_mode,
         :descriptor
       ) do
    field_entries =
      fields
      |> Enum.sort_by(& &1.id)
      |> Enum.map(fn field ->
        [Integer.to_string(field.id), " => ", descriptor_field_entry(field, definition_map)]
      end)
      |> Enum.intersperse("\n")

    DecoderMacro.sparse_message_descriptor_decoder(
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

  defp descriptor_field_entry(field, definition_map) do
    [
      inspect(Macro.underscore(field.name)),
      ": ",
      descriptor_field_kind(field, definition_map),
      ";"
    ]
  end

  defp struct_descriptor_field_entry(field, definition_map) do
    [
      inspect(Macro.underscore(field.name)),
      " ",
      descriptor_field_kind(field, definition_map),
      ";"
    ]
  end

  defp descriptor_field_kind(%{array?: true, type: "byte"}, _definition_map),
    do: "one kiwi_sparse_bytes_value"

  defp descriptor_field_kind(%{array?: true} = field, definition_map) do
    ["repeated ", descriptor_scalar_function(%{field | array?: false}, definition_map)]
  end

  defp descriptor_field_kind(field, definition_map) do
    ["one ", descriptor_scalar_function(field, definition_map)]
  end

  defp descriptor_scalar_function(%{type: type}, definition_map) do
    cond do
      KiwiCodec.PrimitiveType.name?(type) ->
        ["kiwi_sparse_", RustExpr.ident(type), "_value"]

      Map.has_key?(definition_map, type) ->
        ["decode_sparse_", RustExpr.ident(type), "_from_decoder"]
    end
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
