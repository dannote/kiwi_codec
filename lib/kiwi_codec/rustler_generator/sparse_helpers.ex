defmodule KiwiCodec.RustlerGenerator.SparseHelpers do
  @moduledoc """
  Builds RustQ-authored shared sparse helper functions for generated Rustler decoders.

  These helpers are used when callers provide `:decoder_sources`, allowing
  RustQ to read the downstream `Decoder` implementation and infer fallible
  method propagation from real Rust metadata.
  """

  alias RustQ.Meta.AST, as: MetaAST

  @macros [
    :kiwi_sparse_message_descriptor_decoder
  ]

  @functions [
    :kiwi_sparse_bool_value,
    :kiwi_sparse_byte_value,
    :kiwi_sparse_float_value,
    :kiwi_sparse_int_value,
    :kiwi_sparse_int64_value,
    :kiwi_sparse_string_value,
    :kiwi_sparse_uint_value,
    :kiwi_sparse_uint64_value,
    :kiwi_sparse_bytes_value,
    :kiwi_sparse_field_value,
    :kiwi_sparse_message_fields,
    :kiwi_sparse_message_fields_remaining
  ]

  @spec fragments([Path.t()] | Path.t()) :: [RustQ.Rust.Fragment.t()]
  def fragments(decoder_sources) do
    module = generated_module!(decoder_sources)

    module.__rustq_type_items__() ++
      MetaAST.macro_items(module, @macros) ++ MetaAST.items(module, @functions)
  end

  defp generated_module!(decoder_sources) do
    decoder_sources = List.wrap(decoder_sources)

    module =
      Module.concat([
        KiwiCodec.RustlerGenerator.Generated,
        "SparseHelpers#{:erlang.phash2(decoder_sources)}"
      ])

    if Code.ensure_loaded?(module) do
      module
    else
      Module.create(module, quoted_module(decoder_sources), Macro.Env.location(__ENV__))
      module
    end
  end

  defp quoted_module(decoder_sources) do
    quote do
      use RustQ.Meta, rust_sources: unquote(decoder_sources)

      alias RustQ.Type, as: R

      @type kiwi_sparse_decode_fn ::
              R.raw(:"for<'a> fn(Env<'a>, &mut Decoder<'_>) -> NifResult<Term<'a>>")

      @type kiwi_sparse_field :: %{
              required(:id) => R.u32(),
              required(:name) => R.raw(:"&'static str"),
              required(:repeated) => R.bool(),
              required(:decode) => R.path(:KiwiSparseDecodeFn)
            }

      unquote_splicing(macro_definitions())
      unquote_splicing(value_helper_definitions())
      unquote_splicing(message_helper_definitions())
    end
  end

  defp macro_definitions do
    [
      quote do
        defrustmacro kiwi_sparse_message_descriptor_decoder(
                       fn: name(:ident),
                       env: env(:ident),
                       decoder: decoder(:ident),
                       module: module_name(:literal),
                       definition: definition_name(:literal),
                       capacity: capacity(:literal),
                       fields:
                         repeat do
                           field_id(:literal)
                           field_name(:literal)
                           field_mode(:ident)
                           field_decode(:ident)
                         end
                     ) do
          @spec name(
                  R.path(:Env, R.lifetime(:a)),
                  R.mut_ref(R.path(:Decoder, R.lifetime(:_)))
                ) :: R.nif_result(term())
          defrust name(env, decoder) do
            kiwi_sparse_message_fields(
              env,
              decoder,
              module_name,
              definition_name,
              capacity,
              ref(
                array([
                  repeat fields do
                    struct_literal(KiwiSparseField,
                      id: field_id,
                      name: field_name,
                      repeated: kiwi_sparse_repeated!(field_mode),
                      decode: field_decode
                    )
                  end
                ])
              )
            )
          end
        end
      end
    ]
  end

  defp value_helper_definitions do
    [
      quoted_encoded_value(:kiwi_sparse_bool_value, :read_bool),
      quoted_encoded_value(:kiwi_sparse_byte_value, :read_byte),
      quoted_passthrough_value(:kiwi_sparse_float_value, :read_var_float),
      quoted_encoded_value(:kiwi_sparse_int_value, :read_var_int),
      quoted_encoded_value(:kiwi_sparse_int64_value, :read_var_int64),
      quoted_passthrough_value(:kiwi_sparse_string_value, :read_string),
      quoted_encoded_value(:kiwi_sparse_uint_value, :read_var_uint),
      quoted_encoded_value(:kiwi_sparse_uint64_value, :read_var_uint64),
      quoted_passthrough_value(:kiwi_sparse_bytes_value, :read_byte_array)
    ]
  end

  defp quoted_encoded_value(function, read_method) do
    quote do
      @spec unquote(function)(
              R.path(:Env, R.lifetime(:a)),
              R.mut_ref(R.path(:Decoder, R.lifetime(:_)))
            ) :: R.nif_result(term())
      defrust unquote(function)(env, decoder) do
        value = unwrap!(decoder.unquote(read_method)())
        {:ok, value.encode(env)}
      end
    end
  end

  defp quoted_passthrough_value(function, read_method) do
    quote do
      @spec unquote(function)(
              R.path(:Env, R.lifetime(:a)),
              R.mut_ref(R.path(:Decoder, R.lifetime(:_)))
            ) :: R.nif_result(term())
      defrust unquote(function)(env, decoder) do
        decoder.unquote(read_method)(env)
      end
    end
  end

  defp message_helper_definitions do
    [
      quote_field_value(),
      quote_message_fields(),
      quote_message_fields_remaining()
    ]
  end

  defp quote_field_value do
    quote do
      @spec kiwi_sparse_field_value(
              R.path(:Env, R.lifetime(:a)),
              R.mut_ref(R.path(:Decoder, R.lifetime(:_))),
              R.ref(R.path(:KiwiSparseField))
            ) :: R.nif_result(term())
      defrust kiwi_sparse_field_value(env, decoder, field) do
        decode = field.decode

        if field.repeated do
          values = unwrap!(decoder.read_repeated(fn decoder -> decode(env, decoder) end))
          {:ok, values.encode(env)}
        else
          decode(env, decoder)
        end
      end
    end
  end

  defp quote_message_fields do
    quote do
      @spec kiwi_sparse_message_fields(
              R.path(:Env, R.lifetime(:a)),
              R.mut_ref(R.path(:Decoder, R.lifetime(:_))),
              R.str(),
              R.str(),
              R.usize(),
              R.slice(R.path(:KiwiSparseField))
            ) :: R.nif_result(term())
      defrust kiwi_sparse_message_fields(
                env,
                decoder,
                module_name,
                _definition_name,
                capacity,
                fields
              ) do
        module_atom = Atom.from_str(env, module_name).unwrap()
        module_key_atom = Atom.from_str(env, "__kiwi_module__").unwrap()
        keys = Vec.with_capacity(capacity)
        values = Vec.with_capacity(capacity)
        keys.push(module_key_atom.encode(env))
        values.push(module_atom.encode(env))

        kiwi_sparse_message_fields_remaining(
          env,
          decoder,
          fields,
          mut_ref(keys),
          mut_ref(values)
        )

        Term.map_from_term_arrays(env, ref(keys), ref(values))
      end
    end
  end

  defp quote_message_fields_remaining do
    quote do
      @spec kiwi_sparse_message_fields_remaining(
              R.path(:Env, R.lifetime(:a)),
              R.mut_ref(R.path(:Decoder, R.lifetime(:_))),
              R.slice(R.path(:KiwiSparseField)),
              R.mut_ref(R.vec(term())),
              R.mut_ref(R.vec(term()))
            ) :: R.nif_result(R.unit())
      defrust kiwi_sparse_message_fields_remaining(env, decoder, fields, keys, values) do
        field_id = unwrap!(decoder.read_var_uint())

        if field_id == 0 do
          :ok
        else
          case fields.binary_search_by_key(ref(field_id), fn field -> field.id end) do
            {:ok, index} ->
              field = fields.get(index).unwrap()
              keys.push(Atom.from_str(env, field.name).unwrap().encode(env))
              values.push(unwrap!(kiwi_sparse_field_value(env, decoder, field)))

              kiwi_sparse_message_fields_remaining(env, decoder, fields, keys, values)

            {:error, _index} ->
              {:error, badarg()}
          end
        end
      end
    end
  end
end
