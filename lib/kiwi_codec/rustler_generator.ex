defmodule KiwiCodec.RustlerGenerator do
  @moduledoc """
  Generates Rustler decoder code from Kiwi schemas for RustQ manifests.

  This is an experimental bridge for optional native backends. It returns
  RustQ splice replacements for schema-dependent decoder functions and NIF
  entrypoints; `rustq.exs` owns rendering and writing generated files.
  """

  alias KiwiCodec.Schema
  alias KiwiCodec.Schema.Definition
  alias RustQ.Meta.AST, as: MetaAST
  alias RustQ.Rust
  alias RustQ.Rust.AST.Builder, as: A

  @primitive_decoders [
    {"bool", :read_bool, []},
    {"byte", :read_byte, []},
    {"float", :read_var_float, [:env]},
    {"int", :read_var_int, []},
    {"int64", :read_var_int64, []},
    {"string", :read_string, [:env]},
    {"uint", :read_var_uint, []},
    {"uint64", :read_var_uint64, []}
  ]

  for {type, method, args} <- @primitive_decoders do
    call =
      quote do
        decoder.unquote(method)(unquote_splicing(Enum.map(args, &Macro.var(&1, nil))))
      end

    defp primitive_decoder_expr(%{type: unquote(type)}) do
      unquote(Macro.escape(call))
    end
  end

  defp primitive_decoder_expr(_field), do: nil

  @type entrypoint :: {atom() | String.t(), String.t()}

  @doc """
  Returns RustQ splice replacements for a schema.

  Use this from `rustq.exs` with `render/2`:

      generate :native_decoders, "native/my_nif/src/generated.rs" do
        schema = KiwiCodec.parse_schema!(File.read!("priv/schema.kiwi"))

        render File.read!("native/my_nif/src/generated.template.rs"),
          filename: "native/my_nif/src/generated.template.rs",
          splice: KiwiCodec.RustlerGenerator.splices(schema,
            definitions: ["Node"],
            entrypoints: [decode_node: "Node"],
            module_prefix: "Example.Schema"
          )
      end

  """
  @spec splices(Schema.t(), keyword()) :: [{atom(), [RustQ.Rust.Fragment.t()]}]
  def splices(%Schema{} = schema, opts) do
    definitions = Keyword.get(opts, :definitions, [])
    entrypoints = Keyword.get(opts, :entrypoints, [])
    module_prefix = Keyword.fetch!(opts, :module_prefix)

    definition_map = Map.new(schema.definitions, &{&1.name, &1})
    selected = select_definitions(schema, definitions, definition_map)

    [
      {:definitions, definition_fragments(selected, module_prefix, definition_map)},
      {:entrypoints, entrypoint_fragments(entrypoints)}
    ] ++ Keyword.get(opts, :extra_splices, [])
  end

  defp select_definitions(%Schema{} = schema, [], _definition_map), do: schema.definitions

  defp select_definitions(%Schema{} = schema, names, definition_map) do
    names
    |> Enum.map(&to_string/1)
    |> include_dependencies(definition_map, MapSet.new())
    |> then(fn selected_names ->
      Enum.filter(schema.definitions, &MapSet.member?(selected_names, &1.name))
    end)
  end

  defp include_dependencies([], _definition_map, acc), do: acc

  defp include_dependencies([name | names], definition_map, acc) do
    if MapSet.member?(acc, name) do
      include_dependencies(names, definition_map, acc)
    else
      definition = Map.fetch!(definition_map, name)

      dependencies =
        definition.fields
        |> Enum.map(& &1.type)
        |> Enum.filter(&Map.has_key?(definition_map, &1))

      include_dependencies(names ++ dependencies, definition_map, MapSet.put(acc, name))
    end
  end

  defp definition_fragments(definitions, module_prefix, definition_map) do
    definitions
    |> Enum.flat_map(&definition_items(&1, module_prefix, definition_map))
    |> Enum.map(&fragment_code/1)
  end

  defp definition_items(%Definition{kind: :enum} = definition, _module_prefix, _definition_map) do
    variant_statics =
      definition.fields
      |> Enum.with_index()
      |> Enum.map(fn {_field, index} ->
        atom_static(enum_variant_atom_static(definition.name, index))
      end)

    variant_statics ++ [enum_decoder_item(definition)]
  end

  defp definition_items(%Definition{kind: :struct} = definition, module_prefix, definition_map) do
    [
      atom_static(module_atom_static(definition.name)),
      keys_static(struct_keys_static(definition.name)),
      struct_decoder_item(definition, module_prefix, definition_map)
    ]
  end

  defp definition_items(%Definition{kind: :message} = definition, module_prefix, definition_map) do
    [
      atom_static(module_atom_static(definition.name)),
      keys_static(struct_keys_static(definition.name)),
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

  defp enum_decoder_item(%Definition{} = definition) do
    definition
    |> generated_enum_module!()
    |> MetaAST.item(decoder_function_name(definition.name))
  end

  defp generated_enum_module!(%Definition{} = definition) do
    module =
      Module.concat([
        KiwiCodec.RustlerGenerator.Generated,
        "Enum#{definition.name}#{:erlang.phash2(definition)}"
      ])

    if Code.ensure_loaded?(module) do
      module
    else
      variants =
        definition.fields
        |> Enum.with_index()
        |> Enum.map(fn {field, index} ->
          {
            field.value,
            static_alias(enum_variant_atom_static(definition.name, index)),
            field_name(field.name)
          }
        end)

      name = decoder_function_name(definition.name)

      Module.create(
        module,
        quote do
          use RustQ.Meta
          alias RustQ.Type, as: R
          import KiwiCodec.RustlerGenerator.Rusty, only: [enum_decoder: 2]

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

  defp struct_decoder_item(%Definition{} = definition, module_prefix, definition_map) do
    definition
    |> generated_struct_module!(module_prefix, definition_map)
    |> MetaAST.item(decoder_function_name(definition.name))
  end

  defp generated_struct_module!(%Definition{} = definition, module_prefix, definition_map) do
    module =
      Module.concat([
        KiwiCodec.RustlerGenerator.Generated,
        "Struct#{definition.name}#{:erlang.phash2({definition, module_prefix})}"
      ])

    if Code.ensure_loaded?(module) do
      module
    else
      name = decoder_function_name(definition.name)
      field_exprs = Enum.map(definition.fields, &field_value_expr(&1, definition_map))

      Module.create(
        module,
        quote do
          use RustQ.Meta
          alias RustQ.Type, as: R
          import KiwiCodec.RustlerGenerator.Rusty, only: [struct_decoder: 6]

          struct_decoder(
            unquote(name),
            unquote(module_atom_static(definition.name)),
            unquote(struct_keys_static(definition.name)),
            unquote(module_name(module_prefix, definition.name)),
            unquote(Enum.map(definition.fields, &field_name(&1.name))),
            unquote(Macro.escape(field_exprs))
          )
        end,
        Macro.Env.location(__ENV__)
      )

      module
    end
  end

  defp message_decoder_item(%Definition{} = definition, module_prefix, definition_map) do
    definition
    |> generated_message_module!(module_prefix, definition_map)
    |> MetaAST.item(decoder_function_name(definition.name))
  end

  defp message_fields_decoder_item(%Definition{} = definition, module_prefix, definition_map) do
    definition
    |> generated_message_module!(module_prefix, definition_map)
    |> MetaAST.item(message_fields_function_name(definition.name))
  end

  defp generated_message_module!(%Definition{} = definition, module_prefix, definition_map) do
    module =
      Module.concat([
        KiwiCodec.RustlerGenerator.Generated,
        "Message#{definition.name}#{:erlang.phash2({definition, module_prefix})}"
      ])

    if Code.ensure_loaded?(module) do
      module
    else
      decoder_name = decoder_function_name(definition.name)
      fields_name = message_fields_function_name(definition.name)

      fields =
        definition.fields
        |> Enum.with_index()
        |> Enum.map(fn {field, index} ->
          {field.value, index + 1, field_value_expr(field, definition_map)}
        end)

      module_name = module_name(module_prefix, definition.name)

      Module.create(
        module,
        quote do
          use RustQ.Meta
          alias RustQ.Type, as: R

          import KiwiCodec.RustlerGenerator.Rusty,
            only: [message_decoder: 6, message_fields_decoder: 2]

          message_decoder(
            unquote(decoder_name),
            unquote(fields_name),
            unquote(module_atom_static(definition.name)),
            unquote(struct_keys_static(definition.name)),
            unquote(module_name),
            unquote(Enum.map(definition.fields, &field_name(&1.name)))
          )

          message_fields_decoder(unquote(fields_name), unquote(Macro.escape(fields)))
        end,
        Macro.Env.location(__ENV__)
      )

      module
    end
  end

  defp field_value_expr(%{array?: true, type: "byte"}, _definition_map) do
    quote(do: decoder.read_byte_array(env))
  end

  defp field_value_expr(%{array?: true} = field, definition_map) do
    inner = field_result_expr(%{field | array?: false}, definition_map)

    quote do
      decoder.read_repeated(fn decoder -> unquote(inner) end)
    end
  end

  defp field_value_expr(field, definition_map), do: field_result_expr(field, definition_map)

  defp field_result_expr(field, definition_map) do
    primitive_decoder_expr(field) ||
      field
      |> referenced_definition!(definition_map)
      |> then(fn definition ->
        name = decoder_function_name(definition.name)

        quote do
          unquote(name)(env, decoder)
        end
      end)
  end

  defp referenced_definition!(field, definition_map), do: Map.fetch!(definition_map, field.type)

  defp entrypoint_fragments(entrypoints) do
    Enum.map(entrypoints, fn {nif_name, definition_name} ->
      entrypoint_item(nif_name, definition_name)
    end)
  end

  defp entrypoint_item(nif_name, definition_name) do
    module = generated_entrypoint_module!(nif_name, definition_name)
    MetaAST.item(module, RustQ.Atom.identifier!(to_string(nif_name)))
  end

  defp generated_entrypoint_module!(nif_name, definition_name) do
    nif_name = RustQ.Atom.identifier!(to_string(nif_name))
    decoder_name = decoder_function_name(definition_name)

    module =
      Module.concat([
        KiwiCodec.RustlerGenerator.Generated,
        "Entrypoint#{nif_name}#{:erlang.phash2(definition_name)}"
      ])

    if Code.ensure_loaded?(module) do
      module
    else
      Module.create(
        module,
        quote do
          use RustQ.Meta
          alias RustQ.Type, as: R
          import KiwiCodec.RustlerGenerator.Rusty, only: [entrypoint: 2]

          entrypoint(unquote(nif_name), unquote(decoder_name))
        end,
        Macro.Env.location(__ENV__)
      )

      module
    end
  end

  defp fragment_code(fragment), do: RustQ.Rust.to_fragment(fragment)

  defp decoder_name(name), do: "decode_#{rust_ident(name)}"

  defp decoder_function_name(name),
    do: name |> decoder_name() |> Kernel.<>("_from_decoder") |> RustQ.Atom.identifier!()

  defp message_fields_function_name(name),
    do: name |> decoder_name() |> Kernel.<>("_fields_from_decoder") |> RustQ.Atom.identifier!()

  defp module_atom_static(name), do: static_name(name, "MODULE_ATOM")
  defp struct_keys_static(name), do: static_name(name, "STRUCT_KEYS")
  defp enum_variant_atom_static(name, index), do: static_name(name, "ATOM_#{index}")

  defp static_alias(name), do: {:__aliases__, [], [name]}

  defp static_name(name, suffix) do
    name
    |> rust_ident()
    |> String.upcase()
    |> Kernel.<>("_#{suffix}")
    |> RustQ.Atom.identifier!()
  end

  defp module_name(module_prefix, name) do
    "Elixir.#{module_prefix}.#{name}"
  end

  defp field_name(name), do: Macro.underscore(name)

  defp rust_ident(name) do
    name
    |> Macro.underscore()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
  end
end
