import React, { useEffect, useState, useRef } from 'react';
import Button from '@mui/material/Button';
import socket from '../services/taxi_socket';
import { TextField, Card, CardContent, Typography, Alert, CircularProgress } from '@mui/material';

function Customer(props) {
  const [pickupAddress, setPickupAddress] = useState("Tecnologico de Monterrey, campus Puebla, Mexico");
  const [dropOffAddress, setDropOffAddress] = useState("Triangulo Las Animas, Puebla, Mexico");
  const [statusMsg, setStatusMsg] = useState("");
  const [bookingStatus, setBookingStatus] = useState("");
  const [bookingId, setBookingId] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [bookingDetails, setBookingDetails] = useState({});
  const channelRef = useRef(null);

  useEffect(() => {
    const channel = socket.channel("customer:" + props.username, { token: "123" });
    channelRef.current = channel;

    channel.on("booking_accepted", data => {
      console.log("Booking accepted:", data);
      setStatusMsg(data.msg);
      setBookingStatus("accepted");
      setIsLoading(false);
      setBookingDetails({
        driver_id: data.driver_id,
        status: data.status,
        eta: data.estimated_arrival_seconds
          ? Math.round(data.estimated_arrival_seconds / 60) + " min"
          : "unknown"
      });
    });

    channel.on("booking_failed", data => {
      console.log("Booking failed:", data);
      setStatusMsg(data.msg);
      setBookingStatus("failed");
      setIsLoading(false);
    });

    channel.on("booking_request", data => {
      setStatusMsg(data.msg);
    });

    channel.join()
      .receive("ok", () => console.log("Customer channel joined:", props.username))
      .receive("error", err => console.error("Customer channel error:", err));

    return () => {
      channel.leave();
      channelRef.current = null;
    };
  }, [props.username]);

  const submit = () => {
    setIsLoading(true);
    setStatusMsg("Searching for available drivers...");
    setBookingStatus("searching");
    setBookingDetails({});

    fetch("http://localhost:4000/api/bookings", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        pickup_address: pickupAddress,
        dropoff_address: dropOffAddress,
        username: props.username,
        version: "v2"   // change to "v1" for sequential version
      })
    })
      .then(resp => resp.json())
      .then(data => {
        console.log("Booking response:", data);
        setBookingId(data.booking_id);
        setStatusMsg(data.msg);
        setBookingStatus(data.status);
        if (data.status === "failed") setIsLoading(false);
      })
      .catch(err => {
        console.error("Error creating booking:", err);
        setStatusMsg("Error connecting to server");
        setIsLoading(false);
      });
  };

  const cancelBooking = () => {
    const channel = channelRef.current;
    if (!channel) {
      setStatusMsg("Error: not connected");
      return;
    }

    channel.push("cancel_booking", { booking_id: bookingId })
      .receive("ok", resp => {
        console.log("Cancellation successful:", resp);
        if (resp.details && resp.details.amount > 0) {
          setStatusMsg(`Cancelled — penalty: $${resp.details.amount}`);
        } else {
          setStatusMsg("Cancelled — no penalty");
        }
        setBookingStatus("cancelled");
        setIsLoading(false);
      })
      .receive("error", reason => {
        console.error("Cancellation error:", reason);
        setStatusMsg(`Error: ${reason.msg}`);
      });
  };

  const resetBooking = () => {
    setBookingStatus("");
    setBookingId("");
    setStatusMsg("");
    setBookingDetails({});
  };

  return (
    <div style={{ textAlign: "center", borderStyle: "solid", padding: "20px", margin: "10px" }}>
      <h2>Customer: {props.username}</h2>

      {(!bookingStatus || bookingStatus === "completed") && (
        <div>
          <TextField
            label="Pickup address"
            fullWidth
            onChange={ev => setPickupAddress(ev.target.value)}
            value={pickupAddress}
            style={{ marginBottom: "10px" }}
          />
          <TextField
            label="Drop off address"
            fullWidth
            onChange={ev => setDropOffAddress(ev.target.value)}
            value={dropOffAddress}
            style={{ marginBottom: "10px" }}
          />
          <Button onClick={submit} variant="contained" color="primary" disabled={isLoading}>
            {isLoading ? "Searching..." : "Request Ride"}
          </Button>
        </div>
      )}

      {bookingId && (
        <Card style={{ marginTop: "20px" }}>
          <CardContent>
            <Typography variant="h6">Booking ID: {bookingId}</Typography>
            <Typography variant="body2" color="textSecondary">
              Status: {bookingStatus.toUpperCase()}
            </Typography>
            {bookingDetails.driver_id && (
              <>
                <Typography variant="body2">Driver: {bookingDetails.driver_id}</Typography>
                <Typography variant="body2">ETA: {bookingDetails.eta}</Typography>
              </>
            )}
          </CardContent>
        </Card>
      )}

      {isLoading && (
        <div style={{ marginTop: "20px" }}>
          <CircularProgress />
        </div>
      )}

      {statusMsg && (
        <Alert
          severity={
            bookingStatus === "failed" || bookingStatus === "cancelled" ? "error"
            : bookingStatus === "accepted" ? "success"
            : "info"
          }
          style={{ marginTop: "20px" }}
        >
          {statusMsg}
        </Alert>
      )}

      {(bookingStatus === "searching" || bookingStatus === "finding_driver" || bookingStatus === "accepted") && (
        <Button
          onClick={cancelBooking}
          variant="outlined"
          color="secondary"
          style={{ marginTop: "20px", marginRight: "10px" }}
        >
          Cancel Ride
        </Button>
      )}

      {(bookingStatus === "cancelled" || bookingStatus === "failed") && (
        <Button onClick={resetBooking} variant="outlined" style={{ marginTop: "20px" }}>
          New Booking
        </Button>
      )}
    </div>
  );
}

export default Customer;
