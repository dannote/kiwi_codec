defmodule KiwiCodec.MetadataTest do
  use ExUnit.Case, async: true

  defmodule Node do
    use KiwiCodec, kind: :message

    field(:session_id, 1, type: :uint, source_name: "sessionID")
  end

  test "field metadata preserves source schema names" do
    field = Node.__kiwi_props__().fields_by_name.session_id

    assert field.name == :session_id
    assert field.source_name == "sessionID"
  end
end
