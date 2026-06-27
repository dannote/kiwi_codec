defmodule KiwiCodec.PrimitiveType do
  @moduledoc """
  Kiwi primitive type metadata.

  This module is the source of truth for primitive type names used by parsed
  schemas, generated Elixir modules, runtime encoding, and binary schema type
  indexes.
  """

  @binary_schema_atoms [:bool, :byte, :int, :uint, :float, :string, :int64, :uint64]
  @binary_schema_names Enum.map(@binary_schema_atoms, &Atom.to_string/1)
  @name_to_atom Map.new(Enum.zip(@binary_schema_names, @binary_schema_atoms))

  @type name :: String.t()
  @type atom_name :: atom()

  @spec name?(term()) :: boolean()
  def name?(name) when is_binary(name), do: Map.has_key?(name_to_atom(), name)
  def name?(_name), do: false

  @spec atom?(term()) :: boolean()
  def atom?(name) when is_atom(name), do: name in atoms()
  def atom?(_name), do: false

  @spec to_atom!(name()) :: atom_name()
  def to_atom!(name) when is_binary(name), do: Map.fetch!(name_to_atom(), name)

  @spec binary_schema_index(name() | nil) :: non_neg_integer() | nil
  def binary_schema_index(nil), do: nil

  def binary_schema_index(name) when is_binary(name) do
    Enum.find_index(names(), &(&1 == name))
  end

  @spec binary_schema_name!(non_neg_integer()) :: name()
  def binary_schema_name!(index), do: Enum.fetch!(names(), index)

  @spec names() :: [name()]
  def names, do: @binary_schema_names

  @spec atoms() :: [atom_name()]
  def atoms, do: @binary_schema_atoms

  defp name_to_atom, do: @name_to_atom
end
