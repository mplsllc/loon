# Loon Language Specification

Version 0.1 — Draft

## 1. Overview

Loon is a programming language designed for AI coding agents as the primary author. Its primary design goal: make it structurally impossible to write code that leaks secrets, ignores errors, or breaks production — whether the author is a human, an LLM, or both.

Every design decision optimizes for a single constraint: LLMs generate code token-by-token, left-to-right, and cannot revise previous tokens. The language must make correct generation structurally easy and incorrect generation structurally difficult.

The core principle is **machine-checkable intent**: a function signature tells you what it does, what it needs, what it can affect, and what can go wrong — without running the program.

## 2. Design Principles

1. **Structural honesty.** Every block has explicit open and close delimiters. No significant whitespace. Structure is recoverable from a partial token stream.

2. **One way to do everything.** One loop construct. One branch construct. One function syntax. One import syntax. Every additional way to express something is a branch in the model's generation space where it can make an inconsistent choice.

3. **LL(1) grammar.** One token of lookahead determines every parsing decision. No ambiguity. No backtracking. A parser can be written as a simple recursive descent.

4. **Explicit effects.** Every side effect is syntactically marked — both in the function signature and at each call site. Pure functions and effectful functions are visually distinct.

5. **Verifiable without running.** A human, a compiler, and an AI model can all look at a function and know — not guess — its complete behavior contract.

## 3. Lexical Structure

### 3.1 Character Set

Loon source files are UTF-8 encoded. The lexer operates on bytes. Identifiers and keywords use ASCII letters, digits, and underscores. String literals may contain any UTF-8 sequence.

### 3.2 Whitespace

Spaces, tabs, carriage returns, and newlines are whitespace. Whitespace separates tokens but has no structural meaning. Any amount of whitespace between tokens is equivalent.

### 3.3 Comments

Line comments begin with `//` and extend to the end of the line. There are no block comments. Comments are discarded during lexing and do not appear in the token stream.

### 3.4 Keywords

The following 13 identifiers are reserved as keywords:

```
fn       let       type      match     for
in       do        module    imports   exports
sequential   true      false
```

Keywords are case-sensitive and always lowercase.

### 3.5 Identifiers

An identifier begins with an ASCII letter or underscore, followed by zero or more ASCII letters, digits, or underscores.

```
identifier = [a-zA-Z_][a-zA-Z0-9_]*
```

Keywords take priority: if a token matches both a keyword and an identifier, it is a keyword.

### 3.6 Integer Literals

A sequence of one or more ASCII digits.

```
integer = [0-9]+
```

No leading sign. Negative numbers are expressed as `0 - x`. No hex, octal, or binary literals in v0.1.

### 3.7 Float Literals

An integer part, a dot, and a fractional part. Both parts are required.

```
float = [0-9]+ "." [0-9]+
```

No scientific notation in v0.1. No leading or trailing dot (`.5` and `5.` are invalid).

### 3.8 String Literals

Delimited by double quotes. The following escape sequences are recognized:

```
\\    backslash
\"    double quote
\n    newline
\t    tab
```

No other escape sequences. Strings may not contain unescaped newlines — a string must begin and end on the same line.

### 3.9 Operators and Punctuation

Single-character tokens:
```
{  }  (  )  [  ]
+  -  *  /  %
=  <  >  !
:  ;  ,  .
```

Two-character tokens (checked before single-character):
```
->    arrow
|>    pipe
==    equal
!=    not equal
<=    less or equal
>=    greater or equal
&&    logical and
||    logical or
```

### 3.10 Token Types

Complete enumeration of token types emitted by the lexer:

