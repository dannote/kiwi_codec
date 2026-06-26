defmodule KiwiCodec.RustlerGenerator.Rusty do
  @moduledoc """
  Rusty-Elixir macro helpers used by `KiwiCodec.RustlerGenerator`.

  These macros are package-internal metaprogramming helpers: they emit `defrust`
  decoder functions while keeping control flow in Rusty-Elixir instead of raw
  Rust source strings.
  """

  defmacro struct_decoder(name, module_static, keys_static, module_name, key_names, field_exprs) do
    name = expand_arg!(name, __CALLER__)
    module_static = module_static |> expand_arg!(__CALLER__) |> static_path()
    keys_static = keys_static |> expand_arg!(__CALLER__) |> static_path()
    module_name = expand_arg!(module_name, __CALLER__)
    key_names = expand_arg!(key_names, __CALLER__)
    field_exprs = expand_arg!(field_exprs, __CALLER__)

    fields =
      push_fields(
        field_exprs,
        quote(do: make_struct_from_nif_term_arrays(env, keys, ref(values)))
      )

    quote do
      @spec unquote(name)(
              R.path(:Env, R.lifetime(:a)),
              R.mut_ref(R.path(:Decoder, R.lifetime(:_)))
            ) ::
              R.nif_result(R.path(:Term, R.lifetime(:a)))
      defrust unquote(name)(env, decoder) do
        module_atom = cached_atom(env, ref(unquote(module_static)), unquote(module_name))
        keys = cached_struct_keys(env, ref(unquote(keys_static)), ref(array(unquote(key_names))))
        values = Vec.with_capacity(keys.len())
        values.push(module_atom.as_c_arg())
        unquote(fields)
      end
    end
  end

  defmacro message_decoder(name, fields_name, module_static, keys_static, module_name, key_names) do
    name = expand_arg!(name, __CALLER__)
    fields_name = expand_arg!(fields_name, __CALLER__)
    module_static = module_static |> expand_arg!(__CALLER__) |> static_path()
    keys_static = keys_static |> expand_arg!(__CALLER__) |> static_path()
    module_name = expand_arg!(module_name, __CALLER__)
    key_names = expand_arg!(key_names, __CALLER__)

    quote do
      @spec unquote(name)(
              R.path(:Env, R.lifetime(:a)),
              R.mut_ref(R.path(:Decoder, R.lifetime(:_)))
            ) ::
              R.nif_result(R.path(:Term, R.lifetime(:a)))
      defrust unquote(name)(env, decoder) do
        module_atom = cached_atom(env, ref(unquote(module_static)), unquote(module_name))
        keys = cached_struct_keys(env, ref(unquote(keys_static)), ref(array(unquote(key_names))))
        values = default_struct_values(env, module_atom, keys.len() - 1)
        unquote(fields_name)(env, decoder, keys, values)
      end
    end
  end

  defmacro message_fields_decoder(name, fields) do
    name = expand_arg!(name, __CALLER__)
    fields = expand_arg!(fields, __CALLER__)

    finish_clause =
      quote do
        0 -> make_struct_from_nif_term_arrays(env, keys, ref(values))
      end

    clauses =
      finish_clause ++
        Enum.flat_map(fields, fn {field_value, index, expr} ->
          quote do
            unquote(field_value) ->
              case unquote(expr) do
                {:ok, value} ->
                  assign!(index(values, unquote(index)), value.encode(env).as_c_arg())
                  unquote(name)(env, decoder, keys, values)

                {:error, reason} ->
                  {:error, reason}
              end
          end
        end) ++
        quote do
          _unknown -> {:error, badarg()}
        end

    quote do
      @spec unquote(name)(
              R.path(:Env, R.lifetime(:a)),
              R.mut_ref(R.path(:Decoder, R.lifetime(:_))),
              R.slice(R.path({:rustler, :wrapper, :NIF_TERM})),
              R.vec(R.path({:rustler, :wrapper, :NIF_TERM}))
            ) ::
              R.nif_result(R.path(:Term, R.lifetime(:a)))
      defrust unquote(name)(env, decoder, keys, values) do
        values = values

        case decoder.read_var_uint() do
          {:ok, field} ->
            case cast(field, :i64) do
              (unquote_splicing(clauses))
            end

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
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

  defmacro enum_decoder(name, variants) do
    name = expand_arg!(name, __CALLER__)
    variants = expand_arg!(variants, __CALLER__)

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

  defp expand_arg!(quoted, caller) do
    {value, _binding} = Code.eval_quoted(quoted, [], caller)
    value
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
end
