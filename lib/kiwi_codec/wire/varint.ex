defmodule KiwiCodec.Wire.Varint do
  @moduledoc """
  Kiwi integer wire encoding.

  Kiwi uses unsigned LEB128 for `uint`/`uint64` and ZigZag + unsigned LEB128
  for `int`/`int64`. The actual LEB128/ZigZag mechanics are delegated to the
  `varint` package; this module keeps Kiwi-specific range checks and error
  normalization at the wire boundary.
  """

  alias Varint.{LEB128, Zigzag}

  @uint32_max 0xFFFF_FFFF
  @uint64_max 0xFFFF_FFFF_FFFF_FFFF
  @int32_min -0x8000_0000
  @int32_max 0x7FFF_FFFF
  @int64_min -0x8000_0000_0000_0000
  @int64_max 0x7FFF_FFFF_FFFF_FFFF

  @spec encode_uint(non_neg_integer()) :: binary()
  def encode_uint(value) when is_integer(value) and value in 0..@uint32_max do
    LEB128.encode(value)
  end

  def encode_uint(value) do
    raise KiwiCodec.EncodeError, message: "invalid #{inspect(value)} for type :uint"
  end

  @spec encode_uint64(non_neg_integer()) :: binary()
  def encode_uint64(value) when is_integer(value) and value in 0..@uint64_max do
    LEB128.encode(value)
  end

  def encode_uint64(value) do
    raise KiwiCodec.EncodeError, message: "invalid #{inspect(value)} for type :uint64"
  end

  @spec encode_int(integer()) :: binary()
  def encode_int(value) when is_integer(value) and value in @int32_min..@int32_max do
    value
    |> Zigzag.encode()
    |> LEB128.encode()
  end

  def encode_int(value) do
    raise KiwiCodec.EncodeError, message: "invalid #{inspect(value)} for type :int"
  end

  @spec encode_int64(integer()) :: binary()
  def encode_int64(value) when is_integer(value) and value in @int64_min..@int64_max do
    value
    |> Zigzag.encode()
    |> LEB128.encode()
  end

  def encode_int64(value) do
    raise KiwiCodec.EncodeError, message: "invalid #{inspect(value)} for type :int64"
  end

  @spec decode_uint(binary()) :: {non_neg_integer(), binary()}
  def decode_uint(binary) do
    {value, rest} = decode_unsigned!(binary)

    if value <= @uint32_max,
      do: {value, rest},
      else: raise(KiwiCodec.DecodeError, message: "uint out of range")
  end

  @spec decode_uint64(binary()) :: {non_neg_integer(), binary()}
  def decode_uint64(binary) do
    {value, rest} = decode_unsigned!(binary)

    if value <= @uint64_max,
      do: {value, rest},
      else: raise(KiwiCodec.DecodeError, message: "uint64 out of range")
  end

  @spec decode_int(binary()) :: {integer(), binary()}
  def decode_int(binary) do
    {value, rest} = decode_uint(binary)
    {Zigzag.decode(value), rest}
  end

  @spec decode_int64(binary()) :: {integer(), binary()}
  def decode_int64(binary) do
    {value, rest} = decode_uint64(binary)
    {Zigzag.decode(value), rest}
  end

  defp decode_unsigned!(binary) when is_binary(binary) do
    LEB128.decode(binary)
  rescue
    ArgumentError ->
      reraise KiwiCodec.DecodeError, [message: "cannot decode varint"], __STACKTRACE__
  end
end
