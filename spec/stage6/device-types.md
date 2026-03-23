# Loon Device Types — Stage 6.0 Specification

## Overview

Device types extend the type system to track where data lives — CPU, GPU, TPU, or specific device instances. The compiler prevents mixing data from incompatible devices at compile time.

## Syntax

```loon
type Tensor<T>[Device] {
    data: Array<T>,
    shape: List<Int>,
}

fn matmul(
    a: Tensor<Float32>[GPU:0],
    b: Tensor<Float32>[GPU:0]
) [Compute:GPU] -> Tensor<Float32>[GPU:0] {
    // GPU kernel implementation
}

fn main() [IO, Compute:GPU] -> Unit {
    let cpu_data: Tensor<Float32>[CPU] = load_data("input.csv");
    let gpu_data: Tensor<Float32>[GPU:0] = do transfer(cpu_data, GPU:0);
    let result: Tensor<Float32>[GPU:0] = matmul(gpu_data, gpu_data);
    // matmul(cpu_data, gpu_data);  ← COMPILE ERROR: device mismatch
}
```

## Device annotations

```
[CPU]       — data on main CPU memory
[GPU:N]     — data on GPU device N
[TPU:N]     — data on TPU device N
[Device]    — generic device parameter
```

## Transfer operations

Moving data between devices requires explicit `transfer()`:

```loon
fn transfer<T>(data: Tensor<T>[From], to: DeviceId) [IO] -> Tensor<T>[To] {
    // Runtime copy between devices
}
```

The transfer function has IO effect because it involves device communication.

## Compute effects

```loon
[Compute:GPU]   — function executes GPU kernels
[Compute:TPU]   — function executes TPU kernels
[Compute:CPU]   — explicit CPU computation (default)
```

Functions with `[Compute:GPU]` can only be called when a GPU context is available.

## Implementation Plan

### Phase 1: Type system extension

1. Add device annotation syntax: `[GPU:0]` after type
2. Store device info in type_info field (extend compound encoding)
3. Type checker: verify device compatibility at function call boundaries

### Phase 2: Transfer operations

1. Implement `transfer()` builtin
2. Runtime: CPU→GPU copy via CUDA/OpenCL/WebGPU
3. Device capability detection at program startup

### Phase 3: Compute kernels

1. Compile GPU functions to SPIR-V or PTX via LLVM
2. Launch kernels through the effect system
3. Memory management: device-specific allocators

## Privacy types + device types

Device boundaries are treated like trust boundaries for privacy:

```loon
let sensitive_tensor: Tensor<Sensitive<Float32>>[CPU] = ...;
// transfer(sensitive_tensor, GPU:0);  ← COMPILE ERROR
// Cannot transfer Sensitive data to GPU — GPU memory is not zeroed on free
```

This prevents sensitive data from being left in GPU memory where other processes could read it.
