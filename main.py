import cv2
import numpy as np


def min_filter_custom(img, ksize):
    # Custom min filter to match hardware implementation (hierarchical or sliding window)
    # For prototype, standard erosion is fine, but paper uses 15x15
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (ksize, ksize))
    return cv2.erode(img, kernel)

def estimate_atmospheric_light(img):
    # Paper: Downsample by 2
    h, w = img.shape[:2]
    # ds_img = cv2.resize(img, (w//2, h//2), interpolation=cv2.INTER_NEAREST)
    ds_img = img
    # Paper: 15x15 min filter on downsampled image
    min_img = min_filter_custom(ds_img, 7)
    
    # Dark channel of min_filtered image
    dark_channel = np.min(min_img, axis=2)
    
    # Find brightest pixel in dark channel
    flat_idx = np.argmax(dark_channel)
    y, x = np.unravel_index(flat_idx, dark_channel.shape)
    
    A = ds_img[y, x]
    
    # Paper: A cannot be less than 100 (assuming 8-bit range)
    A = np.maximum(A, 100)
    
    print(f"Estimated A: {A}")
    return A / 255.0

def calculate_saturation(img_norm):
    # Eq 9: S_M(x) = 1 - min(M)/K_M
    # K_M = mean(M)
    
    min_c = np.min(img_norm, axis=2)
    mean_c = np.mean(img_norm, axis=2)
    
    # Avoid divide by zero
    mean_c = np.maximum(mean_c, 1e-6)
    
    sat = 1 - min_c / mean_c
    return sat, mean_c

def dehaze(img):
    img_float = img.astype(np.float32) / 255.0
    
    # 1. Estimate A
    A = estimate_atmospheric_light(img)
    
    # Normalize H with A
    # Handle A=0 case (though A>=100/255 constraint prevents this)
    A_safe = np.maximum(A, 1e-6)
    H_norm = img_float / A_safe
    
    # 2. Calculate Saturation of H
    S_H, K_Hn = calculate_saturation(H_norm)
    
    # 3. Estimate Saturation of D (Eq 15)
    # S_D'(x) = S_H(x) * (2.0 - S_H(x))
    S_D = S_H * (2.0 - S_H)
    
    # 4. Estimate Transmission (Eq 13 / 14)
    # Paper mentions psi = 1.25
    psi = 1.25
    
    # Eq 13 modified with psi:
    # t(x) = 1 - psi * K_Hn * (1 - S_H / S_D)
    # Note: S_H / S_D can be unstable if S_D is 0.
    # If S_H is 0, S_D is 0. Limit ratio.
    
    ratio = np.divide(S_H, S_D, out=np.ones_like(S_H), where=S_D!=0)
    
    t = 1 - psi * K_Hn * (1 - ratio)
    
    # Clip transmission
    t = np.clip(t, 0.1, 1.0)
    
    # 5. Scene Restoration (Eq 2)
    # D(x) = (H(x) - A) / t(x) + A
    
    t_stacked = np.dstack([t, t, t])
    D = (img_float - A) / t_stacked + A
    
    D = np.clip(D, 0, 1)
    
    return (D * 255).astype(np.uint8), t

if __name__ == "__main__":
    # Generate Input
    input_img = cv2.imread("haze.jpg").astype(np.uint8) # Small size for faster sim
    input_img = cv2.resize(input_img,(320,240))
    cv2.imwrite("input.png", input_img)
    cv2.imwrite("input.ppm", input_img) # For C++ sim
    print("Generated input.png and input.ppm")
    
    # Run Dehazing
    output_img, trans_map = dehaze(input_img)
    
    cv2.imwrite("golden_output.png", output_img)
    cv2.imwrite("golden_output.ppm", output_img) # For C++ sim
    cv2.imwrite("transmission.png", (trans_map * 255).astype(np.uint8))
    print("Generated golden_output.png/ppm and transmission.png")
