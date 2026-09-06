# UART Project
A simple UART (Universal Asynchronous Receiver/Transmitter) implementation in Verilog, featuring a Receiver (RX) and a Transmitter (TX) module built on a shared FSM style, plus an APB3 slave wrapper for SoC integration.

## Repository Structure
```
UART_project/
└── uart/
    ├── uartreciever.v          → UART RX module (module name: uart)
    ├── tx.v                    → UART TX module (module name: uart_tx)
    ├── rx_tb.v                 → RX/TX testbench
    ├── apb_slave.v             → Generic APB3 bus-protocol layer
    ├── uart_apb_wrapper.v      → UART-specific APB register wrapper
    ├── tb_uart_apb_wrapper.v   → Loopback testbench for the APB wrapper
    ├── tb_uart_async.v         → Asynchronous start-bit timing testbench
    └── readme.md               → This file
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

Note: this core does not detect the start bit itself — it relies entirely
on an external `ready` pulse timed to the moment a start bit begins. The
APB wrapper (below) is responsible for generating that pulse correctly.

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
    .d(serial_line), .ready(rx_ready_pulse),
    .data(rx_data), .done(rx_done)
);
```
`rx_ready_pulse` must be a single-cycle pulse timed to the actual start of
the incoming start bit — see the APB wrapper's start-bit detection logic
below for a working reference implementation, since RX samples using a
half-bit delay in its start state while TX holds the start bit for a full
bit period.

## Simulation (RX/TX core)
```bash
iverilog -o uart_sim uartreciever.v tx.v rx_tb.v
vvp uart_sim
gtkwave uart_sim.vcd
```

## APB Register Interface

`uart_apb_wrapper.v` + `apb_slave.v` wrap the UART core in an APB3
slave interface, exposing it as a memory-mapped peripheral suitable
for integration into an AMBA-based SoC (behind an AHB-to-APB bridge).

| Offset | Name    | Access | Bits                                              |
|--------|---------|--------|----------------------------------------------------|
| 0x00   | TX_DATA | WO     | [7:0] byte to send — write pulses `send`            |
| 0x04   | RX_DATA | RO     | [7:0] last received byte — read clears `rx_valid`   |
| 0x08   | STATUS  | RO     | [0] tx_busy, [1] rx_valid                           |
| 0x0C   | CONTROL | RW     | [0] enable                                          |

**Design notes:**
- `tx_busy` and `rx_valid` are latched by the wrapper itself (set on
  start, cleared on the core's `done` pulse) — neither core exposes a
  persistent status flag on its own.
- **RX start-bit detection:** the raw `uart` core needs an external
  `ready` pulse timed to the exact start of an incoming start bit — it
  has no start-bit detection of its own. The wrapper synchronizes
  `uart_rxd` over two flip-flops and detects a real falling edge
  (`enable & d_prev & ~d_sync`), only recognizing it once `enable`
  is set, and feeds a single-cycle pulse into the core's `ready` input.
  This replaced an earlier version that tied `ready` directly to
  `enable` (a held-high level) — that version only appeared to work in
  the original loopback test because the TX write happened to land at
  a lucky, bit-aligned offset; it would silently receive garbage for
  any real, asynchronously-timed transmission. `tb_uart_async.v`
  specifically tests this by enabling the UART long before sending, at
  a deliberately non-bit-aligned delay, and confirms the byte is still
  received correctly.
- No runtime baud-rate control: `clkperbits` is a compile-time
  parameter in both cores, not a register.
- No frame-error reporting, since neither core produces one.

## Simulation (APB wrapper)

Loopback test (TX wired directly to RX, bit-aligned timing):
```bash
iverilog -o sim tb_uart_apb_wrapper.v apb_slave.v uart_apb_wrapper.v tx.v uartreciever.v
vvp sim
```

Asynchronous start-bit timing test (enable long before sending, at a
non-bit-aligned offset — this is what actually exercises the RX
start-bit detection logic rather than relying on convenient timing):
```bash
iverilog -o sim_async tb_uart_async.v apb_slave.v uart_apb_wrapper.v tx.v uartreciever.v
vvp sim_async
```

Both should end with `ALL TESTS PASSED`.
