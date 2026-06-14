# `hermitian_pipe` — Black-Box Reference

Computes the **Hermitian (conjugate) transpose** of a complex matrix:

```
H^H = conj(H)ᵀ
```

For each element: `H^H[c][r].real = H[r][c].real`, `H^H[c][r].imag = -H[r][c].imag`

No multiplication, rounding, or saturation — pure wiring (transpose) plus two's-complement negation of the imaginary part. Intended to sit directly upstream of `matched_filter_pipe_wrap`.

---

## Files Required

| File | Role |
|---|---|
| `polished_hermitian_pipe.sv` | The module (instantiate this) |

---

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `ROWS` | `8` | Rows of input matrix H. Must be ≥ 1. |
| `COLS` | `8` | Columns of input matrix H. Must be ≥ 1. |
| `WL` | `12` | Word length in bits. Rule: `WL = 1 + INT_BITS + FRAC_BITS` |
| `INT_BITS` | `0` | Integer bits (excluding sign) |
| `FRAC_BITS` | `11` | Fractional bits |
| `REGISTER_OUTPUT` | `1` | `1` = outputs are registered (1-cycle latency). `0` = purely combinational (0-cycle latency). |

> **Format rule:** `WL = 1 + INT_BITS + FRAC_BITS` must hold or elaboration aborts with `$fatal`. Word length is identical for inputs and outputs — no precision change occurs.

---

## Port List

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | System clock. Used only when `REGISTER_OUTPUT=1`. |
| `rst_n` | in | 1 | Active-low async reset. Clears output registers when `REGISTER_OUTPUT=1`. Unused in combinational mode but must still be connected. |
| `valid_in` | in | 1 | High when `h_real` / `h_imag` hold a valid input matrix. |
| `h_real` | in | `ROWS×COLS×WL` | Real part of input matrix H. Unpacked array `[0:ROWS-1][0:COLS-1]`. |
| `h_imag` | in | `ROWS×COLS×WL` | Imaginary part of input matrix H. Same shape. |
| `valid_out` | out | 1 | High when outputs are valid. Follows `valid_in` with `LATENCY` cycle delay. |
| `hh_real` | out | `COLS×ROWS×WL` | Real part of H^H. Unpacked array `[0:COLS-1][0:ROWS-1]`. |
| `hh_imag` | out | `COLS×ROWS×WL` | Imaginary part of H^H (negated). Same shape. |

> **Note the transposed shape:** input is `[ROWS][COLS]`, output is `[COLS][ROWS]`. For the common square case (`ROWS == COLS`) the shape is the same and ports wire directly to `matched_filter_pipe`.

---

## Latency

| `REGISTER_OUTPUT` | Latency | Throughput |
|---|---|---|
| `0` (combinational) | **0 cycles** — `valid_out = valid_in` combinationally | Limited by combinational path |
| `1` (registered, default) | **1 cycle** | 1 matrix per cycle |

Latency is also readable via hierarchical reference:
```systemverilog
localparam int HERM_LAT = u_herm.LATENCY;  // 0 or 1
```

---

## Fixed-Point Behaviour

- **Real part:** pure wire copy, zero logic.
- **Imaginary part:** two's-complement negation (`-h_imag[r][c]`). Overflow wraps — the most-negative value (`-2^(WL-1)`) maps to itself, exactly matching MATLAB `fi()` with `OverflowAction='Wrap'`.
- No word-length growth, no truncation, no rounding, no saturation anywhere.

---

## Integration with `matched_filter_pipe_wrap`

This module is designed to feed directly into `matched_filter_pipe_wrap`. For the square case (`ROWS == COLS == N`):

```
hermitian_pipe.hh_real [0:COLS-1][0:ROWS-1]
      ──────────────────────────────────────────► matched_filter_pipe (hh_real/hh_imag load)
hermitian_pipe.hh_imag [0:COLS-1][0:ROWS-1]
```

**Timing rule when chaining:** `matched_filter_pipe` requires H^H to be registered at least one cycle before the corresponding `y_valid`. Using `REGISTER_OUTPUT=1` (default) satisfies this automatically — connect `hermitian_pipe.valid_out` directly to `matched_filter_pipe.hh_load`.

> **No `en` port:** `hermitian_pipe` has no pipeline-enable input. Its output registers update every cycle unconditionally. If the matched filter is stalled (`en=0`), the hermitian output still advances — ensure `hh_load` into the matched filter is not asserted with stale data during a stall. The safest scheme is to deassert `valid_in` to `hermitian_pipe` when no new H matrix is available.

---

## Instantiation Example

```systemverilog
// --- hermitian_pipe (produces H^H from H) ---
hermitian_pipe #(
    .ROWS            ( 8  ),
    .COLS            ( 8  ),
    .WL              ( 12 ),
    .INT_BITS        ( 0  ),
    .FRAC_BITS       ( 11 ),
    .REGISTER_OUTPUT ( 1  )   // 1-cycle latency, registered outputs
) u_herm (
    .clk       ( clk       ),
    .rst_n     ( rst_n     ),
    .valid_in  ( h_valid   ),  // pulse when H is ready
    .h_real    ( H_real    ),  // [0:7][0:7], 12-bit signed
    .h_imag    ( H_imag    ),
    .valid_out ( hh_load   ),  // wire directly to matched filter hh_load
    .hh_real   ( HH_real   ),  // [0:7][0:7], feed to matched filter
    .hh_imag   ( HH_imag   )
);

// --- matched_filter_pipe_wrap (computes ŷ = H^H · y) ---
matched_filter_pipe_wrap #(
    .N ( 8 ), ...
) u_mf (
    .hh_load    ( hh_load   ),  // driven by hermitian_pipe.valid_out
    .hh_re_flat ( ...       ),  // pack HH_real into flat bus
    .hh_im_flat ( ...       ),
    ...
);
```

---

## Operational Checklist

1. Assert `rst_n = 0` for ≥ 2 cycles on power-up (only matters when `REGISTER_OUTPUT=1`).
2. Drive `h_real` / `h_imag` with matrix H and assert `valid_in` for one cycle per matrix.
3. `valid_out` follows `valid_in` by `LATENCY` cycles; `hh_real` / `hh_imag` are valid on that cycle.
4. Connect `valid_out` to `matched_filter_pipe.hh_load` for correct timing.
5. Back-to-back matrices are supported at full throughput in registered mode.
6. Do not assert `hh_load` on the matched filter during a stall (`en=0`) unless the intent is to genuinely update the coefficient bank during the stall.
