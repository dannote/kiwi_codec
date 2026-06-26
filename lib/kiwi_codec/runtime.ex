defmodule KiwiCodec.Runtime do
  @moduledoc """
  Interpreter for parsed Kiwi schemas without generated modules.

  Prefer generated modules for application code. This runtime is useful for
  tooling, inspection, and compatibility tests where schemas are loaded at runtime.
  """

  alias KiwiCodec.Schema
  alias KiwiCodec.Schema.{Definition, Field}
  alias KiwiCodec.Wire
  alias KiwiCodec.Wire.Varint

  @spec decode(Schema.t(), String.t(), binary()) :: map() | String.t() | integer()
  def decode(%Schema{} = schema, definition_name, binary) do
    {value, rest} = decode_definition(schema, definition!(schema, definition_name), binary)

    if rest == "" do
      value
    else
      raise KiwiCodec.DecodeError, message: "unexpected trailing bytes"
    end
  end

  @spec encode(Schema.t(), String.t(), map()) :: binary()
  def encode(%Schema{} = schema, definition_name, value) do
    definition = definition!(schema, definition_name)

    schema
    |> encode_definition(definition, value)
    |> IO.iodata_to_binary()
  end

  defp decode_definition(schema, %Definition{kind: :message} = definition, binary) do
    decode_message(schema, definition, binary, %{})
  end

  defp decode_definition(schema, %Definition{kind: :struct} = definition, binary) do
    Enum.reduce(definition.fields, {%{}, binary}, fn field, {acc, rest} ->
      {value, tail} = decode_wire_field(schema, field, rest)
      {Map.put(acc, field.name, value), tail}
    end)
  end

  defp decode_definition(_schema, %Definition{kind: :enum} = definition, binary) do
    {value, rest} = Varint.decode_uint(binary)
    field = Enum.find(definition.fields, &(&1.value == value))
    {if(field, do: field.name, else: value), rest}
  end

  defp decode_message(schema, definition, binary, acc) do
    {field_id, rest} = Varint.decode_uint(binary)

    case field_id do
      0 ->
        {acc, rest}

      id ->
        field =
          Enum.find(definition.fields, &(&1.value == id)) || raise_unknown_field(definition, id)

        {value, tail} = decode_wire_field(schema, field, rest)
        decode_message(schema, definition, tail, Map.put(acc, field.name, value))
    end
  end

  defp decode_wire_field(_schema, %Field{array?: true, type: "byte"}, binary) do
    Wire.decode_byte_array(binary)
  end

  defp decode_wire_field(schema, %Field{array?: true} = field, binary) do
    {length, rest} = Varint.decode_uint(binary)

    Enum.reduce(1..length//1, {[], rest}, fn _index, {values, tail} ->
      {value, next} = decode_wire_type(schema, field.type, tail)
      {[value | values], next}
    end)
    |> then(fn {values, tail} -> {Enum.reverse(values), tail} end)
  end

  defp decode_wire_field(schema, field, binary), do: decode_wire_type(schema, field.type, binary)

  defp decode_wire_type(schema, type, binary) do
    if KiwiCodec.PrimitiveType.name?(type) do
      Wire.decode(KiwiCodec.PrimitiveType.to_atom!(type), binary)
    else
      decode_definition(schema, definition!(schema, type), binary)
    end
  end

  defp encode_definition(schema, %Definition{kind: :message} = definition, value)
       when is_map(value) do
    [Enum.map(definition.fields, &encode_message_field(schema, &1, value)), Varint.encode_uint(0)]
  end

  defp encode_definition(schema, %Definition{kind: :struct} = definition, value)
       when is_map(value) do
    Enum.map(definition.fields, fn field ->
      field_value = fetch_value!(value, field.name)
      encode_wire_field(schema, field, field_value)
    end)
  end

  defp encode_definition(_schema, %Definition{kind: :enum} = definition, value) do
    cond do
      is_integer(value) ->
        Varint.encode_uint(value)

      is_binary(value) ->
        definition.fields
        |> Enum.find(&(&1.name == value))
        |> Map.fetch!(:value)
        |> Varint.encode_uint()

      true ->
        raise KiwiCodec.EncodeError, message: "invalid enum value #{inspect(value)}"
    end
  end

  defp encode_message_field(schema, field, value) do
    case fetch_value(value, field.name) do
      nil ->
        []

      field_value ->
        [Varint.encode_uint(field.value), encode_wire_field(schema, field, field_value)]
    end
  end

  defp encode_wire_field(_schema, %Field{array?: true, type: "byte"}, value)
       when is_binary(value) do
    Wire.encode_byte_array(value)
  end

  defp encode_wire_field(schema, %Field{array?: true} = field, values) when is_list(values) do
    [
      Varint.encode_uint(length(values)),
      Enum.map(values, &encode_wire_type(schema, field.type, &1))
    ]
  end

  defp encode_wire_field(schema, field, value), do: encode_wire_type(schema, field.type, value)

  defp encode_wire_type(schema, type, value) do
    if KiwiCodec.PrimitiveType.name?(type) do
      Wire.encode(KiwiCodec.PrimitiveType.to_atom!(type), value)
    else
      encode_definition(schema, definition!(schema, type), value)
    end
  end

  defp definition!(schema, name) do
    Schema.definition(schema, name) || raise ArgumentError, "unknown definition #{inspect(name)}"
  end

  defp fetch_value(map, key), do: Map.get(map, key)

  defp fetch_value!(map, key) do
    case fetch_value(map, key) do
      nil -> raise KiwiCodec.EncodeError, message: "missing required field #{inspect(key)}"
      value -> value
    end
  end

  defp raise_unknown_field(definition, id) do
    raise KiwiCodec.DecodeError, message: "unknown field #{id} while decoding #{definition.name}"
  end
end
