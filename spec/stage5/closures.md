# Loon Closures — Stage 5.3 Specification

## Overview

Closures are anonymous functions that capture variables from their enclosing scope. Loon closures capture by value (not by reference). The effect system applies to closures — a closure's effects are inferred from its body.

## Syntax

```loon
// Anonymous function
let double = fn(x: Int) [] -> Int { x * 2 };

// As argument to higher-order function
let result = list |> map(fn(x: Int) [] -> Int { x + 1 });

// Capturing from enclosing scope
let multiplier: Int = 3;
let scale = fn(x: Int) [] -> Int { x * multiplier };
// scale captures `multiplier` by value
```

## Type syntax

Function types for closures:

```loon
fn(Int) -> Int              // function taking Int, returning Int, no effects
fn(String) [IO] -> Unit     // function taking String, with IO effect
fn(Int, Int) -> Bool         // two-argument function
```

## Capture semantics

Closures capture by **value**. The captured value is copied at closure creation time.

```loon
let x: Int = 10;
let f = fn() [] -> Int { x };
// x is captured as 10
// modifying x after this has no effect on f's result
```

## Privacy type interaction

Closures cannot capture `Sensitive` values and pass them to non-Audit contexts:

```loon
let pw: Sensitive<String> = get_password();
let leak = fn() [IO] -> Unit { do print(pw); };  // COMPILE ERROR
// Cannot capture Sensitive value in a closure that logs it
```

This is enforced at the capture site — the closure's body is type-checked with the captured variable's privacy level.

## Runtime representation

A closure is a struct containing:
1. A function pointer (to the anonymous function's generated code)
2. Captured values (each stored by value)

```
[fn_ptr: 8 bytes][capture_0: 8 bytes][capture_1: 8 bytes]...
```

Calling a closure: the caller passes the closure struct as an implicit first argument. The generated function reads captured values from the struct.

## Implementation Plan

### Phase 1: Parser

1. Recognize `fn(params) [effects] -> RetType { body }` in expression position
2. Create a NODE_CLOSURE node (new type 28)
3. Identify captured variables by scanning the body for IDENT_REFs not in the parameter list

### Phase 2: Codegen

1. Generate a unique function for each closure: `_closure_N`
2. Emit the closure struct allocation (bump heap)
3. Copy captured values into the struct
4. When calling a closure, load the function pointer and pass the struct

### Phase 3: Type checker

1. Infer the closure's effect set from its body
2. Verify captured variable privacy levels
3. Check closure type compatibility at call sites

## Effect inference for closures

```loon
let f = fn(x: Int) -> Unit { do print(x); };
// Inferred effects: [IO]

let g = fn(x: Int) -> Int { x * 2 };
// Inferred effects: []

fn apply(f: fn(Int) [IO] -> Unit, x: Int) [IO] -> Unit {
    do f(x);
}
```

The caller must declare effects that cover the closure's inferred effects.
