defmodule KiwiCodec.Decoder do
  @moduledoc """
  Decodes Kiwi wire binaries into generated Kiwi structs.

  This module is used by `KiwiCodec.decode/2`; callers normally interact with
  the public API or generated module `decode/1` functions.
  """

  alias KiwiCodec.Metadata
  alias KiwiCodec.Metadata.Field
  alias KiwiCodec.Wire
  alias KiwiCodec.Wire.Varint

  @spec decode(binary(), module()) :: struct()
  def decode(binary, module) when is_binary(binary) and is_atom(module) do
    {value, rest} = decode_from_module(binary, module)

    if rest == "" do
      value
    else
      raise KiwiCodec.DecodeError, message: "unexpected trailing bytes"
    end
  end

  defp decode_from_module(binary, module) do
    {value, rest} =
      case module.__kiwi_props__() do
        %Metadata{kind: :message} = metadata -> decode_message(binary, struct(module), metadata)
        %Metadata{kind: :struct} = metadata -> decode_struct(binary, struct(module), metadata)
      end

    {transform(value, module), rest}
  end

  defp decode_message(binary, struct, %Metadata{fields_by_id: fields_by_id} = metadata) do
    {field_id, rest} = Varint.decode_uint(binary)

    case field_id do
      0 ->
        {struct, rest}

      id ->
        field = Map.get(fields_by_id, id) || raise_unknown_field(struct, id)
        {value, tail} = decode_field_value(rest, field, struct.__struct__)
        decode_message(tail, Map.put(struct, field.name, value), metadata)
    end
  end

  defp decode_struct(binary, struct, %Metadata{ordered_fields: fields}) do
    decode_struct_fields(fields, struct, binary, struct.__struct__)
  end

  defp decode_struct_fields([], struct, binary, _module), do: {struct, binary}

  defp decode_struct_fields([field | fields], struct, binary, module) do
    {value, rest} = decode_field_value(binary, field, module)
    decode_struct_fields(fields, Map.put(struct, field.name, value), rest, module)
  end

  defp decode_field_value(binary, %Field{} = field, module) do
    do_decode_field_value(binary, field)
  rescue
    error in [KiwiCodec.DecodeError, ArgumentError, FunctionClauseError, MatchError] ->
      raise_decode_field_error(module, field, error)
  end

  defp do_decode_field_value(binary, %Field{repeated?: true, type: :byte}) do
    Wire.decode_byte_array(binary)
  end

  defp do_decode_field_value(binary, %Field{repeated?: true} = field) do
    {length, rest} = Varint.decode_uint(binary)
    decode_repeated(length, field.type, rest, [])
  end

  defp do_decode_field_value(binary, %Field{} = field) do
    decode_scalar(field.type, binary)
  end

  defp decode_repeated(0, _type, binary, acc), do: {Enum.reverse(acc), binary}

  defp decode_repeated(count, type, binary, acc) do
    {value, rest} = decode_scalar(type, binary)
    decode_repeated(count - 1, type, rest, [value | acc])
  end

  defp decode_scalar({:enum, module}, binary) do
    {value, rest} = Varint.decode_uint(binary)
    {module.key(value), rest}
  end

  defp decode_scalar(type, binary)
       when type in [:bool, :byte, :float, :int, :int64, :string, :uint, :uint64],
       do: Wire.decode(type, binary)

  defp decode_scalar(module, binary) when is_atom(module), do: decode_from_module(binary, module)

  defp transform(message, module) do
    case module.transform_module() do
      nil -> message
      transform_module -> transform_module.decode(message, module)
    end
  end

  defp raise_unknown_field(struct, id) do
    raise KiwiCodec.DecodeError,
      message: "unknown field #{id} while decoding #{inspect(struct.__struct__)}"
  end

  defp raise_decode_field_error(module, field, error) do
    raise KiwiCodec.DecodeError,
      message: "error decoding #{inspect(module)}##{field.name}: #{Exception.message(error)}"
  end
end
