import math

N = 4096
scale = 32767

with open("twiddle_4096.hex","w") as f:
    for k in range(N//2):

        wr = int(round(math.cos(2*math.pi*k/N)*scale))
        wi = int(round(-math.sin(2*math.pi*k/N)*scale))

        wr &= 0xffff
        wi &= 0xffff

        word = (wr<<16) | wi
        f.write(f"{word:08x}\n")
