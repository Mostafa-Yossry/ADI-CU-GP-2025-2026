import math

N = 4096
scale = 32767
NUM_BUTTERFLIES = N // 8  # 512

with open("twiddle_packed_radix8.hex", "w") as f:
    for k in range(NUM_BUTTERFLIES):
        word_224 = 0
        
        # Calculate W1 through W7 and pack them.
        # m ranges from 1 to 7. 
        # m=1 occupies bits [31:0], m=7 occupies bits [223:192]
        for m in range(1, 8):
            angle = 2 * math.pi * (m * k) / N
            wr = int(round(math.cos(angle) * scale))
            wi = int(round(-math.sin(angle) * scale))

            wr &= 0xffff
            wi &= 0xffff

            # Combine Real and Imag into a 32-bit complex word
            complex_word = (wr << 16) | wi
            
            # Shift the 32-bit word into its correct slot in the 224-bit bus
            word_224 |= (complex_word << ((m - 1) * 32))

        # Write as a zero-padded 56-character hex string (224 bits / 4)
        f.write(f"{word_224:056x}\n")

print("Generated twiddle_packed_radix8.hex successfully.")