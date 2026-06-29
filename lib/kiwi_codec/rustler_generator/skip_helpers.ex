defmodule KiwiCodec.RustlerGenerator.SkipHelpers do
  @moduledoc """
  Builds RustQ-authored shared skip helper functions for generated Rustler decoders.

  These helpers are only used when the caller provides `:decoder_sources`, so
  RustQ can read the downstream `Decoder` implementation and infer fallible
  method propagation from real Rust metadata.
  """

  alias RustQ.Meta.AST, as: MetaAST

  @macros [
    :kiwi_skip_struct_decoder
  ]

  @functions [
    :kiwi_skip_bool_value,
    :kiwi_skip_byte_value,
    :kiwi_skip_float_value,
    :kiwi_skip_int_value,
    :kiwi_skip_int64_value,
    :kiwi_skip_string_value,
    :kiwi_skip_uint_value,
    :kiwi_skip_uint64_value,
    :kiwi_skip_bytes_value,
    :kiwi_skip_repeated,
    :kiwi_skip_struct_field,
    :kiwi_skip_struct_fields,
    :kiwi_skip_message_fields
  ]

  @spec fragments([Path.t()] | Path.t()) :: [RustQ.Rust.Fragment.t()]
  def fragments(decoder_sources) do
    module = generated_module!(decoder_sources)

    module.__rustq_type_items__() ++
      MetaAST.macro_items(module, @macros) ++
      MetaAST.items(module, @functions)
  end

  defp generated_module!(decoder_sources) do
    decoder_sources = List.wrap(decoder_sources)

    module =
      Module.concat([
        KiwiCodec.RustlerGenerator.Generated,
        "SkipHelpers#{:erlang.phash2(decoder_sources)}"
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

      unquote_splicing(type_definitions())
      unquote_splicing(macro_definitions())
      unquote_splicing(value_helper_definitions())
      unquote_splicing(struct_helper_definitions())
      unquote_splicing(message_helper_definitions())
    end
  end

  defp type_definitions do
    [
      quote do
        @type kiwi_skip_fn :: R.raw(:"fn(&mut Decoder<'_>) -> NifResult<()>")

        @type kiwi_skip_kind ::
                R.enum(one: [kiwi_skip_fn()], repeated: [kiwi_skip_fn()], bytes: [])

        @type kiwi_skip_field :: %{
                required(:id) => R.u32(),
                required(:kind) => kiwi_skip_kind()
              }

        @type kiwi_skip_struct_field :: %{
                required(:repeated) => R.bool(),
                required(:bytes) => R.bool(),
                required(:skip) => kiwi_skip_fn()
              }
      end
    ]
  end

  defp macro_definitions do
    [
      quote do
        defrustmacro kiwi_skip_struct_decoder(
                       fn: name(:ident),
                       decoder: decoder(:ident),
                       fields:
                         repeat do
                           field_repeated(:literal)
                           field_bytes(:literal)
                           field_skip(:ident)
                         end
                     ) do
          @spec name(R.mut_ref(R.path(:Decoder, R.lifetime(:_)))) :: R.nif_result(R.unit())
          defrust name(decoder) do
            kiwi_skip_struct_fields(
              decoder,
              ref(
                array([
                  repeat fields do
                    struct_literal(KiwiSkipStructField,
                      repeated: field_repeated,
                      bytes: field_bytes,
                      skip: field_skip
                    )
                  end
                ])
              ),
              0
            )
          end
        end
      end
    ]
  end

  defp value_helper_definitions do
    [
      quoted_skip_value(:kiwi_skip_bool_value, :read_bool),
      quoted_skip_value(:kiwi_skip_byte_value, :read_byte),
      quoted_skip_value(:kiwi_skip_float_value, :read_var_float_value),
      quoted_skip_value(:kiwi_skip_int_value, :read_var_int),
      quoted_skip_value(:kiwi_skip_int64_value, :read_var_int64),
      quoted_skip_value(:kiwi_skip_string_value, :skip_string),
      quoted_skip_value(:kiwi_skip_uint_value, :read_var_uint),
      quoted_skip_value(:kiwi_skip_uint64_value, :read_var_uint64),
      quoted_skip_value(:kiwi_skip_bytes_value, :skip_byte_array),
      quote do
        @spec kiwi_skip_repeated(
                R.mut_ref(R.path(:Decoder, R.lifetime(:_))),
                R.path(:KiwiSkipFn)
              ) :: R.nif_result(R.unit())
        defrust kiwi_skip_repeated(decoder, item) do
          decoder.read_repeated(fn decoder -> item(decoder) end)
          :ok
        end
      end
    ]
  end

  defp quoted_skip_value(function, read_method) do
    quote do
      @spec unquote(function)(R.mut_ref(R.path(:Decoder, R.lifetime(:_)))) ::
              R.nif_result(R.unit())
      defrust unquote(function)(decoder) do
        decoder.unquote(read_method)()
        :ok
      end
    end
  end

  defp struct_helper_definitions do
    [
      quote do
        @spec kiwi_skip_struct_field(
                R.mut_ref(R.path(:Decoder, R.lifetime(:_))),
                R.ref(R.path(:KiwiSkipStructField))
              ) :: R.nif_result(R.unit())
        defrust kiwi_skip_struct_field(decoder, field) do
          skip = field.skip

          if field.bytes do
            kiwi_skip_bytes_value(decoder)
          else
            if field.repeated do
              kiwi_skip_repeated(decoder, skip)
            else
              skip(decoder)
            end
          end
        end
      end,
      quote do
        @spec kiwi_skip_struct_fields(
                R.mut_ref(R.path(:Decoder, R.lifetime(:_))),
                R.slice(R.path(:KiwiSkipStructField)),
                R.usize()
              ) :: R.nif_result(R.unit())
        defrust kiwi_skip_struct_fields(decoder, fields, index) do
          if index == fields.len() do
            :ok
          else
            field = fields.get(index).unwrap()
            kiwi_skip_struct_field(decoder, field)
            kiwi_skip_struct_fields(decoder, fields, index + 1)
          end
        end
      end
    ]
  end

  defp message_helper_definitions do
    [
      quote do
        @spec kiwi_skip_message_fields(
                R.mut_ref(R.path(:Decoder, R.lifetime(:_))),
                R.str(),
                R.slice(R.path(:KiwiSkipField))
              ) :: R.nif_result(R.unit())
        defrust kiwi_skip_message_fields(decoder, _definition_name, fields) do
          field_id = unwrap!(decoder.read_var_uint())

          if field_id == 0 do
            :ok
          else
            case fields.binary_search_by_key(ref(field_id), fn field -> field.id end) do
              {:ok, index} ->
                field = fields.get(index).unwrap()
                unwrap!(kiwi_skip_kind(decoder, ref(field.kind)))
                kiwi_skip_message_fields(decoder, _definition_name, fields)

              {:error, _index} ->
                {:error, badarg()}
            end
          end
        end
      end
    ]
  end
end
