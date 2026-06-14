
# `matched_filter_pipe_wrap` — Black-Box Reference

Computes the MIMO matched-filter operation on complex vectors:

$$\mathbf{z} = \mathbf{H}^H \cdot \mathbf{y}$$

The module is fully spatially unrolled and pipelined, delivering one result per clock cycle at full steady-state throughput. All ports use flat, contiguous packed buses to simplify integration with top-level interconnects (no unpacked arrays at the boundary).

---

## Files Required

| File | Role |
|---|---|
| `matched_filter_pipe_wrap.sv` | Top-level flat-bus wrapper (instantiate this) |
| `matched_filter_unrolled.sv` | Core unrolled pipeline engine (must be in the same compile list) |

---

## Parameters

All parameters have verified defaults for an $8 \times 8$ system operating with Q1.11 inputs and Q5.11 outputs. Elaboration-time sanity checks will abort compilation with a `$fatal` error if format consistency rules are violated.

### System Dimension
| Parameter | Default | Description |
|---|---|---|
| `N` | `8` | System dimension (both rows and columns). **Must equal 8** (enforced by core). |

### Fixed-Point Formats
| Parameter | Default | Type / Format | Description / Constraints |
|---|---|---|---|
| `MF_WL_IN` | `12` | Input Word Length | Total bits for $\mathbf{H}^H$ and $\mathbf{y}$ inputs |
| `MF_FL_IN` | `11` | Input Fraction Bits | Q1.11 format |
| `MF_WL_W` | `16` | Widened Word Length | Internal width after zero-padding, before multiplication. **Must be $\ge$ `MF_WL_IN`** |
| `MF_FL_W` | `15` | Widened Fraction Bits | Q1.15 format. **Must be $\ge$ `MF_FL_IN`** |
| `MF_WL_PROD` | `32` | Product Word Length | Full-precision multiplication result |
| `MF_FL_PROD` | `30` | Product Fraction Bits | Q2.30 format |
| `MF_WL_OUT` | `16` | Output Word Length | Total bits for the final output vector $\mathbf{z}$ |
| `MF_FL_OUT` | `11` | Output Fraction Bits | Q5.11 format. **Must equal `MF_FL_Q5`** |

### Accumulator Stage Fraction Bits (16-Bit Accumulators)
| Parameter | Default | Format | Description |
|---|---|---|---|
| `MF_FL_Q2` | `14` | Q2.14 | Accumulator stage fraction bits ($k=1$) |
| `MF_FL_Q3` | `13` | Q3.13 | Accumulator stage fraction bits ($k=2$) |
| `MF_FL_Q4` | `12` | Q4.12 | Accumulator stage fraction bits ($k=3,4$) |
| `MF_FL_Q5` | `11` | Q5.11 | Accumulator stage fraction bits ($k=5 \dots 8$) |

---

## Port List

### Clock / Reset / Enable

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | `1` | System clock. All internal registers are positive-edge triggered. |
| `rst_n` | in | `1` | Active-low asynchronous reset. |
| `en` | in | `1` | Pipeline enable. Assert high for normal operation. Pulling low freezes all pipeline stages simultaneously without data loss. Does **not** gate `hh_load`. |

### $\mathbf{H}^H$ Coefficient Load (Slow / One-Shot Path)

| Port | Dir | Width | Description |
|---|---|---|---|
| `hh_load` | in | `1` | Latch strobe. Assert for **exactly one** rising clock edge to load coefficients. |
| `hh_re_flat` | in | `N * N * MF_WL_IN` | Real part of $\mathbf{H}^H$, row-major packed. Must be stable on the `hh_load` posedge. |
| `hh_im_flat` | in | `N * N * MF_WL_IN` | Imaginary part of $\mathbf{H}^H$, row-major packed. |

> **Timing Rule:** `hh_load` must be registered **at least one cycle before** the first `y_valid` that uses those coefficients. Overlap loading is supported (a new matrix can be safely registered while old data streams through). `hh_load` ignores the `en` stall signal.

### Streaming $\mathbf{y}$ Vector Input (One Vector per Cycle)

| Port | Dir | Width | Description |
|---|---|---|---|
| `y_valid` | in | `1` | Assert high for one cycle when `y_re_flat` and `y_im_flat` hold valid data. Supports back-to-back assertions every cycle. |
| `y_re_flat` | in | `N * MF_WL_IN` | Real part of input vector $\mathbf{y}$, LSB-first packed. |
| `y_im_flat` | in | `N * MF_WL_IN` | Imaginary part of input vector $\mathbf{y}$, LSB-first packed. |

### Outputs

| Port | Dir | Width | Description |
|---|---|---|---|
| `valid_out` | out | `1` | High for one cycle when `x_re_flat` and `x_im_flat` hold a valid computed vector. |
| `gy_enable` | out | `1` | Sticky pipeline-ready flag. Stays `0` after reset; latches to `1` on the very first `valid_out` pulse and remains `1` until the next reset. |
| `x_re_flat` | out | `N * MF_WL_OUT` | Real part of output vector $\mathbf{z}$, LSB-first packed. Valid when `valid_out` is high. |
| `x_im_flat` | out | `N * MF_WL_OUT` | Imaginary part of output vector $\mathbf{z}$, LSB-first packed. |

