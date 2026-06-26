defmodule KiwiCodec.Schema.Binary do
  @moduledoc """
  Encoder and decoder for Kiwi's compact binary schema format.
  """

  alias KiwiCodec.Schema
  alias KiwiCodec.Schema.{Definition, EnumVariant, Field}
  alias KiwiCodec.Wire
  alias KiwiCodec.Wire.Varint

  @kinds [:enum, :struct, :message]
  @kinds_tuple List.to_tuple(@kinds)
  @kind_count tuple_size(@kinds_tuple)

  @spec encode(Schema.t()) :: binary()
  def encode(%Schema{definitions: definitions}) do
    definition_index =
      definitions
      |> Enum.with_index()
      |> Map.new(fn {definition, index} -> {definition.name, index} end)

    [
      Varint.encode_uint(length(definitions)),
      Enum.map(definitions, &encode_definition(&1, definition_index))
    ]
    |> IO.iodata_to_binary()
  end

  @spec decode(binary()) :: Schema.t()
  def decode(binary) when is_binary(binary) do
    do_decode(binary)
  rescue
    error in [
      ArgumentError,
      Enum.OutOfBoundsError,
      FunctionClauseError,
      MatchError,
      KiwiCodec.DecodeError
    ] ->
      reraise_decode_error(error, __STACKTRACE__)
  end

  defp do_decode(binary) do
    {count, rest} = Varint.decode_uint(binary)

    {definitions, rest} =
      Enum.reduce(1..count//1, {[], rest}, fn _index, {acc, tail} ->
        {definition, next} = decode_definition(tail)
        {[definition | acc], next}
      end)

    if rest != "", do: raise(KiwiCodec.DecodeError, message: "trailing bytes in binary schema")

    definitions = Enum.reverse(definitions)
    %Schema{definitions: bind_types!(definitions)}
  end

  defp encode_definition(definition, definition_index) do
    kind_index = Enum.find_index(@kinds, &(&1 == definition.kind))

    [
      Wire.encode(:string, definition.name),
      Wire.encode(:byte, kind_index),
      Varint.encode_uint(length(definition.fields)),
      Enum.map(definition.fields, &encode_field(&1, definition_index))
    ]
  end

  defp decode_kind!(index) when is_integer(index) and index >= 0 and index < @kind_count,
    do: elem(@kinds_tuple, index)

  defp decode_kind!(_index) do
    raise KiwiCodec.DecodeError, message: "invalid definition kind in binary schema"
  end

  defp encode_field(%EnumVariant{} = variant, _definition_index) do
    [
      Wire.encode(:string, variant.name),
      Varint.encode_int(0),
      Wire.encode(:byte, 0),
      Varint.encode_uint(variant.value)
    ]
  end

  defp encode_field(%Field{} = field, definition_index) do
    type_index = KiwiCodec.PrimitiveType.binary_schema_index(field.type)

    encoded_type =
      if is_nil(type_index),
        do: Map.fetch!(definition_index, field.type),
        else: Bitwise.bnot(type_index)

    [
      Wire.encode(:string, field.name),
      Varint.encode_int(encoded_type),
      Wire.encode(:byte, if(field.array?, do: 1, else: 0)),
      Varint.encode_uint(field.id)
    ]
  end

  defp decode_definition(binary) do
    {name, rest} = Wire.decode(:string, binary)
    {kind_index, rest} = Wire.decode(:byte, rest)
    kind = decode_kind!(kind_index)
    {field_count, rest} = Varint.decode_uint(rest)

    {fields, rest} =
      Enum.reduce(1..field_count//1, {[], rest}, fn _index, {acc, tail} ->
        {field, next} = decode_field(tail, kind)
        {[field | acc], next}
      end)

    {%Definition{name: name, kind: kind, fields: Enum.reverse(fields)}, rest}
  end

  defp decode_field(binary, kind) do
    {name, rest} = Wire.decode(:string, binary)
    {type, rest} = Varint.decode_int(rest)
    {array_flag, rest} = Wire.decode(:byte, rest)
    {value, rest} = Varint.decode_uint(rest)

    {decode_schema_member(kind, name, type, array_flag, value), rest}
  end

  defp bind_types!(definitions) do
    Enum.map(definitions, fn definition ->
      fields = Enum.map(definition.fields, &bind_type!(&1, definitions))
      %{definition | fields: fields}
    end)
  end

  defp decode_schema_member(:enum, name, _type, _array_flag, value) do
    %EnumVariant{name: name, value: value}
  end

  defp decode_schema_member(_kind, name, type, array_flag, id) do
    %Field{name: name, type: type, array?: Bitwise.band(array_flag, 1) == 1, id: id}
  end

  defp bind_type!(%EnumVariant{} = variant, _definitions), do: variant

  defp bind_type!(%Field{type: type} = field, _definitions) when is_integer(type) and type < 0 do
    index = Bitwise.bnot(type)
    %{field | type: KiwiCodec.PrimitiveType.binary_schema_name!(index)}
  end

  defp bind_type!(%Field{type: type} = field, definitions) when is_integer(type) do
    %{field | type: definitions |> Enum.fetch!(type) |> Map.fetch!(:name)}
  end

  defp reraise_decode_error(%KiwiCodec.DecodeError{} = error, stacktrace),
    do: reraise(error, stacktrace)

  defp reraise_decode_error(error, _stacktrace) do
    raise KiwiCodec.DecodeError, message: "invalid binary schema: #{Exception.message(error)}"
  end
end
