defmodule TaxiBeWeb.DriverChannel do
  use TaxiBeWeb, :channel
  require Logger

  @impl true
  def join("driver:" <> username, _payload, socket) do
    Logger.info("Driver #{username} connected")
    
    # Register driver as available
    TaxiBeWeb.DriverStore.register_driver(username, %{
      "id" => username,
      "available" => true,
      "location" => [0, 0],  # Will be updated via location updates
      "connected_at" => DateTime.utc_now()
    })
    
    {:ok, assign(socket, :username, username)}
  end

  def handle_in("accept_booking", %{"booking_id" => booking_id}, socket) do
    Logger.info("Driver #{socket.assigns.username} accepting booking #{booking_id}")
    
    case TaxiBeWeb.TaxiAllocationManager.handle_driver_response(booking_id, socket.assigns.username, "accept") do
      {:ok, _} ->
        {:reply, {:ok, %{msg: "Booking accepted"}}, socket}
      
      {:error, reason} ->
        {:reply, {:error, %{msg: "Error accepting booking", reason: reason}}, socket}
    end
  end

  def handle_in("reject_booking", %{"booking_id" => booking_id}, socket) do
    Logger.info("Driver #{socket.assigns.username} rejecting booking #{booking_id}")
    
    case TaxiBeWeb.TaxiAllocationManager.handle_driver_response(booking_id, socket.assigns.username, "reject") do
      {:ok, _} ->
        {:reply, {:ok, %{msg: "Booking rejected"}}, socket}
      
      {:error, reason} ->
        {:reply, {:error, %{msg: "Error rejecting booking", reason: reason}}, socket}
    end
  end

  def handle_in("update_location", %{"latitude" => lat, "longitude" => lon}, socket) do
    username = socket.assigns.username
    
    TaxiBeWeb.DriverStore.update_driver(username, %{
      "location" => [lon, lat],
      "last_location_update" => DateTime.utc_now()
    })
    
    {:reply, {:ok, %{msg: "Location updated"}}, socket}
  end

  def handle_in("set_availability", %{"available" => available}, socket) do
    username = socket.assigns.username
    
    TaxiBeWeb.DriverStore.update_driver(username, %{
      "available" => available
    })
    
    Logger.info("Driver #{username} availability set to #{available}")
    
    {:reply, {:ok, %{msg: "Availability updated"}}, socket}
  end

  def terminate(_reason, socket) do
    username = socket.assigns.username
    Logger.info("Driver #{username} disconnected")
    
    TaxiBeWeb.DriverStore.update_driver(username, %{
      "available" => false,
      "disconnected_at" => DateTime.utc_now()
    })
  end
end
