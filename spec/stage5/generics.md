# Loon Generics — Stage 5.2 Specification

## Overview

Loon generics use monomorphization — each concrete instantiation generates specialized code. No runtime type erasure. No virtual dispatch for generics.

## Syntax

### Type declarations

```loon
type Option<T> {
    Some(value: T),
    None,
}

type Result<T, E> {
    Ok(value: T),
    Err(error: E),
}

type List<T> {
    Cons(head: T, tail: List<T>),
    Nil,
}
```

### Generic functions

```loon
fn map<T, U>(opt: Option<T>, f: fn(T) -> U) [] -> Option<U> {
    match opt {
        Some(v) -> Some(f(v)),
        None -> None,
    }
}

fn unwrap_or<T>(opt: Option<T>, default: T) [] -> T {
    match opt {
        Some(v) -> v,
        None -> default,
    }
}
```

### Instantiation

```loon
let x: Option<Int> = Some(42);
let y: Option<String> = Some("hello");
let r: Result<Int, String> = Ok(42);
```

## Monomorphization

When the compiler encounters `Option<Int>`, it generates a concrete type:

```
Option_Int { Some_Int(value: Int), None_Int }
```

The codegen emits code for `Option_Int` — no generics at runtime. Each unique instantiation creates a separate type.

## Implementation Plan

### Phase 1: Parser changes

1. Recognize `<T>` after type name in `type` declarations
2. Store type parameters in the type table: `gs[1024 + type_idx * 64 + 20..29]` = param names
3. Recognize `<Int>` after type name in type position
4. Create concrete instantiation: substitute type param with concrete type

### Phase 2: Type checker changes

1. When checking generic function calls, infer type parameters from argument types
2. Verify type parameter consistency across arguments
3. Generate concrete instantiation for the function

### Phase 3: Codegen changes

1. For each concrete instantiation, emit the specialized code
2. Use name mangling: `Option_Int`, `Result_Int_String`, etc.
3. ADT tag layout: same as current — tag at offset 0, fields follow

## Privacy type interaction

Generic types preserve privacy levels:

```loon
let pw: Option<Sensitive<String>> = Some(get_password());
// pw is Option with Sensitive content
// Unwrapping preserves: unwrap_or(pw, "") returns Sensitive<String>
```

The monomorphized type `Option_Sensitive_String` has privacy-aware field types.

## Constraints (future)

```loon
fn serialize<T: Display>(value: T) [IO] -> Unit {
    do print(value.to_string());
}
```

Type constraints (traits/interfaces) are deferred to Stage 6. Stage 5.2 implements unconstrained generics.
