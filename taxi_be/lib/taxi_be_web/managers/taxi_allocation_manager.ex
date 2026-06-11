defmodule TaxiBeWeb.TaxiAllocationManager do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{active_allocations: %{}}}
  end

  def allocate_taxi_v1(booking_id, customer_username, pickup_address, dropoff_address, drivers) do
    GenServer.call(__MODULE__, {:allocate_v1, booking_id, customer_username, pickup_address, dropoff_address, drivers})
  end

  def allocate_taxi_v2(booking_id, customer_username, pickup_address, dropoff_address, drivers) do
    GenServer.call(__MODULE__, {:allocate_v2, booking_id, customer_username, pickup_address, dropoff_address, drivers})
  end

  def handle_driver_response(booking_id, driver_username, decision) do
    GenServer.call(__MODULE__, {:driver_response, booking_id, driver_username, decision})
  end

  @impl true
  def handle_call({:allocate_v1, booking_id, customer_username, pickup_address, dropoff_address, drivers}, _from, state) do
    Logger.info("Starting V1 allocation for booking #{booking_id}")

    if Enum.empty?(drivers) do
      TaxiBeWeb.BookingStore.update_booking(booking_id, %{
        "status" => "failed",
        "failure_reason" => "no_drivers_available"
      })
      notify_customer_allocation_failed(booking_id, customer_username)
      {:reply, {:error, :no_drivers_available}, state}
    else
      first_driver = Enum.at(drivers, 0)
      notify_driver_request(booking_id, first_driver, pickup_address, dropoff_address)

      new_state = put_in(state.active_allocations[booking_id], %{
        version: :v1,
        status: :pending,
        customer_username: customer_username,
        pickup_address: pickup_address,
        dropoff_address: dropoff_address,
        drivers: drivers,
        current_index: 0,
        accepted_by: nil,
        created_at: DateTime.utc_now()
      })

      {:reply, {:ok, :allocation_started}, new_state}
    end
  end

  @impl true
  def handle_call({:allocate_v2, booking_id, customer_username, pickup_address, dropoff_address, drivers}, _from, state) do
    Logger.info("Starting V2 allocation for booking #{booking_id}")

    top_3_drivers = Enum.take(drivers, 3)

    new_state = put_in(state.active_allocations[booking_id], %{
      version: :v2,
      status: :pending,
      customer_username: customer_username,
      pickup_address: pickup_address,
      dropoff_address: dropoff_address,
      drivers_contacted: Enum.map(top_3_drivers, & &1["id"]),
      accepted_by: nil,
      created_at: DateTime.utc_now(),
      timeout_ref: set_timeout(booking_id, 90)
    })

    notify_drivers_parallel(booking_id, top_3_drivers, pickup_address, dropoff_address)

    {:reply, {:ok, :allocation_started}, new_state}
  end

  @impl true
  def handle_call({:driver_response, booking_id, driver_username, decision}, _from, state) do
    case Map.get(state.active_allocations, booking_id) do
      nil ->
        {:reply, {:error, :booking_not_found}, state}

      allocation ->
        if allocation.status == :accepted do
          {:reply, {:ok, :ignored}, state}
        else
          handle_driver_decision(booking_id, driver_username, decision, allocation, state)
        end
    end
  end

  @impl true
  def handle_info({:allocation_timeout, booking_id}, state) do
    case Map.get(state.active_allocations, booking_id) do
      nil ->
        {:noreply, state}

      allocation ->
        if allocation.status == :pending do
          Logger.warning("Allocation timeout for booking #{booking_id}")

          TaxiBeWeb.BookingStore.update_booking(booking_id, %{
            "status" => "failed",
            "failure_reason" => "no_drivers_accepted"
          })

          notify_customer_allocation_failed(booking_id, allocation.customer_username)

          new_state = put_in(state.active_allocations[booking_id], %{allocation | status: :failed})
          {:noreply, new_state}
        else
          {:noreply, state}
        end
    end
  end

  # Private helpers

  defp handle_driver_decision(booking_id, driver_username, "accept", allocation, state) do
    # Random ETA between 1-4 minutes (short for demo/testing)
    estimated_seconds = :rand.uniform(180) + 60

    TaxiBeWeb.BookingStore.update_booking(booking_id, %{
      "driver_id" => driver_username,
      "status" => "accepted",
      "accepted_at" => DateTime.utc_now(),
      "estimated_arrival_seconds" => estimated_seconds
    })

    notify_customer_driver_accepted(booking_id, allocation.customer_username, driver_username, estimated_seconds)

    if allocation.version == :v2 do
      notify_other_drivers_rejected(booking_id, driver_username, allocation.drivers_contacted)
      if allocation[:timeout_ref], do: Process.cancel_timer(allocation.timeout_ref)
    end

    new_state = put_in(state.active_allocations[booking_id], %{allocation | status: :accepted, accepted_by: driver_username})
    {:reply, {:ok, :accepted}, new_state}
  end

  defp handle_driver_decision(booking_id, driver_username, "reject", %{version: :v1} = allocation, state) do
    next_index = allocation.current_index + 1

    if next_index >= length(allocation.drivers) do
      TaxiBeWeb.BookingStore.update_booking(booking_id, %{
        "status" => "failed",
        "failure_reason" => "all_drivers_rejected"
      })
      notify_customer_allocation_failed(booking_id, allocation.customer_username)
      new_state = put_in(state.active_allocations[booking_id], %{allocation | status: :failed})
      {:reply, {:ok, :rejected}, new_state}
    else
      next_driver = Enum.at(allocation.drivers, next_index)
      notify_driver_request(booking_id, next_driver, allocation.pickup_address, allocation.dropoff_address)
      Logger.info("V1: driver #{driver_username} rejected, trying driver #{next_driver["id"]}")
      new_state = put_in(state.active_allocations[booking_id], %{allocation | current_index: next_index})
      {:reply, {:ok, :rejected}, new_state}
    end
  end

  defp handle_driver_decision(booking_id, driver_username, "reject", %{version: :v2} = allocation, state) do
    remaining = Enum.filter(allocation.drivers_contacted, fn d -> d != driver_username end)

    if Enum.empty?(remaining) do
      TaxiBeWeb.BookingStore.update_booking(booking_id, %{
        "status" => "failed",
        "failure_reason" => "all_drivers_rejected"
      })
      notify_customer_allocation_failed(booking_id, allocation.customer_username)
      new_state = put_in(state.active_allocations[booking_id], %{allocation | status: :failed})
      {:reply, {:ok, :rejected}, new_state}
    else
      new_state = put_in(state.active_allocations[booking_id], %{allocation | drivers_contacted: remaining})
      {:reply, {:ok, :rejected}, new_state}
    end
  end

  defp handle_driver_decision(_booking_id, _driver_username, _decision, _allocation, state) do
    {:reply, {:error, :invalid_decision}, state}
  end

  defp notify_drivers_parallel(booking_id, drivers, pickup_address, dropoff_address) do
    Enum.each(drivers, fn driver ->
      notify_driver_request(booking_id, driver, pickup_address, dropoff_address)
    end)
  end

  defp notify_driver_request(booking_id, driver, pickup_address, dropoff_address) do
    channel = "driver:#{driver["id"]}"

    message = %{
      "msg" => "New ride request: #{pickup_address} → #{dropoff_address}",
      "bookingId" => booking_id,
      "pickup_address" => pickup_address,
      "dropoff_address" => dropoff_address,
      "pickup_coords" => driver["location"],
      "estimated_arrival" => "calculating..."
    }

    TaxiBeWeb.Endpoint.broadcast(channel, "booking_request", message)
  end

  defp notify_customer_driver_accepted(booking_id, customer_username, driver_username, estimated_seconds) do
    channel = "customer:#{customer_username}"

    message = %{
      "msg" => "Driver #{driver_username} accepted your ride! ETA: #{div(estimated_seconds, 60)} min",
      "bookingId" => booking_id,
      "driver_id" => driver_username,
      "status" => "accepted",
      "estimated_arrival_seconds" => estimated_seconds
    }

    TaxiBeWeb.Endpoint.broadcast(channel, "booking_accepted", message)
  end

  defp notify_other_drivers_rejected(booking_id, accepted_driver, all_drivers) do
    Enum.each(all_drivers, fn driver_id ->
      unless driver_id == accepted_driver do
        channel = "driver:#{driver_id}"

        message = %{
          "msg" => "The ride was assigned to another driver",
          "bookingId" => booking_id,
          "status" => "ride_assigned_other"
        }

        TaxiBeWeb.Endpoint.broadcast(channel, "booking_reassigned", message)
      end
    end)
  end

  defp notify_customer_allocation_failed(booking_id, customer_username) do
    channel = "customer:#{customer_username}"

    message = %{
      "msg" => "Sorry, no drivers available right now. Please try again.",
      "bookingId" => booking_id,
      "status" => "allocation_failed"
    }

    TaxiBeWeb.Endpoint.broadcast(channel, "booking_failed", message)
  end

  defp set_timeout(booking_id, seconds) do
    Process.send_after(self(), {:allocation_timeout, booking_id}, seconds * 1000)
  end
end
