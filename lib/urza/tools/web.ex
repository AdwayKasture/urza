defmodule Urza.Tools.Web do
  @moduledoc """
  A tool for making HTTP requests using Req.

  Supports GET, POST, PUT, and DELETE methods.
  Designed for AI agents to fetch and send data over HTTP.
  """

  use Urza.Tools.Base, queue: :web, max_attempts: 2

  @impl Urza.Tool
  def name, do: "web"

  @impl Urza.Tool
  def description, do: "Makes HTTP requests (GET, POST, PUT, DELETE) to fetch or send data"

  @impl Urza.Tool
  def run(%{"url" => url, "method" => method} = args) do
    headers = Map.get(args, "headers", %{})
    body = Map.get(args, "body")

    req = Req.new(url: url, headers: headers)

    result =
      case String.upcase(method) do
        "GET" ->
          Req.get(req)

        "POST" ->
          req = if body, do: Req.merge(req, body: body), else: req
          Req.post(req)

        "PUT" ->
          req = if body, do: Req.merge(req, body: body), else: req
          Req.put(req)

        "DELETE" ->
          Req.delete(req)

        invalid ->
          {:error, "Invalid HTTP method: #{invalid}"}
      end

    case result do
      {:ok, %{status: status, body: body, headers: resp_headers}} ->
        response = %{
          "status" => status,
          "body" => body,
          "headers" => format_headers(resp_headers)
        }

        {:ok, response}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  def run(_), do: {:error, "Missing required parameters: url and method"}

  @impl Urza.Tool
  def parameter_schema do
    [
      url: [
        type: :string,
        required: true,
        doc: "The URL to make the HTTP request to"
      ],
      method: [
        type: :string,
        required: true,
        doc: "HTTP method: GET, POST, PUT, or DELETE"
      ],
      headers: [
        type: :map,
        required: false,
        doc: "Optional HTTP headers as a map (e.g., %{\"Authorization\" => \"Bearer token\"})"
      ],
      body: [
        type: :string,
        required: false,
        doc: "Optional request body for POST/PUT requests"
      ]
    ]
  end

  @impl Urza.Tool
  def return_schema do
    [
      type: :map,
      required: true,
      doc: "Response with status, body, and headers"
    ]
  end

  defp format_headers(headers) when is_list(headers) do
    headers
    |> Enum.map(fn {name, values} ->
      value = if is_list(values), do: List.first(values), else: values
      {name, value}
    end)
    |> Enum.into(%{})
  end

  defp format_headers(headers) when is_map(headers), do: headers
  defp format_headers(_), do: %{}
end
