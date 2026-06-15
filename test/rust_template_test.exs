defmodule KiwiCodec.RustTemplateTest do
  use ExUnit.Case, async: true

  test "renders RustQ item splice markers" do
    dir =
      Path.join(
        System.tmp_dir!(),
        "kiwi-rust-template-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    template = Path.join(dir, "template.rs")
    out = Path.join(dir, "generated.rs")

    File.write!(template, """
    mod generated {
        __rq_items!();
    }
    """)

    KiwiCodec.RustTemplate.render!(
      template,
      out,
      [
        {:items, "pub fn generated() -> i32 { 1 }"}
      ]
    )

    generated = File.read!(out)

    assert generated =~ "pub fn generated() -> i32"
    refute generated =~ "__rq_items"
  end

  test "renders RustQ template includes relative to the template" do
    dir =
      Path.join(
        System.tmp_dir!(),
        "kiwi-rust-template-include-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(dir, "partials"))
    on_exit(fn -> File.rm_rf(dir) end)

    template = Path.join(dir, "template.rs")
    partial = Path.join(dir, "partials/items.rs")
    out = Path.join(dir, "generated.rs")

    File.write!(partial, "pub fn included() -> i32 { 1 }")
    File.write!(template, "mod generated { __rq_include!(\"partials/items.rs\"); }")

    KiwiCodec.RustTemplate.render!(template, out, [])

    generated = File.read!(out)

    assert generated =~ "pub fn included() -> i32"
    refute generated =~ "__rq_include"
  end
end
