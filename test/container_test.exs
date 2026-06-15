defmodule KiwiCodec.ContainerTest do
  use ExUnit.Case, async: true

  test "builds and parses chunk containers" do
    schema = KiwiCodec.Container.deflate("schema")
    data = KiwiCodec.Container.deflate("data")

    parsed = KiwiCodec.Container.build([schema, data]) |> KiwiCodec.Container.parse()

    assert parsed.magic == "fig-kiwi"
    assert parsed.version == 101
    assert Enum.map(parsed.chunks, &KiwiCodec.Container.inflate/1) == ["schema", "data"]
  end

  test "extracts individual chunks" do
    schema = KiwiCodec.Container.deflate("schema")
    data = KiwiCodec.Container.deflate("data")
    container = KiwiCodec.Container.build([schema, data])

    assert container |> KiwiCodec.Container.chunk(0) |> KiwiCodec.Container.inflate() == "schema"
    assert container |> KiwiCodec.Container.chunk(1) |> KiwiCodec.Container.inflate() == "data"
  end

  test "inflates the data chunk without decoding schema" do
    container =
      [
        KiwiCodec.Container.deflate("schema"),
        KiwiCodec.Container.deflate("data")
      ]
      |> KiwiCodec.Container.build()

    assert KiwiCodec.Container.data(container) == "data"
  end

  test "inflates data chunks with a caller-provided inflater" do
    container = KiwiCodec.Container.build(["schema", "DATA"])

    assert KiwiCodec.Container.data(container, "fig-kiwi", &String.downcase/1) == "data"
  end
end