| Token | Value | Description |
|-------|-------|-------------|
| `KW_FN` | — | `fn` keyword |
| `KW_LET` | — | `let` keyword |
| `KW_TYPE` | — | `type` keyword |
| `KW_MATCH` | — | `match` keyword |
| `KW_FOR` | — | `for` keyword |
| `KW_IN` | — | `in` keyword |
| `KW_DO` | — | `do` keyword |
| `KW_MODULE` | — | `module` keyword |
| `KW_IMPORTS` | — | `imports` keyword |
| `KW_EXPORTS` | — | `exports` keyword |
| `KW_SEQUENTIAL` | — | `sequential` keyword |
| `KW_TRUE` | — | `true` keyword |
| `KW_FALSE` | — | `false` keyword |
| `IDENT` | quoted string | identifier |
| `LIT_INT` | quoted string | integer literal |
| `LIT_FLOAT` | quoted string | float literal |
| `LIT_STRING` | quoted string | string literal contents (without delimiters) |
| `LBRACE` | — | `{` |
| `RBRACE` | — | `}` |
| `LPAREN` | — | `(` |
| `RPAREN` | — | `)` |
| `LBRACKET` | — | `[` |
| `RBRACKET` | — | `]` |
| `ASSIGN` | — | `=` |
| `PLUS` | — | `+` |
| `MINUS` | — | `-` |
| `STAR` | — | `*` |
| `SLASH` | — | `/` |
| `PERCENT` | — | `%` |
| `EQ` | — | `==` |
| `NEQ` | — | `!=` |
| `LT` | — | `<` |
| `GT` | — | `>` |
| `LTE` | — | `<=` |
| `GTE` | — | `>=` |
| `AND` | — | `&&` |
| `OR` | — | `\|\|` |
| `NOT` | — | `!` |
| `ARROW` | — | `->` |
| `PIPE` | — | `\|>` |
| `COLON` | — | `:` |
| `SEMICOLON` | — | `;` |
| `COMMA` | — | `,` |
| `DOT` | — | `.` |
| `EOF` | — | end of file |

### 3.11 Token Output Format

The lexer outputs one token per line to stdout in this format:

```
TYPE line:col
TYPE "value" line:col
```

Tokens with no value (keywords, operators, delimiters, EOF) use the first form. Tokens with a value (IDENT, LIT_INT, LIT_FLOAT, LIT_STRING) use the second form, with the value in double quotes.

Line and column numbers are 1-indexed. Column counts bytes from the start of the line.

### 3.12 Lexer Error Handling

On encountering an invalid character (one that cannot begin any valid token after whitespace and comments are consumed), the lexer:

1. Prints to stderr: `ERROR "unexpected character 'X'" line:col`
2. Exits with code 1

The lexer does not attempt error recovery. It halts on the first invalid character. This is appropriate for a bootstrap tool — error recovery is a Stage 2+ concern.

## 4. Syntax

### 4.1 Grammar Notation

The grammar uses EBNF. `{ X }` means zero or more repetitions. `[ X ]` means optional. `|` means alternation. Terminal symbols are in quotes or ALL_CAPS token names.

### 4.2 Program Structure

```
program = module_decl [ imports_decl ] [ exports_decl ] { declaration }
```

Every Loon source file is a module. The module declaration must be first.

### 4.3 Module Declaration

```
module_decl = "module" IDENT ";"
```

A module declaration with no `imports` or `exports` following it declares a self-contained module. This is the only form used in single-file programs.

### 4.4 Imports and Exports

```
imports_decl = "imports" "[" ident_list "]"
exports_decl = "exports" "[" ident_list "]"
ident_list   = IDENT { "," IDENT } [ "," ]
```

Trailing commas are permitted. No wildcard imports. No re-exports.

### 4.5 Declarations

```
declaration = fn_decl | type_decl | let_decl
```

### 4.6 Function Declaration

```
fn_decl   = "fn" IDENT "(" [ params ] ")" effects "->" type_expr block
params    = param { "," param } [ "," ]
param     = IDENT ":" type_expr
effects   = "[" [ ident_list ] "]"
```

The effect list is mandatory. An empty `[]` means the function is pure. The effect list appears between the parameter list and the return type arrow.

