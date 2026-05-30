defmodule KiwiCodec.RustTemplateTest do
  use ExUnit.Case, async: true

  test "replaces item, statement, and expression macro markers" do
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
        kiwi_codegen::items!();
    }

    fn answer() -> i32 {
        kiwi_codegen::statements!();
        kiwi_codegen::expr!()
    }
    """)

    KiwiCodec.RustTemplate.render!(
      template,
      out,
      [
        {"kiwi_codegen::items", "pub fn generated() -> i32 { 1 }"},
        {"kiwi_codegen::statements", "let base = 40;\nlet extra = 2;"},
        {"kiwi_codegen::expr", "base + extra"}
      ]
    )

    generated = File.read!(out)

    assert generated =~ "pub fn generated() -> i32"
    assert generated =~ "let base = 40;"
    assert generated =~ "base + extra"
    refute generated =~ "kiwi_codegen"
  end
end
