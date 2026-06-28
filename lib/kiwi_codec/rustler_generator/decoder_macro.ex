defmodule KiwiCodec.RustlerGenerator.DecoderMacro do
  @moduledoc """
  Rusty-Elixir macro support for generated Rustler decoders.

  Entrypoint wrappers are authored with `defrust`. Full schema decoders use the
  same semantic boundary, but intentionally lower to compact Rust macro
  invocations instead of expanded Rust function bodies. This keeps generator
  authoring in Elixir/RustQ while preserving small generated source.
  """

  alias KiwiCodec.RustlerGenerator.Name
  alias KiwiCodec.RustlerGenerator.RustExpr
  alias KiwiCodec.Schema.Enum, as: SchemaEnum
  alias KiwiCodec.Schema.{Message, Struct}
  alias RustQ.Rust

  @spec enum_decoder(SchemaEnum.t()) :: RustQ.Rust.Fragment.t()
  def enum_decoder(%SchemaEnum{} = definition) do
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

  @spec struct_decoder(Struct.t(), String.t(), map(), (term(), map() -> iodata())) ::
          RustQ.Rust.Fragment.t()
  def struct_decoder(%Struct{} = definition, module_prefix, definition_map, field_expr_fun) do
    field_exprs = Enum.map(definition.fields, &field_expr_fun.(&1, definition_map))

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

  @spec message_decoder(Message.t(), String.t(), map(), (term(), map() -> iodata())) ::
          RustQ.Rust.Fragment.t()
  def message_decoder(%Message{} = definition, module_prefix, definition_map, field_expr_fun) do
    field_entries =
      definition.fields
      |> Enum.with_index()
      |> Enum.map(fn {field, index} ->
        [
          Integer.to_string(field.id),
          " => ",
          Integer.to_string(index + 1),
          ": ",
          field_expr_fun.(field, definition_map),
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

  @spec sparse_enum_decoder(String.t(), [term()]) :: RustQ.Rust.Fragment.t()
  def sparse_enum_decoder(name, variants) do
    variant_entries =
      variants
      |> Enum.map(fn field ->
        [Integer.to_string(field.value), " => ", inspect(Macro.underscore(field.name)), ";"]
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

  @spec sparse_struct_decoder(String.t(), String.t(), pos_integer(), iodata()) ::
          RustQ.Rust.Fragment.t()
  def sparse_struct_decoder(name, module_name, capacity, field_entries) do
    Rust.item([
      "kiwi_sparse_struct_decoder! {\n",
      "    fn decode_sparse_",
      RustExpr.ident(name),
      "_from_decoder;\n",
      "    env env;\n",
      "    decoder decoder;\n",
      "    module ",
      inspect(module_name),
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

  @spec sparse_message_decoder(String.t(), String.t(), pos_integer(), iodata()) ::
          RustQ.Rust.Fragment.t()
  def sparse_message_decoder(name, module_name, capacity, field_entries) do
    Rust.item([
      "kiwi_sparse_message_decoder! {\n",
      "    fn decode_sparse_",
      RustExpr.ident(name),
      "_from_decoder;\n",
      "    env env;\n",
      "    decoder decoder;\n",
      "    module ",
      inspect(module_name),
      ";\n",
      "    definition ",
      inspect(name),
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

  defmacro entrypoint(nif_name, decoder_name) do
    nif_name = expand_arg!(nif_name, __CALLER__)
    decoder_name = expand_arg!(decoder_name, __CALLER__)

    quote do
      @nif schedule: "DirtyCpu"
      @spec unquote(nif_name)(R.path(:Env, R.lifetime(:a)), R.path(:Binary, R.lifetime(:a))) ::
              R.nif_result(R.path(:Term, R.lifetime(:a)))
      defrust unquote(nif_name)(env, bytes) do
        decoder = Decoder.new(bytes.as_slice())

        case unquote(decoder_name)(env, mut_ref(decoder)) do
          {:ok, term} ->
            case decoder.finish() do
              {:ok, _done} -> {:ok, term}
              {:error, reason} -> {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  defp expand_arg!(quoted, caller) do
    {value, _binding} = Code.eval_quoted(quoted, [], caller)
    value
  end

  defp key_list(fields) do
    fields
    |> Enum.map(&(&1.name |> Name.field_name() |> inspect()))
    |> Enum.intersperse(", ")
  end
end
