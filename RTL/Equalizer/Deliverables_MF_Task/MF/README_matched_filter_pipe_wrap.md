# `matched_filter_pipe_wrap` — Black-Box Reference

Computes the MIMO matched-filter operation **ŷ = H^H · y** on complex vectors,
fully pipelined, one result per clock cycle at full throughput.  
All ports use flat packed buses — no unpacked arrays.

---

## Files Required

| File | Role |
|---|---|
| `matched_filter_pipe_wrap.sv` | Top-level wrapper (instantiate this) |
| `polished_new_matched_filter.sv` | Core pipeline (must be in the same compile list) |

---

## Parameters

All parameters have working defaults for an 8×8, Q0.11 input / Q4.11 output system.
**You must keep the three format consistency rules satisfied** (shown below) or elaboration will abort with a `$fatal`.

| Parameter | Default | Description |
|---|---|---|
| `N` | `8` | System dimension — both rows and columns of H^H. **Must be a power of two.** |
| `MF_WL_IN` | `12` | Input word length (bits). Rule: `MF_WL_IN = 1 + MF_INT_BITS_IN + MF_FRAC_BITS_IN` |
| `MF_INT_BITS_IN` | `0` | Integer bits of input (excluding sign) |
| `MF_FRAC_BITS_IN` | `11` | Fractional bits of input |
| `MF_INTERNAL_WL` | `16` | Internal word length (after widening, before multiply). Must be ≥ `MF_WL_IN`. Rule: `MF_INTERNAL_WL = 1 + MF_INTERNAL_INT_BITS + MF_INTERNAL_FRAC_BITS` |
| `MF_INTERNAL_INT_BITS` | `0` | Internal integer bits. Must be ≥ `MF_INT_BITS_IN` |
| `MF_INTERNAL_FRAC_BITS` | `15` | Internal fractional bits. Must be ≥ `MF_FRAC_BITS_IN` |
| `MF_WL_OUT` | `16` | Output word length (bits). Rule: `MF_WL_OUT = 1 + MF_INT_BITS_OUT + MF_FRAC_BITS_OUT` |
| `MF_INT_BITS_OUT` | `4` | Integer bits of output (excluding sign) |
| `MF_FRAC_BITS_OUT` | `11` | Fractional bits of output |

> **Note:** output elements are `MF_WL_OUT` bits wide, which may differ from `MF_WL_IN`.
> With defaults, inputs are 12-bit and outputs are 16-bit.

---

## Port List

### Clock / Reset / Enable

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | System clock. All registers are positive-edge triggered. |
| `rst_n` | in | 1 | Active-low asynchronous reset. Hold low for ≥ 2 cycles before use. |
| `en` | in | 1 | Pipeline enable. Hold high for normal operation. Pulling low freezes **all** pipeline stages simultaneously — no data is lost; it resumes correctly when re-asserted. Does **not** gate `hh_load`. |

### H^H Coefficient Load (slow / one-shot path)

| Port | Dir | Width | Description |
|---|---|---|---|
| `hh_load` | in | 1 | Latch strobe. Assert for **exactly one** rising clock edge. |
| `hh_re_flat` | in | `N×N×MF_WL_IN` | Real part of H^H, row-major packed (see packing below). Must be stable on the `hh_load` posedge. |
| `hh_im_flat` | in | `N×N×MF_WL_IN` | Imaginary part of H^H, same packing. |

> **Timing rule:** `hh_load` must be registered **at least one cycle before** the first `y_valid` that uses those coefficients. A new `hh_load` can be issued on the same negedge as the preceding frame's `y_valid` (overlap loading). `hh_load` is **not** gated by `en` and takes effect even when the pipeline is stalled.

### Streaming y Input (one vector per cycle)

| Port | Dir | Width | Description |
|---|---|---|---|
| `y_valid` | in | 1 | Assert high for one cycle when `y_re/im_flat` holds a valid input vector. Back-to-back assertion (every cycle) is supported. |
| `y_re_flat` | in | `N×MF_WL_IN` | Real part of y, LSB-first packed. |
| `y_im_flat` | in | `N×MF_WL_IN` | Imaginary part of y, LSB-first packed. |

### Outputs

