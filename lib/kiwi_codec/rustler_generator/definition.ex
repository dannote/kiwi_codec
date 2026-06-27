defmodule KiwiCodec.RustlerGenerator.Definition do
  @moduledoc """
  Generates Rust items for Kiwi schema definitions.
  """

  alias KiwiCodec.RustlerGenerator.Name
  alias KiwiCodec.RustlerGenerator.RustExpr
  alias KiwiCodec.Schema.Enum, as: SchemaEnum
  alias KiwiCodec.Schema.{Message, Struct}
  alias RustQ.Rust
  alias RustQ.Rust.AST.Builder, as: A

  @spec fragments([KiwiCodec.Schema.definition()], String.t(), map()) :: [RustQ.Rust.Fragment.t()]
  def fragments(definitions, module_prefix, definition_map) do
    definitions
    |> Enum.flat_map(&items(&1, module_prefix, definition_map))
    |> Enum.map(&Rust.to_fragment/1)
  end

  defp items(%SchemaEnum{} = definition, _module_prefix, _definition_map) do
    [enum_decoder_item(definition)]
  end

  defp items(%Struct{} = definition, module_prefix, definition_map) do
    [
      atom_static(Name.module_atom_static(definition.name)),
      keys_static(Name.struct_keys_static(definition.name)),
      struct_decoder_item(definition, module_prefix, definition_map)
    ]
  end

  defp items(%Message{} = definition, module_prefix, definition_map) do
    [
      atom_static(Name.module_atom_static(definition.name)),
      keys_static(Name.struct_keys_static(definition.name)),
      message_decoder_item(definition, module_prefix, definition_map)
    ]
  end

  defp atom_static(name) do
    Rust.ast_item(A.static(name, "OnceLock<Atom>", A.path_call([:OnceLock, :new])))
  end

  defp keys_static(name) do
    Rust.ast_item(
      A.static(name, "OnceLock<Vec<rustler::wrapper::NIF_TERM>>", A.path_call([:OnceLock, :new]))
    )
  end

  defp enum_decoder_item(%SchemaEnum{} = definition) do
    variants =
      definition.variants
      |> Enum.map(fn field ->
        [Integer.to_string(field.value), " => ", inspect(Name.field_name(field.name)), ";"]
      end)
      |> Enum.intersperse("\n")

    Rust.item([
      "kiwi_enum_decoder! {\n",
      "    fn ",
      RustExpr.ident(Name.decoder_function(definition.name)),
      ";\n",
      "    variants [\n",
      RustExpr.indent(variants, 8),
      "\n    ]\n",
      "}"
    ])
  end

  defp struct_decoder_item(%Struct{} = definition, module_prefix, definition_map) do
    field_exprs = Enum.map(definition.fields, &field_expr(&1, definition_map))

    Rust.item([
      "kiwi_struct_decoder! {\n",
      "    fn ",
      RustExpr.ident(Name.decoder_function(definition.name)),
      ";\n",
      "    env env;\n",
      "    decoder decoder;\n",
      "    module_static ",
      RustExpr.ident(Name.module_atom_static(definition.name)),
      ";\n",
      "    keys_static ",
      RustExpr.ident(Name.struct_keys_static(definition.name)),
      ";\n",
      "    module ",
      inspect(Name.module_name(module_prefix, definition.name)),
      ";\n",
      "    keys [",
      key_list(definition.fields),
      "];\n",
      "    fields [\n",
      RustExpr.indent(Enum.intersperse(field_exprs, ",\n"), 8),
      "\n    ]\n",
      "}"
    ])
  end

  defp message_decoder_item(%Message{} = definition, module_prefix, definition_map) do
    field_entries =
      definition.fields
      |> Enum.with_index()
      |> Enum.map(fn {field, index} ->
        [
          Integer.to_string(field.id),
          " => ",
          Integer.to_string(index + 1),
          ": ",
          field_expr(field, definition_map),
          ";"
        ]
      end)
      |> Enum.intersperse("\n")

    Rust.item([
      "kiwi_message_decoder! {\n",
      "    fn ",
      RustExpr.ident(Name.decoder_function(definition.name)),
      ";\n",
      "    fields_fn ",
      RustExpr.ident(Name.message_fields_function(definition.name)),
      ";\n",
      "    env env;\n",
      "    decoder decoder;\n",
      "    module_static ",
      RustExpr.ident(Name.module_atom_static(definition.name)),
      ";\n",
      "    keys_static ",
      RustExpr.ident(Name.struct_keys_static(definition.name)),
      ";\n",
      "    module ",
      inspect(Name.module_name(module_prefix, definition.name)),
      ";\n",
      "    keys [",
      key_list(definition.fields),
      "];\n",
      "    fields [\n",
      RustExpr.indent(field_entries, 8),
      "\n    ]\n",
      "}"
    ])
  end

  defp field_expr(%{array?: true, type: "byte"}, _definition_map) do
    "decoder.read_byte_array(env)?"
  end

  defp field_expr(%{array?: true} = field, definition_map) do
    inner = array_field_expr(%{field | array?: false}, definition_map)
    ["decoder.read_repeated(|decoder| ", inner, ")?"]
  end

  defp field_expr(%{type: type}, definition_map) do
    case RustExpr.primitive(type) do
      nil ->
        [
          RustExpr.ident(Name.decoder_function(Map.fetch!(definition_map, type).name)),
          "(env, decoder)?"
        ]

      expr ->
        expr
    end
  end

  defp array_field_expr(%{type: type}, definition_map) do
    case RustExpr.primitive(type) do
      nil ->
        [
          RustExpr.ident(Name.decoder_function(Map.fetch!(definition_map, type).name)),
          "(env, decoder)"
        ]

      expr ->
        String.trim_trailing(expr, "?")
    end
  end

  defp key_list(fields) do
    fields
    |> Enum.map(&(&1.name |> Name.field_name() |> inspect()))
    |> Enum.intersperse(", ")
  end
end
