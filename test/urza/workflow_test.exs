defmodule Urza.WorkflowTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Urza.Repo

  import Mox
  import Urza.Test.Fixtures

  alias Urza.Workflow
  alias Urza.AI.LLMAdapterMock
  alias Urza.Tools.{Calculator, Echo, Wait}

  @model "google:gemini-2.5-flash"

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup tags do
    Urza.DataCase.setup_sandbox(tags)
    :ok
  end

  describe "workflow execution" do
    test "executes a simple single job workflow" do
      workflow_id = "test_simple_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)

      work = [
        %{
          tool: Calculator,
          args: %{"l" => {:const, 1}, "r" => {:const, 2}, "op" => {:const, "add"}},
          ref: "$1",
          deps: []
        }
      ]

      {:ok, _pid} = Workflow.start_link({workflow_id, work, %{}})

      # Wait for job to be queued then drain
      Process.sleep(100)
      Oban.drain_queue(queue: :math)

      assert_receive {_job_id, %{"$1" => 3}}, 1000
    end

    test "executes chained jobs with dependencies" do
      workflow_id = "test_chain_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)

      work = [
        %{
          tool: Calculator,
          args: %{"l" => {:const, 10}, "r" => {:const, 20}, "op" => {:const, "add"}},
          ref: "$1",
          deps: []
        },
        %{
          tool: Calculator,
          args: %{"l" => {:const, 5}, "r" => {:const, 3}, "op" => {:const, "add"}},
          ref: "$2",
          deps: []
        },
        %{
          tool: Calculator,
          args: %{
            "l" => {:dyn, "$1"},
            "r" => {:dyn, "$2"},
            "op" => {:const, "multiply"}
          },
          ref: "$3",
          deps: ["$1", "$2"]
        }
      ]

      {:ok, _pid} = Workflow.start_link({workflow_id, work, %{}})

      # Wait for initial jobs to be queued
      Process.sleep(100)

      # First batch: $1 and $2 (no deps)
      Oban.drain_queue(queue: :math)

      # Collect first two results
      result1 =
        receive do
          {_jid, %{"$1" => v}} -> v
        after
          500 -> nil
        end

      result2 =
        receive do
          {_jid, %{"$2" => v}} -> v
        after
          500 -> nil
        end

      assert result1 == 30
      assert result2 == 8

      # Second batch: $3 (deps on $1 and $2)
      Oban.drain_queue(queue: :math)

      assert_receive {_job_id_3, %{"$3" => 240}}, 1000
    end

    test "executes fan-out and fan-in pattern" do
      workflow_id = "test_fan_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)

      work = [
        %{
          tool: Wait,
          args: %{},
          ref: "$1",
          deps: []
        },
        %{
          tool: Wait,
          args: %{},
          ref: "$2",
          deps: []
        },
        %{
          tool: Echo,
          args: %{"content" => {:const, "fan-in complete"}},
          ref: "$3",
          deps: ["$1", "$2"]
        }
      ]

      {:ok, _pid} = Workflow.start_link({workflow_id, work, %{}})

      Process.sleep(100)

      # First batch: both Wait jobs (default queue)
      Oban.drain_queue(queue: :default)

      # Collect wait results
      results =
        1..2
        |> Enum.map(fn _ ->
          receive do
            {_job_id, result} -> result
          after
            500 -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      assert length(results) == 2
      assert Enum.all?(results, fn r -> Map.values(r) == ["sleeep!"] end)

      # Give workflow time to process Wait results and queue Echo job
      Process.sleep(200)

      # Second batch: Echo job (default queue)
      Oban.drain_queue(queue: :default)

      # Echo tool publishes empty map since it doesn't have a ref in its meta
      assert_receive {_job_id_3, %{}}, 1000
    end

    test "executes jobs concurrently when no dependencies" do
      workflow_id = "test_concurrent_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)

      work = [
        %{
          tool: Calculator,
          args: %{"l" => {:const, 1}, "r" => {:const, 1}, "op" => {:const, "add"}},
          ref: "$1",
          deps: []
        },
        %{
          tool: Calculator,
          args: %{"l" => {:const, 2}, "r" => {:const, 2}, "op" => {:const, "add"}},
          ref: "$2",
          deps: []
        },
        %{
          tool: Calculator,
          args: %{"l" => {:const, 3}, "r" => {:const, 3}, "op" => {:const, "add"}},
          ref: "$3",
          deps: []
        }
      ]

      {:ok, _pid} = Workflow.start_link({workflow_id, work, %{}})

      Process.sleep(100)
      Oban.drain_queue(queue: :math)

      results =
        1..3
        |> Enum.map(fn _ ->
          receive do
            {_job_id, result} -> Map.values(result) |> List.first()
          after
            500 -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      assert length(results) == 3
      assert 2 in results
      assert 4 in results
      assert 6 in results
    end
  end

  describe "dynamic job addition" do
    test "can add jobs to a running workflow" do
      workflow_id = "test_add_job_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)

      initial_work = [
        %{
          tool: Calculator,
          args: %{"l" => {:const, 5}, "r" => {:const, 5}, "op" => {:const, "add"}},
          ref: "$1",
          deps: []
        }
      ]

      {:ok, _pid} = Workflow.start_link({workflow_id, initial_work, %{}})

      Process.sleep(100)
      Oban.drain_queue(queue: :math)

      assert_receive {_job_id_1, %{"$1" => 10}}, 1000

      Workflow.add_job(workflow_id, %{
        tool: Calculator,
        args: %{"l" => {:const, 10}, "r" => {:const, 5}, "op" => {:const, "add"}},
        ref: "$2",
        deps: []
      })

      Process.sleep(100)
      Oban.drain_queue(queue: :math)

      assert_receive {_job_id_2, %{"$2" => 15}}, 1000
    end

    test "can add jobs that depend on existing refs" do
      workflow_id = "test_add_dependent_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)

      initial_work = [
        %{
          tool: Calculator,
          args: %{"l" => {:const, 5}, "r" => {:const, 5}, "op" => {:const, "add"}},
          ref: "$base",
          deps: []
        }
      ]

      {:ok, _pid} = Workflow.start_link({workflow_id, initial_work, %{}})

      Process.sleep(100)
      Oban.drain_queue(queue: :math)

      assert_receive {_job_id_1, %{"$base" => 10}}, 1000

      Workflow.add_job(workflow_id, %{
        tool: Calculator,
        args: %{
          "l" => {:dyn, "$base"},
          "r" => {:const, 2},
          "op" => {:const, "multiply"}
        },
        ref: "$result",
        deps: ["$base"]
      })

      Process.sleep(100)
      Oban.drain_queue(queue: :math)

      assert_receive {_job_id_2, %{"$result" => 20}}, 1000
    end
  end

  describe "dynamic value passing" do
    test "passes dynamic values between jobs using refs" do
      workflow_id = "test_dynamic_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)

      work = [
        %{
          tool: Calculator,
          args: %{"l" => {:const, 100}, "r" => {:const, 50}, "op" => {:const, "add"}},
          ref: "$sum",
          deps: []
        },
        %{
          tool: Calculator,
          args: %{
            "l" => {:dyn, "$sum"},
            "r" => {:const, 2},
            "op" => {:const, "divide"}
          },
          ref: "$half",
          deps: ["$sum"]
        }
      ]

      {:ok, _pid} = Workflow.start_link({workflow_id, work, %{}})

      Process.sleep(100)
      Oban.drain_queue(queue: :math)

      assert_receive {_job_id_1, %{"$sum" => 150}}, 1000

      Process.sleep(100)
      Oban.drain_queue(queue: :math)

      assert_receive {_job_id_2, %{"$half" => 75.0}}, 1000
    end

    test "handles multiple dynamic dependencies" do
      workflow_id = "test_multi_dyn_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)

      work = [
        %{
          tool: Calculator,
          args: %{"l" => {:const, 10}, "r" => {:const, 5}, "op" => {:const, "add"}},
          ref: "$a",
          deps: []
        },
        %{
          tool: Calculator,
          args: %{"l" => {:const, 20}, "r" => {:const, 10}, "op" => {:const, "add"}},
          ref: "$b",
          deps: []
        },
        %{
          tool: Calculator,
          args: %{
            "l" => {:dyn, "$a"},
            "r" => {:dyn, "$b"},
            "op" => {:const, "add"}
          },
          ref: "$c",
          deps: ["$a", "$b"]
        }
      ]

      {:ok, _pid} = Workflow.start_link({workflow_id, work, %{}})

      Process.sleep(100)
      Oban.drain_queue(queue: :math)

      results =
        1..2
        |> Enum.map(fn _ ->
          receive do
            {_job_id, result} -> Map.values(result) |> List.first()
          after
            500 -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      assert 15 in results
      assert 30 in results

      Process.sleep(100)
      Oban.drain_queue(queue: :math)

      assert_receive {_job_id_3, %{"$c" => 45}}, 1000
    end
  end

  describe "README demo workflows" do
    test "test_chaining workflow executes correctly" do
      workflow_id = "test_chaining_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)

      w = Urza.Workflow.test_chaining()
      {:ok, _pid} = Workflow.start_link({workflow_id, w.work, %{}})

      Process.sleep(100)

      Oban.drain_queue(queue: :math)

      results =
        1..2
        |> Enum.map(fn _ ->
          receive do
            {_job_id, result} -> Map.values(result) |> List.first()
          after
            500 -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      assert 3 in results

      Process.sleep(100)
      Oban.drain_queue(queue: :math)

      assert_receive {_job_id, %{}}, 1000
    end

    test "test_fan workflow executes fan-out/fan-in correctly" do
      workflow_id = "test_fan_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)

      w = Urza.Workflow.test_fan()
      {:ok, _pid} = Workflow.start_link({workflow_id, w.work, %{}})

      Process.sleep(100)

      Oban.drain_queue(queue: :default)

      results =
        1..2
        |> Enum.map(fn _ ->
          receive do
            {_job_id, result} -> Map.values(result) |> List.first()
          after
            500 -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      assert length(results) == 2
      assert Enum.all?(results, fn r -> r == "sleeep!" end)

      Process.sleep(100)
      Oban.drain_queue(queue: :default)

      assert_receive {_job_id, %{}}, 1000
    end

    test "test_branch with true condition executes true branch" do
      workflow_id = "test_branch_true_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)

      w = Urza.Workflow.test_branch(workflow_id, true)
      {:ok, _pid} = Workflow.start_link({workflow_id, w.work, %{}})

      Process.sleep(100)

      Oban.drain_queue(queue: :default)

      assert_receive {:branch, _job_id, ["$1"]}, 1000

      Process.sleep(100)
      Oban.drain_queue(queue: :default)

      assert_receive {_job_id, %{}}, 1000
    end

    test "test_branch with false condition executes false branch" do
      workflow_id = "test_branch_false_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)

      w = Urza.Workflow.test_branch(workflow_id, false)
      {:ok, _pid} = Workflow.start_link({workflow_id, w.work, %{}})

      Process.sleep(100)

      Oban.drain_queue(queue: :default)

      assert_receive {:branch, _job_id, ["$2"]}, 1000

      Process.sleep(100)
      Oban.drain_queue(queue: :default)

      assert_receive {_job_id, %{}}, 1000
    end

    test "test_human_checkpoint workflow with approval" do
      workflow_id = "test_human_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)
      Phoenix.PubSub.subscribe(Urza.PubSub, "notification")

      w = Urza.Workflow.test_human_checkpoint()
      {:ok, _pid} = Workflow.start_link({workflow_id, w.work, %{}})

      Process.sleep(100)

      Oban.drain_queue(queue: :default)

      assert_receive {_msg, job_id}, 1000

      Urza.Tools.HumanCheckpoint.approve(job_id)

      Process.sleep(100)
      Oban.drain_queue(queue: :default)

      assert_receive {_job_id, %{"$1" => "accepted"}}, 1000

      Process.sleep(100)
      Oban.drain_queue(queue: :default)

      assert_receive {_job_id, %{}}, 1000
    end

    test "test_human_checkpoint workflow with rejection" do
      workflow_id = "test_human_reject_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)
      Phoenix.PubSub.subscribe(Urza.PubSub, "notification")

      w = Urza.Workflow.test_human_checkpoint()
      {:ok, _pid} = Workflow.start_link({workflow_id, w.work, %{}})

      Process.sleep(100)

      Oban.drain_queue(queue: :default)

      assert_receive {_msg, job_id}, 1000

      Urza.Tools.HumanCheckpoint.deny(job_id)

      Process.sleep(100)
      Oban.drain_queue(queue: :default)

      assert_receive {_job_id, %{"$1" => "rejected"}}, 1000

      Process.sleep(100)
      Oban.drain_queue(queue: :default)

      assert_receive {_job_id, %{}}, 1000
    end

    test "test_agent workflow executes agent and echoes result" do
      workflow_id = "test_agent_#{System.unique_integer()}"
      agent_id = "agent_007_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, "agent:#{agent_id}:logs")

      expect(LLMAdapterMock, :generate_text, fn @model, messages ->
        assert length(messages) == 2
        [system_msg, user_msg] = messages
        user_content = extract_message_content(user_msg)
        assert String.contains?(user_content, "add 33,27")

        {:ok,
         mock_llm_response(~s({"tool": "calculator", "args": {"l": 33, "r": 27, "op": "add"}}))}
      end)

      expect(LLMAdapterMock, :generate_text, fn @model, messages ->
        assert length(messages) == 4

        assert Enum.any?(messages, fn msg ->
                 content = extract_message_content(msg)
                 String.contains?(content, "executing calculator")
               end)

        {:ok, mock_llm_response(~s({"answer": "The sum of 33 and 27 is 60", "confidence": 10}))}
      end)

      work = [
        %{
          agent: agent_id,
          tools: ["calculator", "echo"],
          goal: "add 33,27 and then print it",
          ref: "$agent_007",
          deps: []
        },
        %{
          tool: Echo,
          args: %{"content" => {:dyn, "$agent_007"}},
          ref: nil,
          deps: ["$agent_007"]
        }
      ]

      {:ok, pid} = Workflow.start_link({workflow_id, work, %{}})

      Process.sleep(100)

      assert_receive {:ai_thinking, ^agent_id}

      assert_receive {:tool_started, ^agent_id, "calculator",
                      %{"l" => 33, "r" => 27, "op" => "add"}}

      # Let Oban execute the calculator job
      Oban.drain_queue(queue: :math)

      # Manually send tool result to agent (in real deployment, workflow would forward this)
      Urza.AI.Agent.send_tool_result(agent_id, "60")

      assert_receive {:ai_thinking, ^agent_id}
      assert_receive {:agent_completed, ^agent_id, result}
      assert result["answer"] == "The sum of 33 and 27 is 60"
      assert result["confidence"] == 10

      # Wait for workflow to process agent completion and queue Echo job
      Process.sleep(200)

      # Execute the Echo job that depends on agent result
      Oban.drain_queue(queue: :default)

      # Verify workflow is still alive after completion
      assert Process.alive?(pid)
    end
  end

  describe "edge cases" do
    test "handles jobs without refs (nil ref)" do
      workflow_id = "test_nil_ref_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)

      work = [
        %{
          tool: Calculator,
          args: %{"l" => {:const, 5}, "r" => {:const, 5}, "op" => {:const, "add"}},
          ref: nil,
          deps: []
        },
        %{
          tool: Calculator,
          args: %{"l" => {:const, 10}, "r" => {:const, 10}, "op" => {:const, "add"}},
          ref: nil,
          deps: []
        }
      ]

      {:ok, _pid} = Workflow.start_link({workflow_id, work, %{}})

      Process.sleep(100)
      Oban.drain_queue(queue: :math)

      results =
        1..2
        |> Enum.map(fn _ ->
          receive do
            {_job_id, result} -> result
          after
            500 -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      assert length(results) == 2
    end

    test "handles empty deps list correctly" do
      workflow_id = "test_empty_deps_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)

      work = [
        %{
          tool: Calculator,
          args: %{"l" => {:const, 1}, "r" => {:const, 1}, "op" => {:const, "add"}},
          ref: "$1",
          deps: []
        }
      ]

      {:ok, _pid} = Workflow.start_link({workflow_id, work, %{}})

      Process.sleep(100)
      Oban.drain_queue(queue: :math)

      assert_receive {_job_id, %{"$1" => 2}}, 1000
    end

    test "jobs with same deps execute after dependency completes" do
      workflow_id = "test_shared_deps_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)

      work = [
        %{
          tool: Calculator,
          args: %{"l" => {:const, 10}, "r" => {:const, 10}, "op" => {:const, "add"}},
          ref: "$base",
          deps: []
        },
        %{
          tool: Calculator,
          args: %{
            "l" => {:dyn, "$base"},
            "r" => {:const, 1},
            "op" => {:const, "add"}
          },
          ref: "$a",
          deps: ["$base"]
        },
        %{
          tool: Calculator,
          args: %{
            "l" => {:dyn, "$base"},
            "r" => {:const, 2},
            "op" => {:const, "add"}
          },
          ref: "$b",
          deps: ["$base"]
        }
      ]

      {:ok, _pid} = Workflow.start_link({workflow_id, work, %{}})

      Process.sleep(100)
      Oban.drain_queue(queue: :math)

      assert_receive {_job_id_1, %{"$base" => 20}}, 1000

      Process.sleep(100)
      Oban.drain_queue(queue: :math)

      results =
        1..2
        |> Enum.map(fn _ ->
          receive do
            {_job_id, result} -> Map.values(result) |> List.first()
          after
            500 -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      assert 21 in results
      assert 22 in results
    end

    test "workflow process stays alive after completion" do
      workflow_id = "test_completion_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)

      work = [
        %{
          tool: Calculator,
          args: %{"l" => {:const, 1}, "r" => {:const, 1}, "op" => {:const, "add"}},
          ref: "$1",
          deps: []
        }
      ]

      {:ok, pid} = Workflow.start_link({workflow_id, work, %{}})

      Process.sleep(100)
      Oban.drain_queue(queue: :math)

      assert_receive {_job_id, %{"$1" => 2}}, 1000

      Process.sleep(100)
      assert Process.alive?(pid)
    end
  end

  describe "new tools integration" do
    alias Urza.Tools.{Lua, Web}

    test "executes Lua script in workflow" do
      workflow_id = "test_lua_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)

      work = [
        %{
          tool: Lua,
          args: %{
            "script" => {:const, "return 10 + 20"},
            "input" => {:const, %{}}
          },
          ref: "$lua_result",
          deps: []
        }
      ]

      {:ok, _pid} = Workflow.start_link({workflow_id, work, %{}})

      Process.sleep(100)
      Oban.drain_queue(queue: :script)

      assert_receive {_job_id, %{"$lua_result" => 30}}, 1000
    end

    test "executes Lua script with input variables" do
      workflow_id = "test_lua_input_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)

      work = [
        %{
          tool: Lua,
          args: %{
            "script" => {:const, "return x * y"},
            "input" => {:const, %{"x" => 5, "y" => 6}}
          },
          ref: "$lua_result",
          deps: []
        }
      ]

      {:ok, _pid} = Workflow.start_link({workflow_id, work, %{}})

      Process.sleep(100)
      Oban.drain_queue(queue: :script)

      assert_receive {_job_id, %{"$lua_result" => 30}}, 1000
    end

    test "Lua tool executes after Calculator in workflow" do
      workflow_id = "test_lua_after_calc_#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Urza.PubSub, workflow_id)

      work = [
        %{
          tool: Calculator,
          args: %{
            "l" => {:const, 100},
            "r" => {:const, 50},
            "op" => {:const, "add"}
          },
          ref: "$calc_result",
          deps: []
        },
        %{
          tool: Lua,
          args: %{
            "script" => {:const, "return 150 * 2"},
            "input" => {:const, %{}}
          },
          ref: "$lua_result",
          deps: ["$calc_result"]
        }
      ]

      {:ok, _pid} = Workflow.start_link({workflow_id, work, %{}})

      Process.sleep(100)
      Oban.drain_queue(queue: :math)

      assert_receive {_job_id_1, %{"$calc_result" => 150}}, 1000

      Process.sleep(100)
      Oban.drain_queue(queue: :script)

      assert_receive {_job_id_2, %{"$lua_result" => 300}}, 1000
    end
  end
end