### 4.7 Type Declaration

```
type_decl = "type" IDENT [ type_params ] "{" type_body "}"
type_params = "<" ident_list ">"
type_body = field_list | variant_list
field_list = field { "," field } [ "," ]
field = IDENT ":" type_expr
variant_list = variant { "," variant } [ "," ]
variant = IDENT [ "(" variant_fields ")" ]
variant_fields = field_list | type_list
type_list = type_expr { "," type_expr } [ "," ]
```

A type body is either a list of named fields (product type / struct) or a list of variants (sum type / enum). Variants may have named fields or positional types.

The parser distinguishes them: if the body starts with `IDENT ":"` it's a field list (product type). If it starts with an uppercase `IDENT` optionally followed by `(`, it's a variant list (sum type).

#### Naming Convention

Type names and variant constructors begin with an uppercase letter (A-Z). Function names, variable names, and module names begin with a lowercase letter or underscore. This is enforced by the parser — an uppercase identifier in expression position is always a variant constructor, never a function call.

### 4.8 Let Binding

```
let_decl = "let" IDENT [ ":" type_expr ] "=" expr ";"
```

All bindings are immutable. There is no `var`, `mut`, or reassignment. The type annotation is optional — the type checker infers it from the expression if omitted.

### 4.9 Type Expressions

```
type_expr = IDENT [ type_args ]
type_args = "<" type_expr { "," type_expr } [ "," ] ">"
```

Built-in type names (recognized by the type checker, not reserved as keywords):
- `Int` — 64-bit signed integer
- `Float` — 64-bit floating point
- `String` — UTF-8 string
- `Bool` — `true` or `false`
- `Unit` — the unit type (like void, but a real value)
- `Option<T>` — `Some(T)` or `None`
- `Result<T, E>` — `Ok(T)` or `Err(E)`
- `List<T>` — ordered collection

### 4.10 Expressions

```
expr = match_expr
     | for_expr
     | sequential_expr
     | pipe_expr

pipe_expr = or_expr { "|>" or_expr }

or_expr  = and_expr { "||" and_expr }
and_expr = cmp_expr { "&&" cmp_expr }
cmp_expr = add_expr [ cmp_op add_expr ]
cmp_op   = "==" | "!=" | "<" | ">" | "<=" | ">="
add_expr = mul_expr { ("+" | "-") mul_expr }
mul_expr = unary_expr { ("*" | "/" | "%") unary_expr }

unary_expr = "!" unary_expr
           | "-" unary_expr
           | "do" call_expr
           | postfix_expr

postfix_expr = primary { "(" [ arg_list ] ")" | "." IDENT }
arg_list     = expr { "," expr } [ "," ]

primary = LIT_INT | LIT_FLOAT | LIT_STRING
        | "true" | "false"
        | IDENT
        | IDENT "{" field_init_list "}"
        | IDENT "(" [ arg_list ] ")"
        | "[" [ expr { "," expr } [ "," ] ] "]"
        | "(" expr ")"
        | block

field_init_list = field_init { "," field_init } [ "," ]
field_init      = IDENT ":" expr

block = "{" { statement } [ expr ] "}"
```

Operator precedence (lowest to highest):
1. `|>` (pipe)
2. `||` (logical or)
3. `&&` (logical and)
4. `== != < > <= >=` (comparison — not chainable)
5. `+ -` (additive)
6. `* / %` (multiplicative)
7. `! -` (unary prefix)
8. `do` (effect marker)
9. `f()` `.field` (postfix: call, field access)

### 4.11 Match Expression

```
match_expr = "match" expr "{" match_arm { "," match_arm } [ "," ] "}"
match_arm  = pattern "->" expr
pattern    = IDENT [ "(" pattern_fields ")" ]
           | LIT_INT | LIT_FLOAT | LIT_STRING
           | "true" | "false"
           | "_"
pattern_fields = IDENT { "," IDENT } [ "," ]
```

