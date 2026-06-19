# `hermitian_mf_chain_comb`

Computes `x = H^H · y` by chaining `hermitian_pipe` (computes H^H from H) into `matched_filter_pipe_wrap` using a **pure-combinational MF core** (2-cycle latency, I/O regs only). Black-box integration wrapper — internals are pre-verified IP.

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `N` | 8 | Matrix dimension — **must be 8** (elaboration fatal otherwise) |
| `WL_IN` | 12 | Input word length (Q1.11) |
| `FL_IN` | 11 | Input fractional bits |
| `INT_BITS` | 0 | Input integer bits (`WL_IN = 1 + INT_BITS + FL_IN`, checked) |
| `MF_WL_W` | 16 | MF internal word length |
| `MF_FL_W` | 15 | MF internal fractional bits |
| `MF_WL_PROD` | 32 | MF product word length |
| `MF_FL_PROD` | 30 | MF product fractional bits |
| `MF_FL_Q2`..`MF_FL_Q5` | 14,13,12,11 | MF internal accumulator Q-formats |
| `MF_WL_OUT` | 16 | Output word length |
| `MF_FL_OUT` | 11 | Output fractional bits — **must equal `MF_FL_Q5`** (checked) |
| `HERM_REG` | 1 | `hermitian_pipe` output register mode (1 = registered, recommended) |

## Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock |
| `rst_n` | in | 1 | Async active-low reset |
| `en` | in | 1 | MF pipeline enable only (does not gate Hermitian block or coef load) |
| `h_valid` | in | 1 | Strobe: H matrix valid at input |
| `h_real` / `h_imag` | in | `[0:N-1][0:N-1]` signed `WL_IN` | Channel matrix H, unpacked 2D array |
| `y_valid` | in | 1 | Strobe: y vector valid at input |
| `y_re_flat` / `y_im_flat` | in | `N*WL_IN` | y vector, flattened, `flat[k*WL_IN +: WL_IN]` |
| `x_valid` | out | 1 | x output valid |
| `x_re_flat` / `x_im_flat` | out | `N*MF_WL_OUT` | x = H^H·y, flattened, same packing convention |

Flat bus packing convention (in and out): `flat[(r*N + c)*WL_IN +: WL_IN] = val[r][c]`.

No `gy_enable` port — the combinational MF core ties it low internally and this wrapper does not expose it.

## Usage / Timing

1. Present `H` on `h_real`/`h_imag`, pulse `h_valid` for 1 cycle.
2. Coefficients are internally captured, held, and loaded into the MF core automatically — no user action needed.
3. Starting **2 cycles after `h_valid`**, stream `y` vectors on `y_re_flat`/`y_im_flat` with `y_valid` pulsed each cycle.
4. `x_valid` pulses high when `x` is valid on `x_re_flat`/`x_im_flat`.

Coefficients remain held/stable for all subsequent `y` vectors until a new `h_valid` is issued — no need to reload H per y vector.

## Latency

**5 cycles** from `h_valid` to the first `x_valid`:

`1 (hermitian) + 1 (coef-hold settle) + 1 (hh_load register) + 2 (comb MF I/O regs) = 5`

**Throughput: 1 output vector/cycle** in steady state once `y_valid` is streamed back-to-back (no MF pipeline stalls, since the MF core itself is combinational — only 2 cycles of I/O registration).
