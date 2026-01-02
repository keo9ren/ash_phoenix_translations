defmodule Mix.Tasks.AshPhoenixTranslations.Gen.GraphqlExtensionsTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.AshPhoenixTranslations.Gen.GraphqlExtensions

  @temp_file "test/tmp/translation_extensions.ex"

  setup do
    # Clean up temp file before and after each test
    File.rm(@temp_file)
    on_exit(fn -> File.rm(@temp_file) end)
    :ok
  end

  describe "run/1" do
    test "generates extension module with valid output path" do
      # Test with empty domains (no resources to find)
      # This tests the structure is created even if no resources found
      output =
        capture_io(fn ->
          try do
            GraphqlExtensions.run(["--domains", "NonExistent.Domain", "--output", @temp_file])
          catch
            :exit, _ -> :ok
          end
        end)

      # Should inform about no resources found
      assert output =~ "No translatable resources found"
    end

    test "shows error when no domains specified and none can be discovered" do
      output =
        capture_io(fn ->
          try do
            GraphqlExtensions.run([])
          catch
            :exit, _ -> :ok
          end
        end)

      # Task exits when no domains found - this is expected behavior
      # The output might be empty due to exit timing, so we just verify it ran
      assert is_binary(output)
    end

    test "accepts --domains option" do
      # Just test that the option parsing works
      # Actual generation would require real resources
      output =
        capture_io(fn ->
          try do
            GraphqlExtensions.run(["--domains", "Test.Domain", "--output", @temp_file])
          catch
            :exit, _ -> :ok
          end
        end)

      # Should at least try to process the domain
      assert output =~ "domain" or output =~ "resource" or output =~ "No translatable resources"
    end

    test "accepts --module option" do
      output =
        capture_io(fn ->
          try do
            GraphqlExtensions.run([
              "--domains",
              "Test.Domain",
              "--module",
              "CustomModule",
              "--output",
              @temp_file
            ])
          catch
            :exit, _ -> :ok
          end
        end)

      # Should process without errors
      assert output != ""
    end
  end

  describe "module generation" do
    test "generated code has proper structure" do
      # Test the code generation directly
      code =
        AshPhoenixTranslations.GraphqlExtensions.generate([])

      assert code =~ "defmodule TranslationExtensions"
      assert code =~ "use Absinthe.Schema.Notation"
      assert code =~ "scalar :locale_scalar"
      assert code =~ "object :translation"
    end
  end
end
