defmodule KiwiCodec.Wire.VarintTest do
  use ExUnit.Case, async: true

  alias KiwiCodec.Wire.Varint

  test "encodes unsigned integers with LEB128" do
    assert Varint.encode_uint(300) == <<172, 2>>

    assert Varint.encode_uint64(0xFFFF_FFFF_FFFF_FFFF) ==
             <<255, 255, 255, 255, 255, 255, 255, 255, 255, 1>>
  end

  test "encodes signed integers with ZigZag and LEB128" do
    assert Varint.encode_int(-150) == <<171, 2>>
    assert Varint.encode_int(-0x8000_0000) == <<255, 255, 255, 255, 15>>

    assert Varint.encode_int64(-0x8000_0000_0000_0000) ==
             <<255, 255, 255, 255, 255, 255, 255, 255, 255, 1>>
  end

  test "decodes values and preserves rest" do
    assert Varint.decode_uint(<<172, 2, 0>>) == {300, <<0>>}
    assert Varint.decode_int(<<171, 2, 0>>) == {-150, <<0>>}
  end

  test "rejects out-of-range encoded integers" do
    assert_raise KiwiCodec.DecodeError, ~r/uint out of range/, fn ->
      Varint.decode_uint(<<128, 128, 128, 128, 16>>)
    end

    assert_raise KiwiCodec.DecodeError, ~r/uint64 out of range/, fn ->
      Varint.decode_uint64(<<128, 128, 128, 128, 128, 128, 128, 128, 128, 2>>)
    end
  end

  test "normalizes malformed varints to Kiwi decode errors" do
    assert_raise KiwiCodec.DecodeError, ~r/cannot decode varint/, fn ->
      Varint.decode_uint(<<218>>)
    end
  end

  test "raises Kiwi encode errors for out-of-range values" do
    assert_raise KiwiCodec.EncodeError, ~r/type :uint/, fn -> Varint.encode_uint(-1) end
    assert_raise KiwiCodec.EncodeError, ~r/type :int/, fn -> Varint.encode_int(0x8000_0000) end
  end
end
