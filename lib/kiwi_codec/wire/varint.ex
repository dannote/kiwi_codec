defmodule KiwiCodec.Wire.Varint do
  @moduledoc false

  import Bitwise

  @uint32_max 0xFFFF_FFFF
  @uint64_max 0xFFFF_FFFF_FFFF_FFFF
  @int32_min -0x8000_0000
  @int32_max 0x7FFF_FFFF
  @int64_min -0x8000_0000_0000_0000
  @int64_max 0x7FFF_FFFF_FFFF_FFFF

  @spec encode_uint(non_neg_integer()) :: iodata()
  def encode_uint(value) when is_integer(value) and value in 0..@uint32_max do
    encode_unsigned(value)
  end

  @spec encode_uint64(non_neg_integer()) :: iodata()
  def encode_uint64(value) when is_integer(value) and value in 0..@uint64_max do
    encode_unsigned(value)
  end

  @spec encode_int(integer()) :: iodata()
  def encode_int(value) when is_integer(value) and value in @int32_min..@int32_max do
    value
    |> zigzag_encode()
    |> encode_unsigned()
  end

  @spec encode_int64(integer()) :: iodata()
  def encode_int64(value) when is_integer(value) and value in @int64_min..@int64_max do
    value
    |> zigzag_encode()
    |> encode_unsigned()
  end

  @spec decode_uint(binary()) :: {non_neg_integer(), binary()}
  def decode_uint(binary) do
    {value, rest} = decode_unsigned(binary)

    if value <= @uint32_max,
      do: {value, rest},
      else: raise(KiwiCodec.DecodeError, message: "uint out of range")
  end

  @spec decode_uint64(binary()) :: {non_neg_integer(), binary()}
  def decode_uint64(binary) do
    {value, rest} = decode_unsigned(binary)

    if value <= @uint64_max,
      do: {value, rest},
      else: raise(KiwiCodec.DecodeError, message: "uint64 out of range")
  end

  @spec decode_int(binary()) :: {integer(), binary()}
  def decode_int(binary) do
    {value, rest} = decode_uint(binary)
    {zigzag_decode(value), rest}
  end

  @spec decode_int64(binary()) :: {integer(), binary()}
  def decode_int64(binary) do
    {value, rest} = decode_uint64(binary)
    {zigzag_decode(value), rest}
  end

  defp encode_unsigned(value) when value <= 0x7F, do: [value]

  defp encode_unsigned(value) do
    [bor(band(value, 0x7F), 0x80) | encode_unsigned(value >>> 7)]
  end

  defp decode_unsigned(<<byte, rest::binary>>) when byte < 0x80, do: {byte, rest}

  defp decode_unsigned(<<byte, rest::binary>>) do
    decode_unsigned(rest, byte &&& 0x7F, 7, 1)
  end

  defp decode_unsigned(_binary) do
    raise KiwiCodec.DecodeError, message: "cannot decode varint"
  end

  defp decode_unsigned(<<byte, rest::binary>>, acc, shift, count) when count < 10 do
    value = acc ||| (byte &&& 0x7F) <<< shift

    if byte < 0x80 do
      {value, rest}
    else
      decode_unsigned(rest, value, shift + 7, count + 1)
    end
  end

  defp decode_unsigned(_binary, _acc, _shift, _count) do
    raise KiwiCodec.DecodeError, message: "cannot decode varint"
  end

  defp zigzag_encode(value), do: if(value < 0, do: -2 * value - 1, else: 2 * value)

  defp zigzag_decode(value),
    do: if((value &&& 1) == 1, do: -((value + 1) >>> 1), else: value >>> 1)
end