Match uses `->` for arms (not `=>`). The match expression evaluates to the value of the matched arm. All arms must produce the same type. Exhaustiveness is enforced by the type checker.

### 4.12 For Expression

```
for_expr = "for" IDENT "in" expr block
```

`for` iterates over a collection. It evaluates the block for each element with the loop variable bound to that element. The `for` expression evaluates to `Unit`. If you need a transformed collection, use `map`, `filter`, or `fold`.

### 4.13 Sequential Expression

```
sequential_expr = "sequential" block
```

A sequential block executes its statements in strict order. Outside of sequential blocks, the compiler is free to reorder or parallelize operations. In practice, the interpreter executes everything sequentially in v0.1, but the syntactic distinction exists from day one.

### 4.14 Statements

```
statement = let_decl | expr ";"
```

A statement is either a let binding or an expression followed by a semicolon. The last item in a block may be an expression without a semicolon — this is the block's return value.

### 4.15 The `do` Keyword

`do` is a unary prefix operator that marks an effectful call. It appears:

1. **At the call site:** `do print("hello");` marks an effectful operation.
2. **Effect propagation:** If a function body contains `do` expressions, the function must declare the corresponding effects in its signature.

A function declared with `[]` (empty effects) may not contain `do` expressions. A function containing `do` expressions must declare `[IO]` or the appropriate effect.

## 5. Type System

### 5.1 Primitive Types

| Type | Description | Default value |
|------|-------------|---------------|
| `Int` | 64-bit signed integer | — |
| `Float` | 64-bit IEEE 754 double | — |
| `String` | Immutable UTF-8 string | — |
| `Bool` | `true` or `false` | — |
| `Unit` | Single value `()` | — |

There are no default values. All bindings must be initialized.

### 5.2 Function Types

A function type includes its parameter types, effect set, and return type:

```
fn(Int, Int) [] -> Int       // pure function
fn(String) [IO] -> Unit      // effectful function
```

### 5.3 Algebraic Data Types

**Sum types** (tagged unions):
```loon
type Option<T> {
    Some(T),
    None,
}

type Result<T, E> {
    Ok(T),
    Err(E),
}
```

**Product types** (structs):
```loon
type Point {
    x: Float,
    y: Float,
}
```

### 5.4 No Null

There is no null, nil, nothing, undefined, or any equivalent. Optional values use `Option<T>`. The type checker ensures all Option values are explicitly matched.

### 5.5 No Exceptions

There are no exceptions, throws, try/catch, or panics. Fallible operations return `Result<T, E>`. The type checker ensures all Result values are explicitly matched.

### 5.6 No Implicit Coercion

No implicit type conversions. `Int` does not silently become `Float`. Explicit conversion functions are provided:

```loon
let x: Int = 42;
let y: Float = int_to_float(x);  // explicit
```

### 5.7 Exhaustive Pattern Matching

The type checker verifies that every `match` expression covers all possible variants of the matched type. A `match` on `Option<T>` must have arms for both `Some` and `None`. A `match` on `Bool` must have arms for both `true` and `false`.

The wildcard pattern `_` matches anything and can be used as a catch-all.

### 5.8 Type Parameters

Types and functions may be parameterized:

```loon
type Option<T> { Some(T), None }

fn map<T, U>(list: List<T>, f: fn(T) [] -> U) [] -> List<U> { ... }
```

In v0.1, type parameters are resolved by monomorphization — each concrete usage generates a specific type. Full parametric polymorphism is deferred.

## 6. Effect System

### 6.1 Effect Declarations

Every function declares its effects in brackets between the parameter list and the return type:

```loon
fn pure_add(a: Int, b: Int) [] -> Int { a + b }
fn greet(name: String) [IO] -> Unit { do print("Hello, " + name); }
```

### 6.2 Built-in Effects (v0.1)

| Effect | Description |
|--------|-------------|
| `IO` | Console input/output |
| `FileSystem` | File read/write |

