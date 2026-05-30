defmodule KiwiCodec.RustTemplate do
  @moduledoc """
  Renders Rust templates by replacing marker macro invocations with Rust snippets.

  Templates are valid Rust files. Mark dynamic regions with macros such as
  `kiwi_codegen::items!()` or `kiwi_codegen::expr!()`, then provide replacements
  keyed by the macro path. The helper parses the template with `syn`, replaces
  matching macro AST nodes, and formats the result with `prettyplease`.
  """

  @type replacement :: {String.t(), String.t()} | {atom(), String.t()}

  @doc """
  Renders `template` to `out` using `replacements`.

  Replacement keys are macro paths without `!`, for example
  `"kiwi_codegen::items"`. Values must be valid Rust for the marker position:
  item markers expect Rust items, statement markers expect Rust statements, and
  expression markers expect a Rust expression.
  """
  @spec render!(Path.t(), Path.t(), [replacement()], keyword()) :: Path.t()
  def render!(template, out, replacements, opts \\ []) do
    temp_dir = Keyword.get_lazy(opts, :tmp_dir, &make_tmp_dir!/0)

    try do
      manifest_path = Keyword.get(opts, :manifest_path, default_manifest_path())
      cargo = Keyword.get(opts, :cargo, System.get_env("CARGO") || "cargo")
      replacements_path = Path.join(temp_dir, "replacements.json")

      File.mkdir_p!(Path.dirname(out))
      File.write!(replacements_path, encode_replacements!(replacements))

      args = [
        "run",
        "--quiet",
        "--manifest-path",
        manifest_path,
        "--",
        template,
        replacements_path,
        out
      ]

      case System.cmd(cargo, args, stderr_to_stdout: true) do
        {_output, 0} ->
          out

        {output, status} ->
          raise "rust template patcher failed with status #{status}:\n#{output}"
      end
    after
      if Keyword.get(opts, :tmp_dir) == nil and is_binary(temp_dir) do
        File.rm_rf(temp_dir)
      end
    end
  end

  defp encode_replacements!(replacements) do
    json_array =
      Enum.map_join(replacements, ",", fn {marker, code} ->
        marker = marker |> to_string() |> String.trim_trailing("!")
        encode_object!(%{marker: marker, code: code})
      end)

    "{\"replacements\":[#{json_array}]}"
  end

  defp encode_object!(%{marker: marker, code: code}) do
    "{\"marker\":#{json_string!(marker)},\"code\":#{json_string!(code)}}"
  end

  defp json_string!(value) do
    value
    |> to_string()
    |> then(&:unicode.characters_to_binary(&1, :utf8))
    |> escape_json()
  end

  defp escape_json(value) do
    escaped =
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")
      |> String.replace("\r", "\\r")
      |> String.replace("\t", "\\t")

    "\"#{escaped}\""
  end

  defp default_manifest_path do
    __ENV__.file
    |> Path.dirname()
    |> Path.join("../../priv/rust_template_patch/Cargo.toml")
    |> Path.expand()
  end

  defp make_tmp_dir! do
    path =
      Path.join(System.tmp_dir!(), "kiwi-rust-template-#{System.unique_integer([:positive])}")

    File.mkdir_p!(path)
    path
  end
end
