defmodule KiwiCodec.RustTemplate do
  @moduledoc """
  Renders RustQ-native Rust templates with generated Rust snippets.

  Templates are valid Rust files. Mark dynamic item regions with RustQ splice
  placeholders such as `__rq_definitions!();`, then provide replacements keyed
  by the splice name, for example `{:definitions, code}`.
  """

  @type replacement :: {atom(), String.t() | [String.t()]}

  @doc """
  Renders `template` to `out` using `replacements`.
  """
  @spec render!(Path.t(), Path.t(), [replacement()], keyword()) :: Path.t()
  def render!(template, out, replacements, opts \\ []) do
    rendered = render_source!(template, replacements, opts)

    File.mkdir_p!(Path.dirname(out))
    File.write!(out, rendered)

    out
  end

  @doc """
  Renders `template` with `replacements` and returns the generated Rust source.
  """
  @spec render_source!(Path.t(), [replacement()], keyword()) :: String.t()
  def render_source!(template, replacements, opts \\ []) do
    template
    |> File.read!()
    |> RustQ.render!(Keyword.get(opts, :filename, template),
      include_dir: Keyword.get(opts, :include_dir, Path.dirname(template)),
      splice: splices(replacements)
    )
  end

  defp splices(replacements) do
    Enum.map(replacements, fn {name, code} when is_atom(name) -> {name, List.wrap(code)} end)
  end
end
