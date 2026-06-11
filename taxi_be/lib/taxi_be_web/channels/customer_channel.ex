defmodule TaxiBeWeb.CustomerChannel do
  use TaxiBeWeb, :channel
  require Logger

  @impl true
  def join("customer:" <> username, _payload, socket) do
    Logger.info("Customer #{username} connected")
    
    {:ok, assign(socket, :username, username)}
  end

  def handle_in("cancel_booking", %{"booking_id" => booking_id}, socket) do
    Logger.info("Customer #{socket.assigns.username} requesting cancellation of booking #{booking_id}")
    
    case TaxiBeWeb.CancellationManager.process_cancellation(booking_id, socket.assigns.username) do
      {:ok, reason} ->
        {:reply, {:ok, %{msg: "Booking cancelled", reason: reason}}, socket}
      
      {:ok, reason, details} ->
        {:reply, {:ok, %{msg: "Booking cancelled with penalty", reason: reason, details: details}}, socket}
      
      {:error, reason} ->
        {:reply, {:error, %{msg: "Cannot cancel booking", reason: reason}}, socket}
    end
  end

  def handle_in("get_booking_status", %{"booking_id" => booking_id}, socket) do
    booking = TaxiBeWeb.BookingStore.get_booking(booking_id)
    
    if booking do
      {:reply, {:ok, booking}, socket}
    else
      {:reply, {:error, %{msg: "Booking not found"}}, socket}
    end
  end
end