---

## Bus Packing Convention

All flat array buses are packed **LSB-first**, meaning element 0 occupies the least-significant bit slices.

### $\mathbf{y}$ Input / $\mathbf{z}$ Output Vectors ($N$ elements)
```flat
flat[ k * WL +: WL ] = element[k]           // k = 0 .. N-1

```

### $\mathbf{H}^H$ Matrix ($N \times N$ elements, row-major)

```flat
flat[ (r*N + c) * MF_WL_IN +: MF_WL_IN ] = H^H[r][c]   // r = row, c = col

```

### SystemVerilog Extraction Examples

```systemverilog
// Extracting element 'k' from the real y vector
wire signed [MF_WL_IN-1:0] y_element_k = y_re_flat[ k * MF_WL_IN +: MF_WL_IN ];

// Extracting row 'r', column 'c' from the real matrix
wire signed [MF_WL_IN-1:0] hh_element_rc = hh_re_flat[ (r*N + c)*MF_WL_IN +: MF_WL_IN ];

```

---

## Pipeline Latency

Because the internal architecture is spatially unrolled into 8 MAC steps across 2 processing stages with a sequential accumulator chain and an output register, the latency is fixed:

$$\text{LATENCY} = 10 \text{ clock cycles}$$

`valid_out` asserts exactly **10 cycles** after its corresponding `y_valid`. Steady-state throughput is maintained at **1 output vector per clock cycle** under a continuous input stream.

---

## Fixed-Point Scaling

The core module performs convergent rounding (round-half-to-even) and wraps on overflow at each arithmetic stage, matching the behavior of MATLAB's `fimath` configured for `RoundingMethod='Convergent'` and `OverflowAction='Wrap'`.

To convert the integer bits on the output bus back to real-world floating-point values:

$$\text{real\_value} = \frac{\text{signed\_integer\_output}}{2^{\text{MF\_FL\_OUT}}}$$

Using default parameter values, divide the output integers by **2048** ($2^{11}$).

---

## Instantiation Example (Defaults)

```systemverilog
matched_filter_pipe_wrap #(
    .N                      ( 8  ), // Enforced 8x8 system
    .MF_WL_IN               ( 12 ), // Q1.11 input
    .MF_FL_IN               ( 11 ),
    .MF_WL_W                ( 16 ), // Q1.15 widened
    .MF_FL_W                ( 15 ),
    .MF_WL_PROD             ( 32 ), // Q2.30 product
    .MF_FL_PROD             ( 30 ),
    .MF_FL_Q2               ( 14 ), // Internal stages
    .MF_FL_Q3               ( 13 ),
    .MF_FL_Q4               ( 12 ),
    .MF_FL_Q5               ( 11 ),
    .MF_WL_OUT              ( 16 ), // Q5.11 output
    .MF_FL_OUT              ( 11 )
) u_mf_pipe_wrap (
    .clk        ( clk        ),
    .rst_n      ( rst_n      ),
    .en         ( en         ),
    
    // Coefficient Config Path
    .hh_load    ( hh_load    ),
    .hh_re_flat ( hh_re_flat ), // [8*8*12-1:0]
    .hh_im_flat ( hh_im_flat ), // [8*8*12-1:0]
    
    // Streaming Input Path
    .y_valid    ( y_valid    ),
    .y_re_flat  ( y_re_flat  ), // [8*12-1:0]
    .y_im_flat  ( y_im_flat  ), // [8*12-1:0]
    
    // Streaming Output Path
    .valid_out  ( valid_out  ),
    .gy_enable  ( gy_enable  ),
    .x_re_flat  ( x_re_flat  ), // [8*16-1:0]
    .x_im_flat  ( x_im_flat  )  // [8*16-1:0]
);

```

---

## Operational Checklist

1. **Power-Up Reset:** Assert `rst_n = 0` for at least 2 clock cycles, then deassert.
2. **Coefficient Loading:** Drive `hh_re_flat` and `hh_im_flat` with the matrix coefficients, then pulse `hh_load` high for exactly one clock cycle.
3. **Pipeline Priming:** Wait at least one clock cycle after loading coefficients before asserting the first `y_valid`.
4. **Data Streaming:** Drive your vector data on the `y_flat` lines and assert `y_valid`. You can drive data back-to-back continuously.
5. **Output Capture:** Capture processed vectors on `x_re_flat` and `x_im_flat` when `valid_out` goes high (exactly 10 clock cycles later).
6. **Coefficient Hot-Swapping:** To update $\mathbf{H}^H$ mid-stream, cycle `hh_load` one clock cycle before the data vector intended for the new matrix arrives.
7. **Stalling the Pipeline:** Drive `en = 0` to halt the pipeline. No data will be dropped or corrupted; when `en` returns high, processing resumes with the latency stretched precisely by the duration of the stall.

```

```