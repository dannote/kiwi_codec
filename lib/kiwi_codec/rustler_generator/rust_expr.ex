defmodule KiwiCodec.RustlerGenerator.RustExpr do
  @moduledoc """
  Shared Rust source-expression helpers for Kiwi Rustler generator modules.

  These helpers keep schema-generic renderer modules focused on decoder shape
  while centralizing primitive decoder expressions and small formatting details.
  """

  @primitive %{
    "bool" => "decoder.read_bool()?",
    "byte" => "decoder.read_byte()?",
    "float" => "decoder.read_var_float(env)?",
    "int" => "decoder.read_var_int()?",
    "int64" => "decoder.read_var_int64()?",
    "string" => "decoder.read_string(env)?",
    "uint" => "decoder.read_var_uint()?",
    "uint64" => "decoder.read_var_uint64()?"
  }

  @spec primitive(String.t()) :: String.t() | nil
  def primitive(type), do: @primitive[type]

  @spec skip_primitive(String.t()) :: String.t() | nil
  def skip_primitive("float"), do: "decoder.read_var_float_value()?"
  def skip_primitive("string"), do: "decoder.skip_string()?"
  def skip_primitive(type), do: primitive(type)

  @spec ident(String.t() | atom()) :: String.t()
  def ident(name) when is_atom(name), do: Atom.to_string(name)

  def ident(name) do
    name
    |> Macro.underscore()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
  end

  @spec indent(iodata(), non_neg_integer()) :: String.t() | []
  def indent([], _spaces), do: []

  def indent(iodata, spaces) do
    padding = String.duplicate(" ", spaces)

    iodata
    |> IO.iodata_to_binary()
    |> String.split("\n")
    |> Enum.map_join("\n", &(padding <> &1))
  end
end
