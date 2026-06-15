defmodule KiwiCodec.Container do
  @moduledoc """
  Helpers for Kiwi chunk containers with an 8-byte magic and little-endian chunk lengths.
  """

  @default_magic "fig-kiwi"
  @default_version 101

  @type parsed :: %{magic: binary(), version: non_neg_integer(), chunks: [binary()]}

  @doc """
  Parses all chunks from a Kiwi container.
  """
  @spec parse(binary(), binary()) :: parsed()
  def parse(binary, magic \\ @default_magic) when is_binary(binary) and is_binary(magic) do
    magic_size = byte_size(magic)

    case binary do
      <<^magic::binary-size(^magic_size), version::32-little, rest::binary>> ->
        %{magic: magic, version: version, chunks: parse_chunks(rest, [])}

      _ ->
        raise KiwiCodec.DecodeError, message: "invalid Kiwi container magic"
    end
  end

  @doc """
  Returns one raw chunk from a Kiwi container without parsing later chunks.

  Chunk indexes are zero-based.
  """
  @spec chunk(binary(), non_neg_integer(), binary()) :: binary()
  def chunk(binary, index, magic \\ @default_magic)

  def chunk(binary, index, magic)
      when is_binary(binary) and is_integer(index) and index >= 0 and is_binary(magic) do
    magic_size = byte_size(magic)

    case binary do
      <<^magic::binary-size(^magic_size), _version::32-little, rest::binary>> ->
        chunk_at(rest, index)

      _ ->
        raise KiwiCodec.DecodeError, message: "invalid Kiwi container magic"
    end
  end

  @doc """
  Returns the inflated data chunk from a Kiwi container.

  This is useful for callers that only need the payload and want to avoid
  inflating or decoding the schema chunk.
  """
  @spec data(binary(), binary()) :: binary()
  def data(binary, magic \\ @default_magic) when is_binary(binary) and is_binary(magic) do
    data(binary, magic, &inflate/1)
  end

  @doc """
  Returns the data chunk inflated with a caller-provided inflater.
  """
  @spec data(binary(), binary(), (binary() -> binary())) :: binary()
  def data(binary, magic, inflater)
      when is_binary(binary) and is_binary(magic) and is_function(inflater, 1) do
    binary
    |> chunk(1, magic)
    |> inflater.()
  end

  @spec build([iodata()], keyword()) :: binary()
  def build(chunks, opts \\ []) when is_list(chunks) do
    magic = Keyword.get(opts, :magic, @default_magic)
    version = Keyword.get(opts, :version, @default_version)

    [
      magic,
      <<version::32-little>>,
      Enum.map(chunks, fn chunk ->
        binary = IO.iodata_to_binary(chunk)
        [<<byte_size(binary)::32-little>>, binary]
      end)
    ]
    |> IO.iodata_to_binary()
  end

  @spec deflate(iodata()) :: binary()
  def deflate(data), do: data |> IO.iodata_to_binary() |> :zlib.zip()

  @spec inflate(binary()) :: binary()
  def inflate(data) when is_binary(data), do: :zlib.unzip(data)

  defp chunk_at(<<length::32-little, chunk::binary-size(length), _rest::binary>>, 0), do: chunk

  defp chunk_at(<<length::32-little, _chunk::binary-size(length), rest::binary>>, index) do
    chunk_at(rest, index - 1)
  end

  defp chunk_at(_binary, _index) do
    raise KiwiCodec.DecodeError, message: "truncated Kiwi container"
  end

  defp parse_chunks("", acc), do: Enum.reverse(acc)

  defp parse_chunks(<<length::32-little, chunk::binary-size(length), rest::binary>>, acc) do
    parse_chunks(rest, [chunk | acc])
  end

  defp parse_chunks(_binary, _acc) do
    raise KiwiCodec.DecodeError, message: "truncated Kiwi container"
  end
end
