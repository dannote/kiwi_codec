defmodule KiwiCodec.Schema.Tokenizer do
  @moduledoc """
  Tokenizes `.kiwi` schema text with source positions.
  """

  alias KiwiCodec.Schema.Token

  @token_pattern ~r/((?:-|\b)\d+\b|[=;{}]|\[\]|\[deprecated\]|\b[A-Za-z_][A-Za-z0-9_]*\b|\/\/.*|\s+)/

  @spec tokenize(String.t()) :: [Token.t()]
  def tokenize(text) when is_binary(text) do
    {tokens, line, column} =
      @token_pattern
      |> Regex.split(text, include_captures: true, trim: false)
      |> Enum.reduce({[], 1, 1}, &tokenize_part/2)

    Enum.reverse([%Token{text: "", line: line, column: column} | tokens])
  end

  defp tokenize_part(part, {tokens, line, column}) do
    token? = Regex.match?(@token_pattern, part)
    ignored? = Regex.match?(~r/^(\/\/.*|\s+)$/, part)

    tokens =
      cond do
        part == "" or ignored? ->
          tokens

        token? ->
          [%Token{text: part, line: line, column: column} | tokens]

        true ->
          Token.parse_error!(%Token{text: part, line: line, column: column}, "unexpected input")
      end

    {line, column} = advance_position(part, line, column)
    {tokens, line, column}
  end

  defp advance_position(part, line, column) do
    case String.split(part, "\n") do
      [_single] -> {line, column + String.length(part)}
      parts -> {line + length(parts) - 1, String.length(List.last(parts)) + 1}
    end
  end
end