Additional effects (`GPU`, `Network`, `Mutable`) are deferred to later versions.

### 6.3 Effect Rules

1. A function with `[]` is pure. Its body must not contain `do` expressions.
2. A function containing `do` expressions must declare the effects those expressions use.
3. The `do` keyword is required at every effectful call site.
4. Effect sets propagate: if `f` calls `do g()` and `g` has `[IO]`, then `f` must also have `[IO]` (or a superset).
5. The compiler verifies that declared effects match actual effects in the body.

### 6.4 Effect Checking Errors

```
error[E0024]: function 'bad' performs IO but signature is pure
 --> main.loon:4:1
  |
4 | fn bad() [] -> String {
  |    ^^^ body contains 'do' expressions but effects are []
  |
  = help: change to: fn bad() [IO] -> String {
```

## 7. Module System

### 7.1 Module Structure

Every source file is a module. The module name must match the filename (without `.loon` extension).

```loon
module math;

exports [abs, max, min]

fn abs(x: Int) [] -> Int {
    match x >= 0 {
        true -> x,
        false -> 0 - x,
    }
}
```

### 7.2 Imports and Exports

- `exports [...]` declares which names are visible to other modules.
- `imports [...]` declares which modules this module depends on.
- Only exported names can be used from outside the module.
- Imported names are accessed with dot notation: `math.abs(x)`.
- No wildcard imports. No glob imports. No implicit imports.

### 7.3 Module Resolution

In v0.1, `imports [math]` looks for `math.loon` in the same directory as the importing file. No search paths, no package system yet.

## 8. Built-in Functions

These functions are available without imports:

| Function | Signature | Description |
|----------|-----------|-------------|
| `print` | `fn(String) [IO] -> Unit` | Print string to stdout with newline |
| `int_to_string` | `fn(Int) [] -> String` | Convert integer to string |
| `float_to_string` | `fn(Float) [] -> String` | Convert float to string |
| `int_to_float` | `fn(Int) [] -> Float` | Convert integer to float |
| `string_length` | `fn(String) [] -> Int` | Number of bytes in string |
| `range` | `fn(Int, Int) [] -> List<Int>` | Integers from start (inclusive) to end (exclusive) |
| `map` | `fn(List<T>, fn(T) [] -> U) [] -> List<U>` | Transform each element |
| `filter` | `fn(List<T>, fn(T) [] -> Bool) [] -> List<T>` | Keep matching elements |
| `fold` | `fn(List<T>, U, fn(U, T) [] -> U) [] -> U` | Reduce to single value |

## 9. Structured Error Output

Compiler errors are emitted in two formats:

### 9.1 Human-Readable (default, to stderr)

```
error[E0012]: non-exhaustive match on type Shape
 --> main.loon:15:5
  |
15 |     match s {
   |     ^^^^^ missing variant: Rectangle
  |
  = help: add a branch: Rectangle(width, height) -> ...
```

### 9.2 Machine-Readable (JSON, with --json flag)

```json
{
    "error": "non_exhaustive_match",
    "code": "E0012",
    "location": {"file": "main.loon", "line": 15, "column": 5},
    "message": "non-exhaustive match on type Shape",
    "missing": ["Rectangle"],
    "suggestion": "add a branch: Rectangle(width, height) -> ..."
}
```

The JSON format is designed for AI feedback loops — an LLM can parse the error and mechanically produce a fix.

## 10. What Is Not in Loon

These features are deliberately excluded, not accidentally missing:

