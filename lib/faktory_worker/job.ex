defmodule FaktoryWorker.Job do
  @moduledoc """
  todo: docs
  """

  alias FaktoryWorker.Random

  # Look at supporting the following optional fields when pushing a job
  # priority
  # at
  # backtrace
  # created_at
  @optional_job_fields [:queue, :custom, :retry, :reserve_for]

  @default_worker_config [
    retry: 25,
    reserve_for: 1800
  ]

  defmacro __using__(using_opts \\ []) do
    alias FaktoryWorker.Job

    using_opts = Keyword.merge(@default_worker_config, using_opts)

    quote do
      def worker_config(), do: unquote(using_opts)

      def perform_async(job, opts \\ []) do
        opts = Keyword.merge(unquote(using_opts), opts)

        case Job.encode_job(job) do
          {:ok, job} ->
            __MODULE__
            |> Job.build_payload(job, opts)
            |> Job.perform_async(opts)

          result ->
            result
        end
      end
    end
  end

  @doc false
  def encode_job(job) when is_list(job) do
    job_args =
      job
      |> Enum.reverse()
      |> Enum.reduce_while([], fn arg, acc ->
        case encode_job_args(arg) do
          {:ok, arg} -> {:cont, [arg | acc]}
          _ -> {:halt, {:error, "Unable to encode job argument '#{inspect(arg)}'"}}
        end
      end)

    case job_args do
      {:error, _} = error -> error
      job_args -> {:ok, job_args}
    end
  end

  def encode_job(job), do: encode_job([job])

  @doc false
  def build_payload(worker_module, job, opts) when is_list(job) do
    %{
      jid: Random.job_id(),
      jobtype: job_type_for_module(worker_module),
      args: job
    }
    |> append_optional_fields(opts)
  end

  @doc false
  def perform_async(payload, opts) do
    opts
    |> push_pipeline_name()
    |> perform_async(payload, opts)
  end

  @doc false
  def perform_async(_, {:error, _} = error, _), do: error

  def perform_async(pipeline_name, payload, _opts) do
    message = %Broadway.Message{
      acknowledger: {FaktoryWorker.PushPipeline.Acknowledger, :push_message, []},
      data: {pipeline_name, payload}
    }

    Broadway.push_messages(pipeline_name, [message])
  end

  defp append_optional_fields(args, opts) do
    Enum.reduce_while(@optional_job_fields, args, fn field, args ->
      case Keyword.get(opts, field) do
        nil ->
          {:cont, args}

        value ->
          if is_valid_field_value?(field, value),
            do: {:cont, Map.put(args, field, value)},
            else: {:halt, {:error, field_error_message(field, value)}}
      end
    end)
  end

  defp is_valid_field_value?(:queue, value), do: is_binary(value)
  defp is_valid_field_value?(:custom, value), do: is_map(value)
  defp is_valid_field_value?(:retry, value), do: is_integer(value)
  defp is_valid_field_value?(:reserve_for, value), do: is_integer(value) and value >= 60

  defp field_error_message(field, value) do
    "The field '#{Atom.to_string(field)}' has an invalid value '#{inspect(value)}'"
  end

  defp push_pipeline_name(opts) do
    opts
    |> Keyword.get(:faktory_name, FaktoryWorker)
    |> FaktoryWorker.PushPipeline.format_pipeline_name()
  end

  defp job_type_for_module(module) do
    module
    |> to_string()
    |> String.trim_leading("Elixir.")
  end

  defp encode_job_args(payload) when is_number(payload), do: {:ok, payload}
  defp encode_job_args(payload) when is_binary(payload), do: {:ok, payload}

  defp encode_job_args(%_{} = payload) do
    payload
    |> Map.from_struct()
    |> encode_job_args()
  end

  defp encode_job_args(payload) do
    Jason.encode(payload)
  end
end
