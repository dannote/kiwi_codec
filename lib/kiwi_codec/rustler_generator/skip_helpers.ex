defmodule KiwiCodec.RustlerGenerator.SkipHelpers do
  @moduledoc """
  Builds RustQ-authored shared skip helper functions for generated Rustler decoders.

  These helpers are only used when the caller provides `:decoder_sources`, so
  RustQ can read the downstream `Decoder` implementation and infer fallible
  method propagation from real Rust metadata.
  """

  alias RustQ.Meta.AST, as: MetaAST

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
    :kiwi_skip_message_fields
  ]

  @spec fragments([Path.t()] | Path.t()) :: [RustQ.Rust.Fragment.t()]
  def fragments(decoder_sources) do
    decoder_sources
    |> generated_module!()
    |> MetaAST.items(@functions)
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

      @spec kiwi_skip_bool_value(R.mut_ref(R.path(:Decoder, R.lifetime(:_)))) ::
              R.nif_result(R.unit())
      defrust kiwi_skip_bool_value(decoder) do
        decoder.read_bool()
        :ok
      end

      @spec kiwi_skip_byte_value(R.mut_ref(R.path(:Decoder, R.lifetime(:_)))) ::
              R.nif_result(R.unit())
      defrust kiwi_skip_byte_value(decoder) do
        decoder.read_byte()
        :ok
      end

      @spec kiwi_skip_float_value(R.mut_ref(R.path(:Decoder, R.lifetime(:_)))) ::
              R.nif_result(R.unit())
      defrust kiwi_skip_float_value(decoder) do
        decoder.read_var_float_value()
        :ok
      end

      @spec kiwi_skip_int_value(R.mut_ref(R.path(:Decoder, R.lifetime(:_)))) ::
              R.nif_result(R.unit())
      defrust kiwi_skip_int_value(decoder) do
        decoder.read_var_int()
        :ok
      end

      @spec kiwi_skip_int64_value(R.mut_ref(R.path(:Decoder, R.lifetime(:_)))) ::
              R.nif_result(R.unit())
      defrust kiwi_skip_int64_value(decoder) do
        decoder.read_var_int64()
        :ok
      end

      @spec kiwi_skip_string_value(R.mut_ref(R.path(:Decoder, R.lifetime(:_)))) ::
              R.nif_result(R.unit())
      defrust kiwi_skip_string_value(decoder) do
        decoder.skip_string()
        :ok
      end

      @spec kiwi_skip_uint_value(R.mut_ref(R.path(:Decoder, R.lifetime(:_)))) ::
              R.nif_result(R.unit())
      defrust kiwi_skip_uint_value(decoder) do
        decoder.read_var_uint()
        :ok
      end

      @spec kiwi_skip_uint64_value(R.mut_ref(R.path(:Decoder, R.lifetime(:_)))) ::
              R.nif_result(R.unit())
      defrust kiwi_skip_uint64_value(decoder) do
        decoder.read_var_uint64()
        :ok
      end

      @spec kiwi_skip_bytes_value(R.mut_ref(R.path(:Decoder, R.lifetime(:_)))) ::
              R.nif_result(R.unit())
      defrust kiwi_skip_bytes_value(decoder) do
        decoder.skip_byte_array()
        :ok
      end

      @spec kiwi_skip_repeated(R.mut_ref(R.path(:Decoder, R.lifetime(:_))), R.path(:KiwiSkipFn)) ::
              R.nif_result(R.unit())
      defrust kiwi_skip_repeated(decoder, item) do
        decoder.read_repeated(fn decoder -> item(decoder) end)
        :ok
      end

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
  end
end
