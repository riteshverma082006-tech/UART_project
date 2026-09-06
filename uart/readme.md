# UART Project

A simple UART (Universal Asynchronous Receiver/Transmitter) implementation in Verilog, featuring a Receiver (RX) and a Transmitter (TX) module built on a shared FSM style.

## Repository Structure

```
UART_project/
└── uart_rx/
    ├── uartreciever.v   → UART RX module (module name: uart)
    ├── tx.v             → UART TX module (module name: uart_tx)
    ├── rx_tb.v          → Testbench
    └── readme.md        → This file
```

## Modules

### RX — `uartreciever.v` (`module uart`)

```verilog
module uart (
    input clk, reset,
    input d, ready,
    output reg [7:0] data,
    output reg done
);
```

| Port    | Dir | Description                                  |
|---------|-----|-----------------------------------------------|
| `clk`   | in  | System clock                                  |
| `reset` | in  | Active-low asynchronous reset                 |
| `d`     | in  | Serial data input line                        |
| `ready` | in  | Asserted to indicate a start bit / begin RX    |
| `data`  | out | Received 8-bit parallel data                  |
| `done`  | out | Asserted when a byte has been fully received  |

**FSM states:**
- `S0` — Idle: waits for `ready`
- `S1` — Start bit: waits half a bit period before sampling
- `S2` — Data bits: samples `d` into `data[i]`, `i = 0..7`
- `S3` — Stop bit: validates line and returns to idle

### TX — `tx.v` (`module uart_tx`)

```verilog
module uart_tx (
    input clk, reset,
    input send,
    input [7:0] data_in,
    output reg tx,
    output reg done
);
```

| Port      | Dir | Description                                   |
|-----------|-----|------------------------------------------------|
| `clk`     | in  | System clock                                   |
| `reset`   | in  | Active-low asynchronous reset                  |
| `send`    | in  | Pulse/level high to start transmitting `data_in`|
| `data_in` | in  | 8-bit byte to transmit                         |
| `tx`      | out | Serial data output line (idles high)           |
| `done`    | out | Pulses high for one clock when TX completes    |

**FSM states:**
- `S0` — Idle: `tx` held high, waits for `send`, latches `data_in`
- `S1` — Start bit: drives `tx` low for one full bit period
- `S2` — Data bits: shifts out `data_in[i]`, LSB first, `i = 0..7`
- `S3` — Stop bit: drives `tx` high for one bit period, then asserts `done`

## Timing / Baud Rate

Both modules use:

```verilog
parameter clkperbits = 5208;
```

This sets clock cycles per bit period: `clkperbits = clk_frequency / baud_rate` (5208 ≈ 9600 baud @ ~50 MHz). Keep this value identical in both modules — RX and TX must agree on baud rate to interoperate.

## Connecting TX to RX (loopback)

```verilog
uart_tx tx_inst (
    .clk(clk), .reset(reset),
    .send(send), .data_in(tx_data),
    .tx(serial_line), .done(tx_done)
);

uart rx_inst (
    .clk(clk), .reset(reset),
    .d(serial_line), .ready(rx_ready),
    .data(rx_data), .done(rx_done)
);
```

`rx_ready` needs to be asserted in sync with TX's start bit — check this timing carefully in simulation, since RX samples using a half-bit delay in its start state while TX holds the start bit for a full bit period.

## Simulation

```bash
iverilog -o uart_sim uartreciever.v tx.v rx_tb.v
vvp uart_sim
gtkwave uart_sim.vcd
```

