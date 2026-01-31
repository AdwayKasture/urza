defmodule Urza.Tools.WebTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Urza.Repo

  alias Urza.Tools.Web

  setup tags do
    Urza.DataCase.setup_sandbox(tags)
    :ok
  end

  describe "run/1" do
    test "returns error when url is missing" do
      assert {:error, "Missing required parameters: url and method"} = Web.run(%{})
    end

    test "returns error when method is missing" do
      assert {:error, "Missing required parameters: url and method"} =
               Web.run(%{"url" => "http://example.com"})
    end

    test "returns error for invalid HTTP method" do
      result = Web.run(%{"url" => "http://example.com", "method" => "INVALID"})
      assert {:error, reason} = result
      assert String.contains?(reason, "Invalid HTTP method")
    end

    test "parameter_schema returns expected structure" do
      schema = Web.parameter_schema()

      assert Keyword.has_key?(schema, :url)
      assert Keyword.has_key?(schema, :method)
      assert Keyword.has_key?(schema, :headers)
      assert Keyword.has_key?(schema, :body)

      assert schema[:url][:type] == :string
      assert schema[:url][:required] == true
      assert schema[:method][:type] == :string
      assert schema[:method][:required] == true
      assert schema[:headers][:type] == :map
      assert schema[:headers][:required] == false
      assert schema[:body][:type] == :string
      assert schema[:body][:required] == false
    end

    test "return_schema returns expected structure" do
      schema = Web.return_schema()
      assert schema[:type] == :map
      assert schema[:required] == true
    end

    test "name returns 'web'" do
      assert Web.name() == "web"
    end

    test "description returns expected string" do
      assert Web.description() ==
               "Makes HTTP requests (GET, POST, PUT, DELETE) to fetch or send data"
    end
  end

  describe "Oban Worker" do
    test "enqueues job with correct queue" do
      changeset =
        Web.new(%{"url" => "http://example.com", "method" => "GET"},
          meta: %{"ref" => "test", "workflow_id" => "wf1"}
        )

      job = Ecto.Changeset.apply_changes(changeset)

      assert job.queue == "web"
      assert job.max_attempts == 2
      assert job.args == %{"url" => "http://example.com", "method" => "GET"}
    end
  end
end
