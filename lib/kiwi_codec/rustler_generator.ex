defmodule KiwiCodec.RustlerGenerator.Rusty do
  @moduledoc false

  defmacro struct_decoder(name, module_static, keys_static, module_name, key_names, field_exprs) do
    {name, _binding} = Code.eval_quoted(name, [], __CALLER__)
    {module_static, _binding} = Code.eval_quoted(module_static, [], __CALLER__)
    {keys_static, _binding} = Code.eval_quoted(keys_static, [], __CALLER__)
    module_static = static_path(module_static)
    keys_static = static_path(keys_static)
    {module_name, _binding} = Code.eval_quoted(module_name, [], __CALLER__)
    {key_names, _binding} = Code.eval_quoted(key_names, [], __CALLER__)
    {field_exprs, _binding} = Code.eval_quoted(field_exprs, [], __CALLER__)

    fields = push_fields(field_exprs, quote(do: make_struct(env, keys, ref(values))))

    quote do
      @spec unquote(name)(
              R.path(:Env, R.lifetime(:a)),
              R.mut_ref(R.path(:Decoder, R.lifetime(:_)))
            ) ::
              R.nif_result(R.path(:Term, R.lifetime(:a)))
      defrust unquote(name)(env, decoder) do
        module_atom = cached_atom(env, ref(unquote(module_static)), unquote(module_name))
        keys = cached_struct_keys(env, ref(unquote(keys_static)), ref(unquote(key_names)))
        values = Vec.with_capacity(keys.len())
        values.push(module_atom.as_c_arg())
        unquote(fields)
      end
    end
  end

  defmacro entrypoint(nif_name, decoder_name) do
    {nif_name, _binding} = Code.eval_quoted(nif_name, [], __CALLER__)
    {decoder_name, _binding} = Code.eval_quoted(decoder_name, [], __CALLER__)

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

  defp static_path(name), do: {:__aliases__, [], [name]}

  defp push_fields([], done), do: done

  defp push_fields([expr | rest], done) do
    next = push_fields(rest, done)

    quote do
      case unquote(expr) do
        {:ok, value} ->
          values.push(value.encode(env).as_c_arg())
          unquote(next)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defmacro enum_decoder(name, variants) do
    {name, _binding} = Code.eval_quoted(name, [], __CALLER__)
    {variants, _binding} = Code.eval_quoted(variants, [], __CALLER__)

    clauses =
      variants
      |> Enum.flat_map(fn {value, static_name, atom_name} ->
        quote do
          unquote(value) ->
            {:ok, cached_atom(env, ref(unquote(static_name)), unquote(atom_name)).encode(env)}
        end
      end)
      |> Kernel.++(
        quote do
          value -> {:ok, value.encode(env)}
        end
      )

    quote do
      @spec unquote(name)(
              R.path(:Env, R.lifetime(:a)),
              R.mut_ref(R.path(:Decoder, R.lifetime(:_)))
            ) ::
              R.nif_result(R.path(:Term, R.lifetime(:a)))
      defrust unquote(name)(env, decoder) do
        case decoder.read_var_uint() do
          {:ok, raw} ->
            case cast(raw, :i64) do
              (unquote_splicing(clauses))
            end

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end
end

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

    defp primitive_decoder_source(%{type: unquote(type)}) do
      unquote("decoder.#{method}(#{Enum.map_join(args, ", ", &to_string/1)})")
    end
  end

  defp primitive_decoder_expr(_field), do: nil
  defp primitive_decoder_source(_field), do: nil

  @type entrypoint :: {atom() | String.t(), String.t()}

  @doc """
  Returns RustQ splice replacements for a schema.

  Use this from `rustq.exs` with `render/2`:

      generate :native_decoders, "native/my_nif/src/generated.rs" do
        schema = KiwiCodec.parse_schema!(File.read!("priv/schema.kiwi"))

        render "native/my_nif/src/generated.template.rs",
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

  defp definition_items(%Definition{} = definition, module_prefix, definition_map) do
    definition
    |> definition_code(module_prefix, definition_map)
    |> rust_item_fragment()
    |> List.wrap()
  end

  defp definition_code(%Definition{kind: :message} = definition, module_prefix, definition_map) do
    fields =
      definition.fields |> Enum.with_index() |> Enum.map(&message_field_arm(&1, definition_map))

    """
    fn #{decoder_name(definition.name)}_from_decoder<'a>(env: Env<'a>, decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {
        static MODULE_ATOM: OnceLock<Atom> = OnceLock::new();
        static STRUCT_KEYS: OnceLock<Vec<rustler::wrapper::NIF_TERM>> = OnceLock::new();
        let module_atom = cached_atom(env, &MODULE_ATOM, #{rust_string(module_name(module_prefix, definition.name))});
        let keys = cached_struct_keys(env, &STRUCT_KEYS, &[#{field_names(definition.fields)}]);
        let mut values = default_values(module_atom, keys.len() - 1);
        loop {
            match decoder.read_var_uint()? {
                0 => break,
    #{indent(fields, 12)}
                field => return Err(Error::Term(Box::new(format!("unknown field {} while decoding #{definition.name}", field)))),
            }
        }
        make_struct(env, keys, &values)
    }
    """
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
    module = Module.concat([KiwiCodec.RustlerGenerator.Generated, "Enum#{definition.name}"])

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

  defp message_field_arm({field, index}, definition_map) do
    value = field_value_source(field, definition_map)

    """
    #{field.value} => {
        let value = #{value};
        values[#{index + 1}] = value.encode(env).as_c_arg();
    }
    """
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

  defp field_value_source(%{array?: true, type: "byte"}, _definition_map) do
    "decoder.read_byte_array(env)?"
  end

  defp field_value_source(%{array?: true} = field, definition_map) do
    "decoder.read_repeated(|decoder| #{field_result_source(%{field | array?: false}, definition_map)})?"
  end

  defp field_value_source(field, definition_map),
    do: "#{field_result_source(field, definition_map)}?"

  defp field_result_source(field, definition_map) do
    primitive_decoder_source(field) ||
      field
      |> referenced_definition!(definition_map)
      |> then(&"#{decoder_name(&1.name)}_from_decoder(env, decoder)")
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

  defp rust_item_fragment(code) do
    RustQ.parse_fragment!(:item, code)
  end

  defp fragment_code(fragment), do: RustQ.Rust.to_fragment(fragment)

  defp decoder_name(name), do: "decode_#{rust_ident(name)}"

  defp decoder_function_name(name),
    do: name |> decoder_name() |> Kernel.<>("_from_decoder") |> RustQ.Atom.identifier!()

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

  defp field_names(fields) do
    Enum.map_join(fields, ", ", fn field -> field.name |> field_name() |> rust_string() end)
  end

  defp rust_ident(name) do
    name
    |> Macro.underscore()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
  end

  defp rust_string(value) do
    escaped =
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")

    "\"#{escaped}\""
  end

  defp indent(lines, spaces) when is_list(lines) do
    lines |> Enum.join("\n") |> indent(spaces)
  end

  defp indent(text, spaces) do
    padding = String.duplicate(" ", spaces)

    text
    |> String.trim_trailing()
    |> String.split("\n")
    |> Enum.map_join("\n", &(padding <> &1))
  end
end
