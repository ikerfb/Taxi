defmodule TaxiBeWeb.BookingStore do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def create_booking(booking_id, booking_data) do
    Agent.update(__MODULE__, fn state ->
      Map.put(state, booking_id, Map.put(booking_data, "id", booking_id))
    end)
    get_booking(booking_id)
  end

  def get_booking(booking_id) do
    Agent.get(__MODULE__, fn state -> Map.get(state, booking_id) end)
  end

  def update_booking(booking_id, updates) do
    Agent.update(__MODULE__, fn state ->
      case Map.get(state, booking_id) do
        nil -> state
        booking -> Map.put(state, booking_id, Map.merge(booking, updates))
      end
    end)
    get_booking(booking_id)
  end

  def list_bookings do
    Agent.get(__MODULE__, fn state -> Map.values(state) end)
  end

  def delete_booking(booking_id) do
    Agent.update(__MODULE__, fn state -> Map.delete(state, booking_id) end)
  end
end
