defmodule Urza.Tools.Context do
  @enforce_keys :id
  defstruct [
    :id,                   # workflow or orchestration id
    work: [],              # tuple of tool and map args to execute {Echo,%{content: "hello"}}
    executing_job: nil,    # current executing Oban Job Id 
    acc: %{}               # map of all references / variables
  ]
  
end
