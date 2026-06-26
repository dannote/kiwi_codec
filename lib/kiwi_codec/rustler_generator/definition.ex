defmodule KiwiCodec.RustlerGenerator.Definition do
  @moduledoc """
  Generates Rust items for Kiwi schema definitions.
  """

  alias KiwiCodec.RustlerGenerator.FieldExpr
  alias KiwiCodec.RustlerGenerator.Name
  alias KiwiCodec.Schema.Enum, as: SchemaEnum
  alias KiwiCodec.Schema.{Message, Struct}
  alias RustQ.Meta.AST, as: MetaAST
  alias RustQ.Rust
  alias RustQ.Rust.AST.Builder, as: A

  @spec fragments([KiwiCodec.Schema.definition()], String.t(), map()) :: [RustQ.Rust.Fragment.t()]
  def fragments(definitions, module_prefix, definition_map) do
    definitions
    |> Enum.flat_map(&items(&1, module_prefix, definition_map))
    |> Enum.map(&Rust.to_fragment/1)
  end

  defp items(%SchemaEnum{} = definition, _module_prefix, _definition_map) do
    variant_statics =
      definition.variants
      |> Enum.with_index()
      |> Enum.map(fn {_field, index} ->
        atom_static(Name.enum_variant_atom_static(definition.name, index))
      end)

    variant_statics ++ [enum_decoder_item(definition)]
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
      message_decoder_item(definition, module_prefix, definition_map),
      message_fields_decoder_item(definition, module_prefix, definition_map)
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
    definition
    |> generated_enum_module!()
    |> MetaAST.item(Name.decoder_function(definition.name))
  end

  defp generated_enum_module!(%SchemaEnum{} = definition) do
    module =
      Module.concat([
        KiwiCodec.RustlerGenerator.Generated,
        "Enum#{definition.name}#{:erlang.phash2(definition)}"
      ])

    if Code.ensure_loaded?(module) do
      module
    else
      variants =
        definition.variants
        |> Enum.with_index()
        |> Enum.map(fn {field, index} ->
          {
            field.value,
            Name.static_alias(Name.enum_variant_atom_static(definition.name, index)),
            Name.field_name(field.name)
          }
        end)

      name = Name.decoder_function(definition.name)

      Module.create(
        module,
        quote do
          use RustQ.Meta
          alias RustQ.Type, as: R
          import KiwiCodec.RustlerGenerator.DecoderMacro, only: [enum_decoder: 2]

          enum_decoder(
            unquote(name),
            unquote(Macro.escape(variants))
          )
        end,
        Macro.Env.location(__ENV__)
      )

      module
    end
  end

  defp struct_decoder_item(%Struct{} = definition, module_prefix, definition_map) do
    definition
    |> generated_struct_module!(module_prefix, definition_map)
    |> MetaAST.item(Name.decoder_function(definition.name))
  end

  defp generated_struct_module!(%Struct{} = definition, module_prefix, definition_map) do
    module =
      Module.concat([
        KiwiCodec.RustlerGenerator.Generated,
        "Struct#{definition.name}#{:erlang.phash2({definition, module_prefix})}"
      ])

    if Code.ensure_loaded?(module) do
      module
    else
      name = Name.decoder_function(definition.name)
      field_exprs = Enum.map(definition.fields, &FieldExpr.build(&1, definition_map))

      Module.create(
        module,
        quote do
          use RustQ.Meta
          alias RustQ.Type, as: R
          import KiwiCodec.RustlerGenerator.DecoderMacro, only: [struct_decoder: 6]

          struct_decoder(
            unquote(name),
            unquote(Name.module_atom_static(definition.name)),
            unquote(Name.struct_keys_static(definition.name)),
            unquote(Name.module_name(module_prefix, definition.name)),
            unquote(Enum.map(definition.fields, &Name.field_name(&1.name))),
            unquote(Macro.escape(field_exprs))
          )
        end,
        Macro.Env.location(__ENV__)
      )

      module
    end
  end

  defp message_decoder_item(%Message{} = definition, module_prefix, definition_map) do
    definition
    |> generated_message_module!(module_prefix, definition_map)
    |> MetaAST.item(Name.decoder_function(definition.name))
  end

  defp message_fields_decoder_item(%Message{} = definition, module_prefix, definition_map) do
    definition
    |> generated_message_module!(module_prefix, definition_map)
    |> MetaAST.item(Name.message_fields_function(definition.name))
  end

  defp generated_message_module!(%Message{} = definition, module_prefix, definition_map) do
    module =
      Module.concat([
        KiwiCodec.RustlerGenerator.Generated,
        "Message#{definition.name}#{:erlang.phash2({definition, module_prefix})}"
      ])

    if Code.ensure_loaded?(module) do
      module
    else
      decoder_name = Name.decoder_function(definition.name)
      fields_name = Name.message_fields_function(definition.name)

      fields =
        definition.fields
        |> Enum.with_index()
        |> Enum.map(fn {field, index} ->
          {field.id, index + 1, FieldExpr.build(field, definition_map)}
        end)

      module_name = Name.module_name(module_prefix, definition.name)

      Module.create(
        module,
        quote do
          use RustQ.Meta
          alias RustQ.Type, as: R

          import KiwiCodec.RustlerGenerator.DecoderMacro,
            only: [message_decoder: 6, message_fields_decoder: 2]

          message_decoder(
            unquote(decoder_name),
            unquote(fields_name),
            unquote(Name.module_atom_static(definition.name)),
            unquote(Name.struct_keys_static(definition.name)),
            unquote(module_name),
            unquote(Enum.map(definition.fields, &Name.field_name(&1.name)))
          )

          message_fields_decoder(unquote(fields_name), unquote(Macro.escape(fields)))
        end,
        Macro.Env.location(__ENV__)
      )

      module
    end
  end
end
