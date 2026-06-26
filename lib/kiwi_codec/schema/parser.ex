defmodule KiwiCodec.Schema.Parser do
  @moduledoc """
  Parser for `.kiwi` schema text.
  """

  alias KiwiCodec.Schema
  alias KiwiCodec.Schema.Enum, as: SchemaEnum
  alias KiwiCodec.Schema.{EnumVariant, Field, Message, Struct, Token, Tokenizer, Validator}

  @spec parse!(String.t()) :: Schema.t()
  def parse!(text) when is_binary(text) do
    text
    |> Tokenizer.tokenize()
    |> parse_tokens()
    |> Validator.validate!()
  end

  defp parse_tokens(tokens) do
    {package, rest} = parse_package(tokens)
    {definitions, rest} = parse_definitions(rest, [])
    expect!(rest, "")
    %Schema{package: package, definitions: Enum.reverse(definitions)}
  end

  defp parse_package([%Token{text: "package"}, token | rest]) do
    expect_identifier!(token)
    {_, rest} = expect!(rest, ";")
    {token.text, rest}
  end

  defp parse_package(tokens), do: {nil, tokens}

  defp parse_definitions([%Token{text: ""} | _] = tokens, acc), do: {acc, tokens}

  defp parse_definitions([kind_token, name_token | rest], acc) do
    kind = parse_kind!(kind_token)
    expect_identifier!(name_token)
    {_, rest} = expect!(rest, "{")
    {members, rest} = parse_fields(rest, kind, [])

    definition =
      build_definition(
        kind,
        name_token.text,
        Enum.reverse(members),
        name_token.line,
        name_token.column
      )

    parse_definitions(rest, [definition | acc])
  end

  defp parse_kind!(%Token{text: "enum"}), do: :enum
  defp parse_kind!(%Token{text: "struct"}), do: :struct
  defp parse_kind!(%Token{text: "message"}), do: :message
  defp parse_kind!(token), do: Token.parse_error!(token, "expected definition kind")

  defp build_definition(:enum, name, variants, line, column),
    do: %SchemaEnum{name: name, variants: variants, line: line, column: column}

  defp build_definition(:struct, name, fields, line, column),
    do: %Struct{name: name, fields: fields, line: line, column: column}

  defp build_definition(:message, name, fields, line, column),
    do: %Message{name: name, fields: fields, line: line, column: column}

  defp parse_fields([%Token{text: "}"} | rest], _kind, acc), do: {acc, rest}

  defp parse_fields(tokens, :enum, acc) do
    [name_token | rest] = tokens
    expect_identifier!(name_token)
    {_, rest} = expect!(rest, "=")
    [value_token | rest] = rest
    value = parse_integer!(value_token)
    {_, rest} = expect!(rest, ";")

    variant = %EnumVariant{
      name: name_token.text,
      value: value,
      line: name_token.line,
      column: name_token.column
    }

    parse_fields(rest, :enum, [variant | acc])
  end

  defp parse_fields([type_token | rest], kind, acc) do
    expect_identifier!(type_token)
    {array?, rest} = parse_array(rest)
    [name_token | rest] = rest
    expect_identifier!(name_token)

    {id, rest} = parse_field_id(kind, acc, rest)
    {deprecated?, rest} = parse_deprecated(rest)
    {_, rest} = expect!(rest, ";")

    field = %Field{
      name: name_token.text,
      type: type_token.text,
      array?: array?,
      deprecated?: deprecated?,
      id: id,
      line: name_token.line,
      column: name_token.column
    }

    parse_fields(rest, kind, [field | acc])
  end

  defp parse_field_id(:struct, acc, rest), do: {length(acc) + 1, rest}

  defp parse_field_id(_kind, _acc, rest) do
    {_, rest} = expect!(rest, "=")
    [value_token | rest] = rest
    {parse_integer!(value_token), rest}
  end

  defp parse_array([%Token{text: "[]"} | rest]), do: {true, rest}
  defp parse_array(rest), do: {false, rest}

  defp parse_deprecated([%Token{text: "[deprecated]"} | rest]), do: {true, rest}
  defp parse_deprecated(rest), do: {false, rest}

  defp expect!([%Token{text: expected} = token | rest], expected), do: {token, rest}

  defp expect!([token | _rest], expected),
    do: Token.parse_error!(token, "expected #{inspect(expected)}")

  defp expect_identifier!(%Token{text: text} = token) do
    unless Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, text),
      do: Token.parse_error!(token, "expected identifier")
  end

  defp parse_integer!(%Token{text: text} = token) do
    case Integer.parse(text) do
      {value, ""} -> value
      _ -> Token.parse_error!(token, "expected integer")
    end
  end
end
