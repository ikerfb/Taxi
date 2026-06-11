defmodule TaxiBeWeb.CancellationManager do
  require Logger

  # 3 minutes in milliseconds
  @late_cancellation_threshold_ms 180_000

  def can_cancel_without_penalty?(booking_id) do
    booking = TaxiBeWeb.BookingStore.get_booking(booking_id)

    cond do
      is_nil(booking) ->
        {:error, :booking_not_found}

      # Scenario 1: No driver has accepted yet → no penalty
      booking["status"] in ["pending", "finding_driver"] ->
        {:ok, :no_penalty}

      # Scenario 2: Driver accepted → check time remaining until arrival
      booking["status"] == "accepted" ->
        case time_remaining_ms(booking) do
          {:ok, remaining_ms} when remaining_ms > @late_cancellation_threshold_ms ->
            # More than 3 min away → no penalty
            {:ok, :no_penalty}

          {:ok, _remaining_ms} ->
            # 3 min or less away → $20 penalty
            {:ok, :penalty_required, %{"amount" => 20, "reason" => "late_cancellation"}}

          {:error, _reason} ->
            # Arrival time unknown → apply penalty to be safe
            {:ok, :penalty_required, %{"amount" => 20, "reason" => "late_cancellation"}}
        end

      booking["status"] in ["completed", "cancelled", "failed"] ->
        {:error, :cannot_cancel_completed}

      true ->
        {:error, :invalid_status}
    end
  end

  def process_cancellation(booking_id, customer_username) do
    case can_cancel_without_penalty?(booking_id) do
      {:ok, :no_penalty} ->
        execute_cancellation_no_penalty(booking_id, customer_username)

      {:ok, :penalty_required, penalty_info} ->
        execute_cancellation_with_penalty(booking_id, customer_username, penalty_info)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private

  defp execute_cancellation_no_penalty(booking_id, customer_username) do
    TaxiBeWeb.BookingStore.update_booking(booking_id, %{
      "status" => "cancelled",
      "cancelled_by" => customer_username,
      "cancelled_at" => DateTime.utc_now(),
      "cancellation_penalty" => 0
    })

    booking = TaxiBeWeb.BookingStore.get_booking(booking_id)
    notify_cancellation(booking_id, booking, 0)

    {:ok, :cancelled_no_penalty}
  end

  defp execute_cancellation_with_penalty(booking_id, customer_username, penalty_info) do
    penalty_amount = penalty_info["amount"] || 20

    TaxiBeWeb.BookingStore.update_booking(booking_id, %{
      "status" => "cancelled",
      "cancelled_by" => customer_username,
      "cancelled_at" => DateTime.utc_now(),
      "cancellation_penalty" => penalty_amount,
      "penalty_reason" => penalty_info["reason"] || "late_cancellation"
    })

    booking = TaxiBeWeb.BookingStore.get_booking(booking_id)
    notify_cancellation(booking_id, booking, penalty_amount)

    {:ok, :cancelled_with_penalty, %{"amount" => penalty_amount}}
  end

  defp time_remaining_ms(booking) do
    with accepted_at when not is_nil(accepted_at) <- booking["accepted_at"],
         estimated_s when not is_nil(estimated_s) <- booking["estimated_arrival_seconds"] do
      elapsed_ms = DateTime.diff(DateTime.utc_now(), accepted_at, :millisecond)
      remaining_ms = max(estimated_s * 1000 - elapsed_ms, 0)
      {:ok, remaining_ms}
    else
      _ -> {:error, :arrival_time_not_available}
    end
  end

  defp notify_cancellation(booking_id, booking, penalty_amount) do
    if booking && booking["driver_id"] do
      driver_channel = "driver:#{booking["driver_id"]}"

      message = %{
        "msg" => "Booking #{booking_id} was cancelled by the customer",
        "bookingId" => booking_id,
        "status" => "cancelled",
        "cancellation_penalty" => penalty_amount
      }

      TaxiBeWeb.Endpoint.broadcast(driver_channel, "booking_cancelled", message)
    end
  end
end
