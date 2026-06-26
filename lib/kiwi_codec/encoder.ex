defmodule KiwiCodec.Encoder do
  @moduledoc """
  Encodes generated Kiwi structs into Kiwi wire iodata.

  This module is used by `KiwiCodec.encode/1`; callers normally interact with
  the public API or generated module `encode/1` functions.
  """

  alias KiwiCodec.Metadata
  alias KiwiCodec.Metadata.Field
  alias KiwiCodec.Wire
  alias KiwiCodec.Wire.Varint

  @spec encode_to_iodata(struct(), module()) :: iodata()
  def encode_to_iodata(%module{} = struct, module) do
    struct
    |> transform(module)
    |> encode_with_props(module.__kiwi_props__())
  end

  defp encode_with_props(struct, %Metadata{kind: :message, ordered_fields: fields}) do
    [Enum.map(fields, &encode_message_field(&1, struct)), Varint.encode_uint(0)]
  end

  defp encode_with_props(struct, %Metadata{kind: :struct, ordered_fields: fields}) do
    Enum.map(fields, &encode_required_field(&1, struct))
  end

  defp encode_message_field(%Field{name: name} = field, struct) do
    value = Map.fetch!(struct, name)

    if is_nil(value) do
      []
    else
      [Varint.encode_uint(field.id), encode_field_value(field, value)]
    end
  rescue
    error in [KiwiCodec.EncodeError, ArgumentError, FunctionClauseError, KeyError, MatchError] ->
      raise_encode_field_error(struct.__struct__, field, error)
  end

  defp encode_required_field(%Field{name: name} = field, struct) do
    value = Map.fetch!(struct, name)

    if is_nil(value) do
      raise KiwiCodec.EncodeError, message: "missing required field #{inspect(name)}"
    end

    encode_field_value(field, value)
  rescue
    error in [KiwiCodec.EncodeError, ArgumentError, FunctionClauseError, KeyError, MatchError] ->
      raise_encode_field_error(struct.__struct__, field, error)
  end

  defp encode_field_value(%Field{repeated?: true, type: :byte}, value)
       when is_binary(value) do
    Wire.encode_byte_array(value)
  end

  defp encode_field_value(%Field{repeated?: true} = field, values) when is_list(values) do
    [Varint.encode_uint(length(values)), Enum.map(values, &encode_scalar(field.type, &1))]
  end

  defp encode_field_value(%Field{} = field, value) do
    encode_scalar(field.type, value)
  end

  defp encode_scalar({:enum, module}, value) when is_atom(value) do
    module.value(value)
    |> Varint.encode_uint()
  end

  defp encode_scalar({:enum, _module}, value) when is_integer(value),
    do: Varint.encode_uint(value)

  defp encode_scalar(type, value)
       when type in [:bool, :byte, :float, :int, :int64, :string, :uint, :uint64],
       do: Wire.encode(type, value)

  defp encode_scalar(module, %module{} = value) when is_atom(module),
    do: encode_to_iodata(value, module)

  defp encode_scalar(type, value) do
    raise KiwiCodec.EncodeError, message: "invalid #{inspect(value)} for type #{inspect(type)}"
  end

  defp transform(message, module) do
    case module.transform_module() do
      nil -> message
      transform_module -> transform_module.encode(message, module)
    end
  end

  defp raise_encode_field_error(module, field, error) do
    raise KiwiCodec.EncodeError,
      message: "error encoding #{inspect(module)}##{field.name}: #{Exception.message(error)}"
  end
end
