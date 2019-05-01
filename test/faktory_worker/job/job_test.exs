defmodule FaktoryWorker.Job.JobTest do
  use ExUnit.Case, async: true

  alias FaktoryWorker.Job

  defmodule TestWorker do
    use FaktoryWorker.Job,
      queue: "test_queue",
      concurrency: 10

    def perform(_), do: :ok
  end

  defmodule OverridesWorker do
    use FaktoryWorker.Job,
      queue: "override_queue",
      concurrency: 5,
      retry: 10,
      reserve_for: 600,
      custom: %{"unique_for" => 60}

    def perform(_), do: :ok
  end

  defstruct [:value]

  describe "encode_job/1" do
    test "should encode a binary" do
      {:ok, job} = Job.encode_job("hey there!")

      assert job == ["hey there!"]
    end

    test "should encode a number" do
      {:ok, job} = Job.encode_job(123)

      assert job == [123]
    end

    test "should encode a map" do
      {:ok, job} = Job.encode_job(%{hey: "there!"})

      assert job == ["{\"hey\":\"there!\"}"]
    end

    test "should encode a struct" do
      {:ok, job} = Job.encode_job(%__MODULE__{value: "hey there!"})

      assert job == ["{\"value\":\"hey there!\"}"]
    end

    test "should encode a list" do
      {:ok, job} = Job.encode_job(["first arg", %__MODULE__{value: "hey there!"}, 123])

      assert job == ["first arg", "{\"value\":\"hey there!\"}", 123]
    end

    test "should return an error if the arguments could not be encoded" do
      {:error, error} = Job.encode_job({:ok, 123})

      assert error == "Unable to encode job argument '{:ok, 123}'"
    end
  end

  describe "build_payload/3" do
    test "should create new faktory job struct" do
      {:ok, data} = Job.encode_job(%{hey: "there!"})

      job = Job.build_payload(Test.Worker, data, [])

      assert job.jid != nil
      assert job.jobtype == "Test.Worker"
      assert job.args == data
    end

    test "should be able to pass in multiple job args" do
      {:ok, data} = Job.encode_job(["some_text", %{hey: "there!"}, 123])

      job = Job.build_payload(Test.Worker, data, [])

      assert job.jid != nil
      assert job.jobtype == "Test.Worker"
      assert job.args == ["some_text", "{\"hey\":\"there!\"}", 123]
    end

    test "should be able to pass in a non list job arg" do
      {:ok, data} = Job.encode_job(%{hey: "there!"})

      job = Job.build_payload(Test.Worker, data, [])

      assert job.jid != nil
      assert job.jobtype == "Test.Worker"
      assert job.args == data
    end

    test "should be able to specify a queue name" do
      {:ok, data} = Job.encode_job(%{hey: "there!"})

      opts = [queue: "test_queue"]
      job = Job.build_payload(Test.Worker, data, opts)

      assert job.queue == "test_queue"
    end

    test "should not be able to specify an invalid data type for queue name" do
      {:ok, data} = Job.encode_job(%{hey: "there!"})
      opts = [queue: 123]
      error = Job.build_payload(Test.Worker, data, opts)

      assert error == {:error, "The field 'queue' has an invalid value '123'"}
    end

    test "should be able to specify a custom map of values" do
      {:ok, data} = Job.encode_job(%{hey: "there!"})
      opts = [custom: %{unique_for: 120}]
      job = Job.build_payload(Test.Worker, data, opts)

      assert job.custom == %{unique_for: 120}
    end

    test "should not be able to specify an invalid data type for custom data" do
      {:ok, data} = Job.encode_job(%{hey: "there!"})
      opts = [custom: [1, 2, 3]]
      error = Job.build_payload(Test.Worker, data, opts)

      assert error == {:error, "The field 'custom' has an invalid value '[1, 2, 3]'"}
    end

    test "should be able to specify the retry field" do
      {:ok, data} = Job.encode_job(%{hey: "there!"})
      opts = [retry: 20]
      job = Job.build_payload(Test.Worker, data, opts)

      assert job.retry == 20
    end

    test "should not be able to specify invalid data for the retry field" do
      {:ok, data} = Job.encode_job(%{hey: "there!"})
      opts = [retry: "20"]
      error = Job.build_payload(Test.Worker, data, opts)

      assert error == {:error, "The field 'retry' has an invalid value '\"20\"'"}
    end

    test "should be able to specify the reserve_for field" do
      {:ok, data} = Job.encode_job(%{hey: "there!"})
      opts = [reserve_for: 120]
      job = Job.build_payload(Test.Worker, data, opts)

      assert job.reserve_for == 120
    end

    test "should not be able to specify invalid data for the reserve_for field" do
      {:ok, data} = Job.encode_job(%{hey: "there!"})
      opts = [reserve_for: "120"]
      error = Job.build_payload(Test.Worker, data, opts)

      assert error == {:error, "The field 'reserve_for' has an invalid value '\"120\"'"}
    end

    test "should not be able to specify a value less than 60 for the reserve_for field" do
      {:ok, data} = Job.encode_job(%{hey: "there!"})
      opts = [reserve_for: 59]
      error = Job.build_payload(Test.Worker, data, opts)

      assert error == {:error, "The field 'reserve_for' has an invalid value '59'"}
    end

    test "should set the job id to a long string" do
      job = Job.build_payload(Test.Worker, [123], [])

      assert byte_size(job.jid) == 24
    end
  end

  describe "perform_async/2" do
    test "should not send a bad payload" do
      {:ok, data} = Job.encode_job(%{hey: "there!"})
      opts = [queue: 123]
      {:error, _} = payload = Job.build_payload(Test.Worker, data, opts)

      {:error, error} = Job.perform_async(payload, [])

      assert error == "The field 'queue' has an invalid value '123'"
    end
  end

  describe "perform_async/3" do
    test "should not send a bad payload" do
      {:ok, data} = Job.encode_job(%{hey: "there!"})
      opts = [queue: 123]
      {:error, _} = payload = Job.build_payload(Test.Worker, data, opts)

      {:error, error} = Job.perform_async(TestPipeline, payload, [])

      assert error == "The field 'queue' has an invalid value '123'"
    end
  end

  describe "worker_config/0" do
    test "should default the retry field value" do
      config = TestWorker.worker_config()

      assert Keyword.get(config, :retry) == 25
    end

    test "should default the reserve_for field value" do
      config = TestWorker.worker_config()

      assert Keyword.get(config, :reserve_for) == 1800
    end
  end

  describe "__using__/1" do
    test "should make the worker config available via worker_config/0" do
      config = TestWorker.worker_config()

      assert Keyword.get(config, :queue) == "test_queue"
      assert Keyword.get(config, :concurrency) == 10
    end

    test "should be able to specify worker config fields" do
      config = OverridesWorker.worker_config()

      assert Keyword.get(config, :queue) == "override_queue"
      assert Keyword.get(config, :concurrency) == 5
      assert Keyword.get(config, :retry) == 10
      assert Keyword.get(config, :reserve_for) == 600
      assert Keyword.get(config, :custom) == %{"unique_for" => 60}
    end
  end
end
