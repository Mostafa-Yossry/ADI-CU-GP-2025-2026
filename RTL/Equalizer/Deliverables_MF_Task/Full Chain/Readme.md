### **Module Documentation: `hermitian_mf_chain**`

#### **1. Purpose**

The `hermitian_mf_chain` is a glue-logic wrapper that cascades two verified IP blocks: a **Hermitian Transpose generator** (`hermitian_pipe`) and a **Matched Filter** (`matched_filter_pipe_wrap`). It performs the complex vector-matrix operation:


$$g_y = H^H \cdot y$$


where $H^H = \text{conj}(H)^T$. It manages coefficient synchronization, bus flattening, and coefficient holding during streaming operations.

---

#### **2. Interface Summary**

| Port Type | Name | Width/Description |
| --- | --- | --- |
| **Control** | `clk`, `rst_n` | Standard system signals. |
| **Control** | `en` | Pipeline enable for the Matched Filter stage. |
| **Input** | `h_valid` | Strobe for new $H$ matrix (latches into $H^H$ compute). |
| **Input** | `h_real`, `h_imag` | $N \times N$ unpacked arrays ($Q1.11$ default). |
| **Input** | `y_valid` | Input strobe for vector $y$. |
| **Input** | `y_re_flat`, `y_im_flat` | $N \times WL\_IN$ flat buses for input vector $y$. |
| **Output** | `gy_valid` | Strobe for computed $g_y$ output. |
| **Output** | `gy_re_flat`, `gy_im_flat` | $N \times MF\_WL\_OUT$ flat buses for result $g_y$. |

---

#### **3. Critical Constraints**

* **Dimensionality:** $N$ must be exactly $8$ (fixed MF core logic).
* **Timing:** $H$ must be updated by asserting `h_valid`. The wrapper handles the one-cycle delay for the Hermitian computation and an additional cycle for internal coefficient register stabilization before the MF can accept $y$ data.
* **Stability:** Coefficients are held in an internal register (`coef_hold`) once computed. The system expects coefficients to remain stable throughout the entire burst of $y$ vectors.

---

#### **4. Latency Analysis**

The total latency from `h_valid` assertion to the first `gy_valid` output is **13 cycles** (for `HERM_REG=1`):

1. **Cycle 0:** $H$ input presented; `h_valid` high.
2. **Cycle 1:** Hermitian result available (`herm_valid_out` high); `coef_hold` registers latch $H^H$.
3. **Cycle 2:** `hh_load` strobe fires; internal MF coefficients update.
4. **Cycle 2–12:** Matched Filter pipeline latency (10 cycles).
5. **Cycle 12:** First $g_y$ result produced.

---

#### **5. Functional Architecture**

The module acts as a "black box" where the user provides the matrix $H$ and the data vector $y$. The internal sequencing ensures that the Matched Filter always works on the most recently computed Hermitian transpose without requiring the user to manage the pipeline synchronization between the two blocks.

---

#### **6. Parameters**

* **`N`**: Fixed at 8.
* **`WL_IN / FL_IN / INT_BITS`**: Define input precision (default: $Q1.11$, 12-bit).
* **`MF_*`**: Pass-through parameters that configure the internal Matched Filter precision/word-lengths.
* **`HERM_REG`**: Toggle between registered output ($1$) or combinatorial ($0$) for the Hermitian block.