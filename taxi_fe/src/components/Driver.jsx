import React, { useEffect, useState, useRef } from 'react';
import Button from '@mui/material/Button';
import socket from '../services/taxi_socket';
import { Card, CardContent, Typography, Alert, Box } from '@mui/material';

function Driver(props) {
  const [message, setMessage] = useState("");
  const [bookingId, setBookingId] = useState("");
  const [pickupAddress, setPickupAddress] = useState("");
  const [dropOffAddress, setDropOffAddress] = useState("");
  const [visible, setVisible] = useState(false);
  const [isAvailable, setIsAvailable] = useState(true);
  const [notifications, setNotifications] = useState([]);
  const channelRef = useRef(null);

  const addNotification = (notif) => {
    setNotifications(prev => [notif, ...prev.slice(0, 4)]);
  };

  useEffect(() => {
    const channel = socket.channel("driver:" + props.username, { token: "123" });
    channelRef.current = channel;

    channel.on("booking_request", data => {
      console.log("Booking request received:", data);
      setMessage(data.msg);
      setBookingId(data.bookingId);
      setPickupAddress(data.pickup_address);
      setDropOffAddress(data.dropoff_address);
      setVisible(true);
      addNotification({ type: "request", msg: `New ride: ${data.pickup_address} → ${data.dropoff_address}` });
    });

    channel.on("booking_reassigned", data => {
      console.log("Booking reassigned:", data);
      setVisible(false);
      addNotification({ type: "info", msg: data.msg });
    });

    channel.on("booking_cancelled", data => {
      console.log("Booking cancelled:", data);
      setVisible(false);
      const penaltyMsg = data.cancellation_penalty > 0
        ? `Customer cancelled — penalty charged: $${data.cancellation_penalty}`
        : "Customer cancelled — no penalty";
      addNotification({ type: "warning", msg: penaltyMsg });
    });

    channel.join()
      .receive("ok", () => {
        console.log("Driver channel joined:", props.username);
        channel.push("set_availability", { available: true });
      })
      .receive("error", err => console.error("Driver channel error:", err));

    return () => {
      channel.leave();
      channelRef.current = null;
    };
  }, [props.username]);

  const reply = (decision) => {
    const channel = channelRef.current;
    if (!channel) {
      console.error("Channel not connected");
      return;
    }

    const action = decision === "accept" ? "accept_booking" : "reject_booking";

    channel.push(action, { booking_id: bookingId })
      .receive("ok", resp => {
        console.log(`Booking ${decision}ed:`, resp);
        setVisible(false);
        addNotification({ type: "success", msg: `Ride ${decision}ed` });
      })
      .receive("error", reason => {
        console.error(`Error ${decision}ing:`, reason);
        addNotification({ type: "error", msg: reason.msg || `Error ${decision}ing booking` });
      });
  };

  const toggleAvailability = () => {
    const channel = channelRef.current;
    if (!channel) return;

    const newAvailability = !isAvailable;
    channel.push("set_availability", { available: newAvailability })
      .receive("ok", () => {
        setIsAvailable(newAvailability);
        addNotification({
          type: "info",
          msg: newAvailability ? "You are now available" : "You are now offline"
        });
      });
  };

  return (
    <div style={{ textAlign: "center", borderStyle: "solid", padding: "20px", margin: "10px" }}>
      <h2>Driver: {props.username}</h2>

      <Box style={{ marginBottom: "20px" }}>
        <Button
          onClick={toggleAvailability}
          variant={isAvailable ? "contained" : "outlined"}
          color={isAvailable ? "success" : "error"}
        >
          {isAvailable ? "Available" : "Offline"}
        </Button>
      </Box>

      <div style={{ backgroundColor: "lavender", minHeight: "150px", padding: "20px" }}>
        {visible && (
          <Card variant="outlined" style={{ marginBottom: "20px" }}>
            <CardContent>
              <Typography variant="h6">New Ride Request</Typography>
              <Typography variant="body2" style={{ marginTop: "10px" }}>{message}</Typography>
              <Typography variant="caption" display="block" style={{ marginTop: "10px" }}>
                <strong>From:</strong> {pickupAddress}
              </Typography>
              <Typography variant="caption" display="block">
                <strong>To:</strong> {dropOffAddress}
              </Typography>
              <Box style={{ marginTop: "15px" }}>
                <Button
                  onClick={() => reply("accept")}
                  variant="contained"
                  color="success"
                  style={{ marginRight: "10px" }}
                >
                  Accept
                </Button>
                <Button onClick={() => reply("reject")} variant="outlined" color="error">
                  Reject
                </Button>
              </Box>
            </CardContent>
          </Card>
        )}

        {!visible && notifications.length === 0 && (
          <Typography color="textSecondary">Waiting for ride requests...</Typography>
        )}

        {notifications.length > 0 && (
          <Box style={{ marginTop: "10px" }}>
            <Typography variant="subtitle2">Recent Activity</Typography>
            {notifications.map((notif, idx) => (
              <Alert
                key={idx}
                severity={
                  notif.type === "success" ? "success"
                  : notif.type === "error" ? "error"
                  : notif.type === "warning" ? "warning"
                  : "info"
                }
                style={{ marginTop: "5px", textAlign: "left" }}
              >
                {notif.msg}
              </Alert>
            ))}
          </Box>
        )}
      </div>
    </div>
  );
}

export default Driver;
