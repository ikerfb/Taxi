import { useState } from 'react'
import './App.css'
import Customer from './components/Customer';
import Driver from './components/Driver';
import { Button, Box, Typography } from '@mui/material';

function App() {
  const [role, setRole] = useState(null);
  const [username, setUsername] = useState("");
  const [confirmed, setConfirmed] = useState(false);

  if (!confirmed) {
    return (
      <Box style={{ textAlign: "center", padding: "40px" }}>
        <Typography variant="h4" gutterBottom>Taxi App</Typography>
        <Typography variant="body1" gutterBottom>Select your role:</Typography>

        <Box style={{ marginBottom: "20px" }}>
          <Button
            variant={role === "customer" ? "contained" : "outlined"}
            onClick={() => { setRole("customer"); setUsername("customer1"); }}
            style={{ marginRight: "10px" }}
          >
            Customer
          </Button>
          <Button
            variant={role === "driver" ? "contained" : "outlined"}
            onClick={() => { setRole("driver"); setUsername("driver1"); }}
          >
            Driver
          </Button>
        </Box>

        {role && (
          <Box>
            <input
              placeholder={`Username (default: ${username})`}
              onChange={e => setUsername(e.target.value || (role === "customer" ? "customer1" : "driver1"))}
              style={{ padding: "8px", marginBottom: "10px", display: "block", margin: "0 auto 10px" }}
            />
            <Button variant="contained" onClick={() => setConfirmed(true)}>
              Enter as {role}
            </Button>
          </Box>
        )}
      </Box>
    );
  }

  if (role === "customer") return <Customer username={username} />;
  if (role === "driver") return <Driver username={username} />;
}

export default App
