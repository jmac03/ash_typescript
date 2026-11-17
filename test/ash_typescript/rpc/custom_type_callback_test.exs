# SPDX-FileCopyrightText: 2026 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.CustomTypeCallbackTest do
  use ExUnit.Case, async: false

  alias Ash.Info.Manifest.Generator.TypeResolver
  alias AshTypescript.Codegen.SchemaCore
  alias AshTypescript.Codegen.ValibotSchemaGenerator
  alias AshTypescript.Codegen.ZodSchemaGenerator

  defmodule Identifier do
    @moduledoc false
    use Ash.Type

    @impl true
    def storage_type(_), do: :integer
    @impl true
    def cast_input(value, _), do: {:ok, value}
    @impl true
    def cast_stored(value, _), do: {:ok, value}
    @impl true
    def dump_to_native(value, _), do: {:ok, value}

    def typescript_type_name, do: "Identifier"
    def typescript_format_type(ZodSchemaGenerator), do: "z.string()"
    def typescript_format_type(ValibotSchemaGenerator), do: "v.string()"
  end

  defmodule OpaqueIdentifier do
    @moduledoc false
    use Ash.Type

    @impl true
    def storage_type(_), do: :unmappable_identifier
    @impl true
    defdelegate cast_input(value, constraints), to: Identifier
    @impl true
    defdelegate cast_stored(value, constraints), to: Identifier
    @impl true
    defdelegate dump_to_native(value, constraints), to: Identifier

    def typescript_type_name, do: "OpaqueIdentifier"
    defdelegate typescript_format_type(formatter), to: Identifier
  end

  setup do
    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([
      :zod_mapping_overrides,
      :valibot_mapping_overrides
    ])

    Application.put_env(:ash_typescript, :zod_mapping_overrides, [])
    Application.put_env(:ash_typescript, :valibot_mapping_overrides, [])
  end

  test "the callback takes precedence over mappable storage for both formatters" do
    type = TypeResolver.resolve(Identifier, [])

    assert SchemaCore.get_type(ZodSchemaGenerator, type) == "z.string()"
    assert SchemaCore.get_type(ValibotSchemaGenerator, type) == "v.string()"
  end

  test "array items retain the callback schema" do
    type = TypeResolver.resolve({:array, Identifier}, [])

    assert SchemaCore.get_type(ZodSchemaGenerator, type) == "z.array(z.string())"
    assert SchemaCore.get_type(ValibotSchemaGenerator, type) == "v.array(v.string())"
  end

  test "the callback supplies a schema for otherwise unmappable storage" do
    type = TypeResolver.resolve(OpaqueIdentifier, [])

    assert SchemaCore.get_type(ZodSchemaGenerator, type) == "z.string()"
    assert SchemaCore.get_type(ValibotSchemaGenerator, type) == "v.string()"
  end

  @tag :tmp_dir
  test "an initially unloaded type uses its callback on the first call", %{tmp_dir: directory} do
    module = __MODULE__.InitiallyUnloadedIdentifier

    compiled =
      Code.compile_string("""
      defmodule #{inspect(module)} do
        use Ash.Type
        def storage_type(_), do: :integer
        def cast_input(v, _), do: {:ok, v}
        def cast_stored(v, _), do: {:ok, v}
        def dump_to_native(v, _), do: {:ok, v}
        def typescript_type_name, do: "InitiallyUnloadedIdentifier"
        def typescript_format_type(#{inspect(ZodSchemaGenerator)}), do: "z.string()"
        def typescript_format_type(#{inspect(ValibotSchemaGenerator)}), do: "v.string()"
      end
      """)

    on_exit(fn ->
      Enum.each(compiled, fn {compiled_module, _} ->
        :code.purge(compiled_module)
        :code.delete(compiled_module)
      end)

      Code.delete_path(directory)
    end)

    Enum.each(compiled, fn {compiled_module, beam} ->
      File.write!(Path.join(directory, "#{compiled_module}.beam"), beam)
    end)

    Code.prepend_path(directory)
    type = TypeResolver.resolve(module, [])

    for formatter <- [ZodSchemaGenerator, ValibotSchemaGenerator] do
      :code.purge(module)
      :code.delete(module)
      assert :code.is_loaded(module) == false

      expected = if formatter == ZodSchemaGenerator, do: "z.string()", else: "v.string()"
      assert SchemaCore.get_type(formatter, type) == expected
    end
  end

  test "config overrides precede callbacks independently for each formatter" do
    type = TypeResolver.resolve(Identifier, [])

    Application.put_env(:ash_typescript, :zod_mapping_overrides, [{Identifier, "z.boolean()"}])

    assert SchemaCore.get_type(ZodSchemaGenerator, type) == "z.boolean()"
    assert SchemaCore.get_type(ValibotSchemaGenerator, type) == "v.string()"

    Application.put_env(:ash_typescript, :zod_mapping_overrides, [])

    Application.put_env(:ash_typescript, :valibot_mapping_overrides, [{Identifier, "v.boolean()"}])

    assert SchemaCore.get_type(ZodSchemaGenerator, type) == "z.string()"
    assert SchemaCore.get_type(ValibotSchemaGenerator, type) == "v.boolean()"
  end
end
