# Loon Parallel Execution — Stage 5.5 Specification

## Overview

Loon programs are parallel by default. Pure functions (declared `[]`) can run in parallel without coordination. IO functions require explicit sequencing via `sequential {}` blocks.

## Semantics

```loon
// These CAN run in parallel — both are pure
let a: Int = expensive_pure_1();
let b: Int = expensive_pure_2();
let c: Int = a + b;  // implicit barrier — waits for both

// These MUST run sequentially — both have IO
sequential {
    do write_header();
    do write_body();
    do write_footer();
}
```

## Effect-based safety

The effect system guarantees parallel safety:

- `[]` (pure) functions: no side effects, safe to run in parallel
- `[IO]` functions: side effects, must be sequenced
- `[Audit]` functions: write audit logs, must be sequenced
- `[Crypto]` functions: may use shared state, must be sequenced

The compiler automatically determines which `let` bindings can be evaluated in parallel based on their effect declarations and data dependencies.

## Runtime model

### Green threads (future)

Parallel tasks are scheduled on a thread pool. Each task runs on a green thread — lightweight, user-space scheduled, no OS thread per task.

### Work stealing

Idle threads steal tasks from busy threads' queues. Standard work-stealing algorithm for load balancing.

## Implementation Plan

### Phase 1: Analysis pass

Add a dependency analysis pass before codegen:
1. For each basic block, identify independent `let` bindings
2. Pure bindings with no data dependencies → mark as parallelizable
3. IO bindings or bindings with dependencies → mark as sequential

### Phase 2: Codegen

For parallelizable bindings:
1. Create a task for each independent binding
2. Submit to thread pool
3. Wait for all tasks before the next sequential point

### Phase 3: Runtime

1. Implement a thread pool (using pthreads on native, Web Workers on WASM)
2. Implement green threads with small stacks
3. Work-stealing scheduler

## Interaction with privacy types

Parallel tasks cannot share `Sensitive` or `ZeroOnDrop` values between threads. The ownership model ensures sensitive data stays on the thread that created it.

```loon
let pw: Sensitive<String> = read_password();
// pw cannot be moved to a parallel task
// It stays on the current thread
```
