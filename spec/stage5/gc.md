# Loon Garbage Collector — Stage 5.4 Specification

## Overview

Replace the bump allocator with a mark-and-sweep garbage collector. The bump allocator works for short-lived programs but leaks memory for long-running servers. The GC reclaims unreachable objects while respecting ZeroOnDrop semantics.

## Design: Simple mark-and-sweep

### Phase 1: Mark

Starting from roots (stack frames, global variables), trace all reachable objects by following pointers. Mark each reachable object.

### Phase 2: Sweep

Walk the heap. Any unmarked object is unreachable — reclaim its memory. For ZeroOnDrop objects, zero the memory BEFORE adding to the free list.

### Phase 3: Compact (future)

After sweep, optionally compact the heap to reduce fragmentation. This requires updating all pointers — expensive but eliminates fragmentation.

## Root identification

Roots are:
1. Local variables on the stack (identified by the stack frame layout)
2. Global variables (the `gs`, `gb`, `gt`, `gn` arrays in the compiler)
3. Closure capture structs on the heap

The compiler must emit a stack map for each function — a table that identifies which stack slots contain pointers vs integers.

## Object header

Every heap object gets a small header:

```
[mark_bit: 1 byte][type_tag: 1 byte][size: 2 bytes][padding: 4 bytes][data...]
```

- `mark_bit`: 0 or 1, used by the mark phase
- `type_tag`: 0=raw bytes, 1=array of pointers, 2=ADT, 3=closure
- `size`: object size in 8-byte units

The header is 8 bytes — same alignment as the current bump allocator.

## ZeroOnDrop interaction

When the sweep phase finds an unreachable ZeroOnDrop object:
1. Zero all data bytes (not the header)
2. Then add to the free list

This ensures sensitive data doesn't survive in freed memory.

## Trigger

GC runs when:
- The heap usage exceeds 75% of the current heap size
- Or when explicitly requested via `do gc_collect()` (new builtin with `[GC]` effect)

## Implementation Plan

1. Add object headers to all heap allocations
2. Build a root scanner that walks the stack
3. Implement mark phase (recursive trace)
4. Implement sweep phase (linear scan, zero ZeroOnDrop, build free list)
5. Replace malloc's bump pointer with free-list-first allocation
6. Add GC trigger to allocation path