| Feature | Reason | Alternative |
|---------|--------|-------------|
| `null` / `nil` | Entire category of runtime crashes | `Option<T>` |
| Exceptions / try-catch | Invisible control flow | `Result<T, E>` |
| Inheritance | Deep hierarchies are hard to trace | Composition, traits (future) |
| Operator overloading | `+` must mean one thing everywhere | Named functions |
| Implicit coercion | Silent precision loss | Explicit conversion functions |
| Global mutable state | Action at a distance | Effect system, parameters |
| Significant whitespace | Invisible in token stream | Explicit `{}` delimiters |
| `if/else` | Two ways to branch | `match` on `Bool` |
| `while` / `loop` | Multiple loop constructs | `for` + `fold` |
| `return` keyword | Two ways to produce a value | Last expression in block |
| `var` / `mut` | Mutable bindings | Immutable `let` only |
| Multiple assignment | Reassignment | Shadow with new `let` |
| Variadic functions | Implicit argument count | Explicit `List` parameter |
| Macros | Invisible code generation | (deferred to future version) |

## 11. Complete Example Programs

### 11.1 Hello World

```loon
module main;

fn main() [IO] -> Unit {
    do print("Hello, Loon!");
}
```

### 11.2 Shapes with Pattern Matching

```loon
module main;

type Shape {
    Circle(radius: Float),
    Rectangle(width: Float, height: Float),
}

fn area(s: Shape) [] -> Float {
    match s {
        Circle(r) -> 3.14159 * r * r,
        Rectangle(w, h) -> w * h,
    }
}

fn describe(s: Shape) [] -> String {
    match s {
        Circle(r) -> "circle with radius " + float_to_string(r),
        Rectangle(w, h) -> "rectangle " + float_to_string(w) + "x" + float_to_string(h),
    }
}

fn main() [IO] -> Unit {
    let shapes = [
        Circle(5.0),
        Rectangle(3.0, 4.0),
        Circle(1.0),
    ];

    for shape in shapes {
        let desc = describe(shape);
        let a = area(shape);
        do print(desc + " has area " + float_to_string(a));
    };
}
```

### 11.3 Effect Tracking

```loon
module main;

fn add(a: Int, b: Int) [] -> Int {
    a + b
}

fn greet(name: String) [IO] -> Unit {
    do print("Hello, " + name);
}

fn main() [IO] -> Unit {
    let sum = add(3, 4);
    do print("Sum: " + int_to_string(sum));
    do greet("Loon");
}
```

### 11.4 Option Handling

```loon
module main;

type Option<T> {
    Some(T),
    None,
}

fn find_positive(items: List<Int>) [] -> Option<Int> {
    fold(items, None, fn(acc: Option<Int>, x: Int) [] -> Option<Int> {
        match acc {
            Some(v) -> Some(v),
            None -> match x > 0 {
                true -> Some(x),
                false -> None,
            },
        }
    })
}

fn main() [IO] -> Unit {
    let nums = [0 - 3, 0 - 1, 0, 4, 7];
    let result = find_positive(nums);
    match result {
        Some(v) -> do print("Found: " + int_to_string(v)),
        None -> do print("No positive number found"),
    };
}
```

### 11.5 Pipes

```loon
module main;

fn double(x: Int) [] -> Int { x * 2 }
fn add_one(x: Int) [] -> Int { x + 1 }

fn main() [IO] -> Unit {
    let nums = range(1, 6);
    let result = nums
        |> map(fn(x: Int) [] -> Int { double(x) })
        |> filter(fn(x: Int) [] -> Bool { x > 4 })
        |> fold(0, fn(acc: Int, x: Int) [] -> Int { acc + x });
    do print("Result: " + int_to_string(result));
}
```

### 11.6 Multi-Module

```loon
// math.loon
module math;

exports [abs, max]

fn abs(x: Int) [] -> Int {
    match x >= 0 {
        true -> x,
        false -> 0 - x,
    }
}

fn max(a: Int, b: Int) [] -> Int {
    match a >= b {
        true -> a,
        false -> b,
    }
}
```

```loon
// main.loon
module main;

imports [math]

fn main() [IO] -> Unit {
    do print("abs(-5) = " + int_to_string(math.abs(0 - 5)));
    do print("max(3,7) = " + int_to_string(math.max(3, 7)));
}
```
