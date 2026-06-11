defmodule TaxiBeWeb.BookingController do
  use TaxiBeWeb, :controller
  require Logger

  def create(conn, req) do
    Logger.info("Creating booking: #{inspect(req)}")

    booking_id = UUID.uuid4()
    pickup_address = req["pickup_address"] || ""
    dropoff_address = req["dropoff_address"] || ""
    customer_username = req["username"] || "unknown"
    # Pass "version": "v1" in the request body to use V1 (sequential)
    version = req["version"] || "v2"

    TaxiBeWeb.BookingStore.create_booking(booking_id, %{
      "pickup_address" => pickup_address,
      "dropoff_address" => dropoff_address,
      "customer_username" => customer_username,
      "status" => "finding_driver",
      "version" => version,
      "created_at" => DateTime.utc_now()
    })

    available_drivers = TaxiBeWeb.DriverStore.list_available_drivers()

    if Enum.empty?(available_drivers) do
      TaxiBeWeb.BookingStore.update_booking(booking_id, %{"status" => "failed"})

      conn
      |> put_resp_header("location", "/api/bookings/" <> booking_id)
      |> put_status(:created)
      |> json(%{
        booking_id: booking_id,
        msg: "No drivers available at the moment. Please try again later.",
        status: "failed"
      })
    else
      sorted_drivers = sort_drivers_by_distance(available_drivers, req)

      case version do
        "v1" ->
          TaxiBeWeb.TaxiAllocationManager.allocate_taxi_v1(
            booking_id, customer_username, pickup_address, dropoff_address, sorted_drivers
          )
        _ ->
          TaxiBeWeb.TaxiAllocationManager.allocate_taxi_v2(
            booking_id, customer_username, pickup_address, dropoff_address, sorted_drivers
          )
      end

      conn
      |> put_resp_header("location", "/api/bookings/" <> booking_id)
      |> put_status(:created)
      |> json(%{
        booking_id: booking_id,
        msg: "We are processing your request",
        status: "finding_driver"
      })
    end
  end

  def update(conn, %{"action" => "accept", "username" => username, "id" => booking_id}) do
    Logger.info("'#{username}' accepting booking #{booking_id}")

    case TaxiBeWeb.TaxiAllocationManager.handle_driver_response(booking_id, username, "accept") do
      {:ok, _} ->
        json(conn, %{msg: "Booking accepted successfully", status: "success"})

      {:error, reason} ->
        Logger.warning("Error accepting booking: #{inspect(reason)}")
        json(conn, %{msg: "Error processing acceptance", error: reason, status: "error"})
    end
  end

  def update(conn, %{"action" => "reject", "username" => username, "id" => booking_id}) do
    Logger.info("'#{username}' rejecting booking #{booking_id}")

    case TaxiBeWeb.TaxiAllocationManager.handle_driver_response(booking_id, username, "reject") do
      {:ok, _} ->
        json(conn, %{msg: "Booking rejected", status: "success"})

      {:error, reason} ->
        Logger.warning("Error rejecting booking: #{inspect(reason)}")
        json(conn, %{msg: "Error processing rejection", error: reason, status: "error"})
    end
  end

  def update(conn, %{"action" => "cancel", "username" => username, "id" => booking_id}) do
    Logger.info("'#{username}' cancelling booking #{booking_id}")

    case TaxiBeWeb.CancellationManager.process_cancellation(booking_id, username) do
      {:ok, reason} ->
        json(conn, %{msg: "Booking cancelled successfully", reason: reason, status: "success"})

      {:ok, reason, details} ->
        json(conn, %{msg: "Booking cancelled", reason: reason, details: details, status: "success"})

      {:error, reason} ->
        Logger.warning("Error cancelling booking: #{inspect(reason)}")
        json(conn, %{msg: "Error processing cancellation", error: reason, status: "error"})
    end
  end

  defp sort_drivers_by_distance(drivers, _req) do
    # Randomized for now — replace with real distance calculation via Mapbox
    Enum.shuffle(drivers)
  end
end
