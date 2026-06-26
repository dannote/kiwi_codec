defmodule KiwiCodec.Schema.Binary do
  @moduledoc """
  Encoder and decoder for Kiwi's compact binary schema format.
  """

  alias KiwiCodec.Schema
  alias KiwiCodec.Schema.Binary.TypeIndex
  alias KiwiCodec.Schema.Enum, as: SchemaEnum
  alias KiwiCodec.Schema.{EnumVariant, Field, Message, Struct}
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
    %Schema{definitions: bind_field_types!(definitions)}
  end

  defp encode_definition(%SchemaEnum{} = definition, definition_index) do
    encode_definition_members(definition.name, :enum, definition.variants, definition_index)
  end

  defp encode_definition(%Struct{} = definition, definition_index) do
    encode_definition_members(definition.name, :struct, definition.fields, definition_index)
  end

  defp encode_definition(%Message{} = definition, definition_index) do
    encode_definition_members(definition.name, :message, definition.fields, definition_index)
  end

  defp encode_definition_members(name, kind, members, definition_index) do
    [
      Wire.encode(:string, name),
      Wire.encode(:byte, kind_to_index!(kind)),
      Varint.encode_uint(length(members)),
      Enum.map(members, &encode_member(&1, definition_index))
    ]
  end

  defp encode_member(%EnumVariant{} = variant, _definition_index) do
    [
      Wire.encode(:string, variant.name),
      Varint.encode_int(0),
      Wire.encode(:byte, 0),
      Varint.encode_uint(variant.value)
    ]
  end

  defp encode_member(%Field{} = field, definition_index) do
    [
      Wire.encode(:string, field.name),
      Varint.encode_int(TypeIndex.encode(field, definition_index)),
      Wire.encode(:byte, if(field.array?, do: 1, else: 0)),
      Varint.encode_uint(field.id)
    ]
  end

  defp decode_definition(binary) do
    {name, rest} = Wire.decode(:string, binary)
    {kind_index, rest} = Wire.decode(:byte, rest)
    kind = kind_from_index!(kind_index)
    {field_count, rest} = Varint.decode_uint(rest)

    {members, rest} =
      Enum.reduce(1..field_count//1, {[], rest}, fn _index, {acc, tail} ->
        {member, next} = decode_member(tail, kind)
        {[member | acc], next}
      end)

    {decode_definition_struct(kind, name, Enum.reverse(members)), rest}
  end

  defp decode_member(binary, kind) do
    {name, rest} = Wire.decode(:string, binary)
    {type, rest} = Varint.decode_int(rest)
    {array_flag, rest} = Wire.decode(:byte, rest)
    {value, rest} = Varint.decode_uint(rest)

    {decode_schema_member(kind, name, type, array_flag, value), rest}
  end

  defp bind_field_types!(definitions) do
    Enum.map(definitions, fn
      %SchemaEnum{} = definition ->
        definition

      definition ->
        fields = Enum.map(definition.fields, &bind_field_type!(&1, definitions))
        %{definition | fields: fields}
    end)
  end

  defp kind_to_index!(kind) do
    case Enum.find_index(@kinds, &(&1 == kind)) do
      nil -> raise KiwiCodec.EncodeError, message: "invalid definition kind #{inspect(kind)}"
      index -> index
    end
  end

  defp kind_from_index!(index) when is_integer(index) and index >= 0 and index < @kind_count,
    do: elem(@kinds_tuple, index)

  defp kind_from_index!(_index) do
    raise KiwiCodec.DecodeError, message: "invalid definition kind in binary schema"
  end

  defp decode_definition_struct(:enum, name, variants),
    do: %SchemaEnum{name: name, variants: variants}

  defp decode_definition_struct(:struct, name, fields), do: %Struct{name: name, fields: fields}
  defp decode_definition_struct(:message, name, fields), do: %Message{name: name, fields: fields}

  defp decode_schema_member(:enum, name, _type, _array_flag, value) do
    %EnumVariant{name: name, value: value}
  end

  defp decode_schema_member(_kind, name, type, array_flag, id) do
    %Field{name: name, type: type, array?: Bitwise.band(array_flag, 1) == 1, id: id}
  end

  defp bind_field_type!(%Field{type: type} = field, definitions) when is_integer(type) do
    %{field | type: TypeIndex.decode(type, definitions)}
  end

  defp reraise_decode_error(%KiwiCodec.DecodeError{} = error, stacktrace),
    do: reraise(error, stacktrace)

  defp reraise_decode_error(error, _stacktrace) do
    raise KiwiCodec.DecodeError, message: "invalid binary schema: #{Exception.message(error)}"
  end
end
