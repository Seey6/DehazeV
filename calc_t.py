KHn125 = 0x00c
S_D = 0xFD8
S_H = 0xE70

print("浮点数:")
S_H_float = S_H / 4096.0
S_D_float = (2-S_H_float)*S_H_float
t = 1-KHn125/3.0/256.0*(1-S_H_float/S_D_float)
print(f"传输率:{t:.6f}")

print("定点数:")
a = S_D - (KHn125*(S_D-S_H)>>8)
inv_a = 0x10000//a
t = S_D * inv_a
print(f"传输率:{t/65536.0}")