| Port | Dir | Width | Description |
|---|---|---|---|
| `valid_out` | out | 1 | High for one cycle when `x_re/im_flat` holds a valid result. |
| `gy_enable` | out | 1 | Sticky flag. Stays 0 after reset; latches to 1 on the first `valid_out` and stays 1 until the next reset. Use this to gate downstream logic until the pipeline has produced its first output. |
| `x_re_flat` | out | `N×MF_WL_OUT` | Real part of ŷ = H^H·y, LSB-first packed. Valid when `valid_out` is high. |
| `x_im_flat` | out | `N×MF_WL_OUT` | Imaginary part of ŷ, same packing. |

---

## Bus Packing Convention

All buses are **LSB-first** — element 0 occupies the least-significant bits.

**y / x vectors** (`N` elements):
```
flat[ k * WL +: WL ]  =  element[k]        k = 0 .. N-1
```

**H^H matrix** (`N×N` elements, row-major):
```
flat[ (r*N + c) * MF_WL_IN +: MF_WL_IN ]  =  H^H[r][c]
                                               r = row, c = col
```

**SystemVerilog slice syntax to extract element k from y:**
```systemverilog
y_re_flat[ k * MF_WL_IN +: MF_WL_IN ]
```

---

## Pipeline Latency

```
LATENCY = 1 + $clog2(N)  cycles
```

| N | Latency |
|---|---|
| 4 | 3 cycles |
| **8** | **4 cycles** (default) |
| 16 | 5 cycles |
| 32 | 6 cycles |

`valid_out` asserts exactly `LATENCY` cycles after the corresponding `y_valid`.  
Throughput is **1 result per clock cycle** at full rate (back-to-back `y_valid`).

If you need the latency value at elaboration time in a wrapping module:
```systemverilog
localparam int MY_LAT = u_wrap.u_mf.LATENCY;
```

---

## Fixed-Point Arithmetic

The core uses **convergent rounding (round-half-to-even)** and **wrap-on-overflow** at every stage, matching MATLAB `fimath` with `RoundingMethod='Convergent'`, `OverflowAction='Wrap'`. Products are computed at full precision internally before being rounded to the output format.

To convert integer output values to real:
```
real_value = signed_integer_output / 2^MF_FRAC_BITS_OUT
```
With defaults: divide by **2048**.

---

## Instantiation Example (defaults)

```systemverilog
matched_filter_pipe_wrap #(
    .N                   ( 8  ),
    .MF_WL_IN            ( 12 ),
    .MF_INT_BITS_IN      ( 0  ),
    .MF_FRAC_BITS_IN     ( 11 ),
    .MF_INTERNAL_WL      ( 16 ),
    .MF_INTERNAL_INT_BITS ( 0 ),
    .MF_INTERNAL_FRAC_BITS(15 ),
    .MF_WL_OUT           ( 16 ),
    .MF_INT_BITS_OUT     ( 4  ),
    .MF_FRAC_BITS_OUT    ( 11 )
) u_mf_wrap (
    .clk        ( clk        ),
    .rst_n      ( rst_n      ),
    .en         ( 1'b1       ),
    .hh_load    ( hh_load    ),
    .hh_re_flat ( hh_re_flat ),  // [N*N*12-1:0]
    .hh_im_flat ( hh_im_flat ),  // [N*N*12-1:0]
    .y_valid    ( y_valid    ),
    .y_re_flat  ( y_re_flat  ),  // [N*12-1:0]
    .y_im_flat  ( y_im_flat  ),  // [N*12-1:0]
    .valid_out  ( valid_out  ),
    .gy_enable  ( gy_enable  ),
    .x_re_flat  ( x_re_flat  ),  // [N*16-1:0]
    .x_im_flat  ( x_im_flat  )   // [N*16-1:0]
);
```

---

## Operational Checklist

1. Assert `rst_n = 0` for at least 2 cycles on power-up, then release.
2. Drive `hh_re/im_flat` with H^H and pulse `hh_load` for one cycle.
3. Wait at least one cycle after `hh_load` before asserting `y_valid`.
4. Drive `y_re/im_flat` and assert `y_valid` for each input vector.
5. Monitor `valid_out` — results appear `LATENCY` cycles later on `x_re/im_flat`.
6. To update H^H mid-stream: load new coefficients one `hh_load` cycle before the first `y_valid` that should use them. Overlap with a running `y_valid` stream is supported.
7. To stall: deassert `en`. No data is lost. Re-assert to resume; latency for in-flight frames increases by the number of stall cycles.
