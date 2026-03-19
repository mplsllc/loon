# Loon-0 Language Specification

Version 0.1 — Bootstrap Subset

## 1. Overview

Loon-0 is the minimal subset of Loon needed to write a compiler. It has 14 constructs, 4 types, and 8 built-in functions. Every construct earns its place by being necessary for Stage 2 (the real Loon compiler written in Loon-0).

Loon-0 is compiled by Stage 1 (parser + codegen in x86-64 assembly). Once Stage 2 exists, Loon-0 and Stage 1 are never used again.

## 2. Differences from Full Loon

Loon-0 is a strict subset. Nothing in Loon-0 contradicts the full Loon spec — it only omits features.

| Feature | Full Loon | Loon-0 | Reason |
|---------|-----------|--------|--------|
| Types | Int, Float, String, Bool, Unit, Option, Result, List, custom ADTs | Int, Bool, String, Array, Unit | Compilers don't need Float; ADTs, Option, Result deferred |
| Match | On any type, exhaustive | On Int and Bool only, with `_` wildcard | Token types are integers; String match too complex |
| Generics | Full parametric | `Array<Int>` special-cased only | Not needed for bootstrap |
| Effects | Verified by compiler | `do` parsed but not verified | Stage 2 implements verification |
| Modules | Multi-file with imports/exports | Single-file, `module name;` only | Stage 2 implements module system |
| Pipe | `\|>` operator | Not available | Explicit calls suffice |
| Error handling | `Result<T, E>` with exhaustive match | `do exit(1)` | Crude but sufficient for bootstrap |
| Closures | First-class functions | Named functions only | Not needed for bootstrap |

## 3. Lexical Structure

Loon-0 uses the same lexer as full Loon (Stage 0). All tokens defined in the full Loon spec are valid input to the Stage 1 compiler, but only the subset below is recognized by the parser.

### 3.1 Keywords Recognized

```
fn   let   match   for   in   do   module   true   false
```

9 of the 13 full Loon keywords. `type`, `imports`, `exports`, and `sequential` are not recognized by the Loon-0 parser (they produce a parse error if encountered at the top level).

### 3.2 Operators and Punctuation Used

```
+  -  *  /  %                   arithmetic
==  !=  <  >  <=  >=            comparison
&&  ||  !                       boolean
->                              return type arrow
=                               assignment (in let)
{  }  (  )  [  ]               delimiters
:  ;  ,                         punctuation
```

Not used in Loon-0: `|>` (pipe), `.` (field access).

## 4. Grammar

### 4.1 Notation

EBNF. `{ X }` = zero or more. `[ X ]` = optional. `|` = alternation. Terminals in quotes or ALL_CAPS.

### 4.2 Program Structure

```
program     = module_decl { fn_decl }
module_decl = KW_MODULE IDENT SEMICOLON
```

A Loon-0 program is a module declaration followed by one or more function declarations. No top-level `let` bindings. No `type` declarations.

### 4.3 Function Declaration

```
fn_decl     = KW_FN IDENT LPAREN [ params ] RPAREN effects ARROW type_expr block
params      = param { COMMA param } [ COMMA ]
param       = IDENT COLON type_expr
effects     = LBRACKET [ ident_list ] RBRACKET
ident_list  = IDENT { COMMA IDENT } [ COMMA ]
```

Effects are parsed but not verified. `[]` and `[IO]` are both accepted without semantic checking.

### 4.4 Type Expressions

```
type_expr   = IDENT [ LT type_expr GT ]
```

Recognized type names: `Int`, `Bool`, `String`, `Unit`, `Array`. `Array<Int>` is the only generic form recognized. The type checker does not enforce types beyond variable-declared-before-use and argument-count matching.

### 4.5 Block

```
block          = LBRACE { statement } [ expr ] RBRACE
statement      = let_stmt | array_set_stmt | expr_stmt
let_stmt       = KW_LET IDENT [ COLON type_expr ] ASSIGN expr SEMICOLON
array_set_stmt = IDENT LBRACKET expr RBRACKET ASSIGN expr SEMICOLON
expr_stmt      = expr SEMICOLON
```

`array_set_stmt` is the one form of mutation in Loon-0 — arrays are mutable containers (like buffers). The array name must be an `IDENT` (not an arbitrary expression). This is necessary for a compiler that builds token and node arrays.

**Parser note:** `array_set_stmt` and `expr_stmt` both start with `IDENT`. To keep the grammar LL(1), bare array reads as expression statements (`arr[i];` with value discarded) are a parse error. An `expr_stmt` may not begin with `IDENT LBRACKET`. When the parser sees `IDENT LBRACKET`, it always parses `array_set_stmt`. Array reads are only valid as sub-expressions (e.g., `arr[i] + 1` or `do print(int_to_string(arr[i]))`).

The last item in a block may be an expression without a semicolon — this is the block's return value (tagged `RETURN_EXPR` in the AST). All other expressions are statements (tagged `EXPR_STMT`).

### 4.6 Expressions

Operator precedence (lowest to highest):

| Level | Operators | Associativity |
|-------|-----------|---------------|
| 1 | `\|\|` | left |
| 2 | `&&` | left |
| 3 | `==` `!=` `<` `>` `<=` `>=` | none (not chainable) |
| 4 | `+` `-` | left |
| 5 | `*` `/` `%` | left |
| 6 | `!` `-` (unary) | prefix |
| 7 | `do` | prefix |
| 8 | `f()` `arr[i]` | postfix |

```
expr        = match_expr | for_expr | or_expr

or_expr     = and_expr { OR and_expr }
and_expr    = cmp_expr { AND cmp_expr }
cmp_expr    = add_expr [ cmp_op add_expr ]
cmp_op      = EQ | NEQ | LT | GT | LTE | GTE
add_expr    = mul_expr { ( PLUS | MINUS ) mul_expr }
mul_expr    = unary_expr { ( STAR | SLASH | PERCENT ) unary_expr }
unary_expr  = NOT unary_expr
            | MINUS unary_expr
            | KW_DO postfix_expr
            | postfix_expr
postfix_expr = primary { LPAREN [ arg_list ] RPAREN | LBRACKET expr RBRACKET }
arg_list    = expr { COMMA expr } [ COMMA ]
primary     = LIT_INT
            | LIT_STRING
            | KW_TRUE
            | KW_FALSE
            | IDENT
            | IDENT LPAREN [ arg_list ] RPAREN
            | LPAREN expr RPAREN
            | block
```

Note: there is no negative integer literal token. Negative values are unary negation applied to a positive literal: `0 - 42` or `MINUS LIT_INT`. This means `-42` cannot appear as a match arm pattern — use `0 - 42` in expressions or match on the positive value.

### 4.7 Special Syntax: `Array(n)`

```
array_new   = "Array" LPAREN expr RPAREN
```

`Array(n)` is special syntax, not a function call. The parser recognizes the identifier `Array` followed by `(` and produces an `ARRAY_NEW` node. Codegen allocates `n * 8` bytes from the bump heap.

### 4.8 Match Expression

```
match_expr  = KW_MATCH expr LBRACE match_arm { COMMA match_arm } [ COMMA ] RBRACE
match_arm   = pattern ARROW expr
pattern     = LIT_INT | KW_TRUE | KW_FALSE | IDENT
```

Where `IDENT` as a pattern is the wildcard `_` (the only identifier valid as a pattern in Loon-0). No ADT variant patterns. No string patterns.

Match arms for `Bool` must cover `true` and `false` (or use `_`). Match arms for `Int` must include a `_` wildcard (the compiler cannot verify exhaustiveness for integers).

### 4.9 For Expression

```
for_expr    = KW_FOR IDENT KW_IN "range" LPAREN expr COMMA expr RPAREN block
```

`range(a, b)` is special syntax, not a function call. The parser recognizes `for IDENT in range ( expr , expr ) block` as a single production. Codegen emits: initialize counter to `a`, compare against `b`, execute body, increment, conditional jump back.

`for` evaluates to `Unit`.

### 4.10 The `do` Keyword

`do` is a unary prefix operator. `do f(x)` and `f(x)` produce identical compiled code. The `do` keyword exists in the syntax so that Loon-0 code remains valid full Loon code — removing it would create programs that don't compile under the real Loon compiler's effect checker.

In the AST, `do expr` produces a `DO_EXPR` node wrapping the inner expression. Codegen for `DO_EXPR` simply recurses into its child.

## 5. Types

### 5.1 Primitive Types

| Type | Representation | Size on stack |
|------|---------------|---------------|
| `Int` | 64-bit signed integer | 8 bytes |
| `Bool` | 64-bit integer (0 = false, 1 = true) | 8 bytes |
| `String` | (pointer, length) pair | 16 bytes (two 8-byte values) |
| `Array` | (pointer, length) pair, elements are 8 bytes | 16 bytes (two 8-byte values) |
| `Unit` | No value stored | 0 bytes |

### 5.2 Type Checking in Loon-0

The Loon-0 "type checker" is minimal:

1. **Variable declaration check.** Every `IDENT` reference must have a corresponding `let` binding or function parameter in scope. Undeclared variables produce a compile error.

2. **Argument count check.** Every function call must pass the same number of arguments as the function's parameter list. Mismatched counts produce a compile error.

3. **No type compatibility checking.** `let x: Int = "hello";` is not caught by Loon-0. Full type checking is a Stage 2 concern.

### 5.3 String Representation

Strings are `(pointer, length)` pairs. The pointer points into the bump heap (for runtime-constructed strings) or into the `.data` section (for string literals in the compiled program). Strings are not null-terminated.

String concatenation with `+` allocates a new string in the bump heap containing the bytes of both operands.

**Important:** The `open` syscall requires null-terminated filenames. `read_file` must copy the filename to the bump heap and append `\0` before calling `open`.

### 5.4 Array Representation

Arrays are `(pointer, length)` pairs. The pointer points into the bump heap. Each element is 8 bytes (one `Int`, one `Bool`, or one string pointer — all values are 8 bytes or 16 bytes, but array elements store only the first 8 bytes, so arrays of String or Array are not supported in Loon-0).

`Array(n)` allocates `n * 8` bytes from the bump heap, zero-initialized.

Index access `arr[i]` loads from `pointer + i * 8`. Bounds checking: if `i < 0` or `i >= length`, print error to stderr and `exit(1)`.

Arrays store 8-byte values only. Storing a String or Array value (which is 16 bytes) in an array element is not caught by the Loon-0 type checker. Behavior is undefined. In practice, only `Array<Int>` is used in Loon-0 programs.

## 6. Built-in Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `print` | `fn(String) [IO] -> Unit` | Write string to stdout, followed by newline |
| `print_raw` | `fn(String) [IO] -> Unit` | Write string to stdout, no newline |
| `int_to_string` | `fn(Int) [] -> String` | Convert integer to decimal string |
| `string_length` | `fn(String) [] -> Int` | Return length in bytes |
| `string_equals` | `fn(String, String) [] -> Bool` | Compare two strings for equality |
| `string_char_at` | `fn(String, Int) [] -> Int` | Return byte value at index (bounds-checked) |
| `read_file` | `fn(String) [IO] -> String` | Read entire file into bump heap |
| `exit` | `fn(Int) [IO] -> Unit` | Terminate program with exit code |

Built-in functions are recognized by name during codegen. They do not need to be declared in the source. Calling a name that is neither a declared function nor a built-in is a compile error.

## 7. Scoping Rules

Loon-0 uses lexical scoping with no shadowing.

- Function parameters are in scope for the entire function body.
- `let` bindings are in scope from the statement after the binding to the end of the enclosing block.
- `for` loop variables are in scope within the loop body.
- Functions are in scope throughout the entire program (order of declaration does not matter — forward calls are allowed). Implementation: the parser does a first pass to collect all function names and parameter counts before parsing bodies.
- There is no global scope for variables. Only function declarations are global.

Shadowing (declaring a variable with the same name as an existing one in an enclosing scope) is a compile error in Loon-0. This restriction simplifies stack slot assignment in codegen.

## 8. Compilation Model

### 8.1 Pipeline

```
source.loon → stage0/lexer → token stream → stage1/compiler → output.asm → nasm → ld → binary
```

### 8.2 Output Format

The Stage 1 compiler outputs NASM x86-64 assembly to stdout. The output contains:

- `section .data` — string literals, builtin string constants
- `section .bss` — bump heap
- `section .text` — `_start`, compiled functions, runtime builtins

### 8.3 Calling Convention

Compiled Loon-0 functions use the AMD64 System V ABI:

- Arguments 1-6 in: `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`
- Return value in: `rax`
- Caller-saved: `rax`, `rcx`, `rdx`, `rsi`, `rdi`, `r8`, `r9`, `r10`, `r11`
- Callee-saved: `rbx`, `rbp`, `rsp`, `r12`, `r13`, `r14`, `r15`
- Stack frame: `push rbp; mov rbp, rsp; sub rsp, N` ... `mov rsp, rbp; pop rbp; ret`

For String and Array parameters (16 bytes), the pointer is passed in one register and the length in the next. A function `fn foo(s: String, n: Int)` receives: `rdi`=s.ptr, `rsi`=s.len, `rdx`=n.

### 8.4 String/Int `+` Dispatch

The `+` operator is overloaded between Int and String in Loon-0 (this is the only operator overloading, inherited from full Loon). The AST node for `BINOP ADD` carries a `type_info` field:

- `type_info == 0` (Int): emit `add rax, rcx`
- `type_info == 2` (String): emit call to `str_concat` runtime function

The parser sets `type_info` on `BINOP ADD` nodes: if either operand is a string literal (`NODE_STR_LIT`) or a variable declared with type `String`, `type_info = 2` (String). Otherwise `type_info = 0` (Int). This is the only type propagation the Loon-0 parser performs.

## 9. Error Handling

### 9.1 Compile Errors

The Stage 1 compiler writes errors to stderr and exits with code 1. Error format:

```
error: <message> at line <line>, col <col>
```

Compile errors include:
- Unexpected token (parse error)
- Undeclared variable
- Wrong number of arguments to function
- Unknown function name (not declared and not a builtin)

### 9.2 Runtime Errors

Compiled Loon-0 programs may produce runtime errors:
- Array index out of bounds → print error to stderr, exit 1
- `read_file` failure (file not found) → print error to stderr, exit 1

### 9.3 No Error Recovery

Neither the compiler nor compiled programs attempt error recovery. First error halts execution. This is appropriate for a bootstrap tool.

## 10. Complete Example Programs

### 10.1 Hello World

```loon
module main;

fn main() [IO] -> Unit {
    do print("Hello, Loon!");
}
```

Expected output: `Hello, Loon!` followed by newline. Exit code 0.

### 10.2 Arithmetic

```loon
module main;

fn main() [IO] -> Unit {
    do exit(3 + 4 * 5);
}
```

Expected output: none. Exit code 23.

### 10.3 Function Calls

```loon
module main;

fn add(a: Int, b: Int) [] -> Int {
    a + b
}

fn main() [IO] -> Unit {
    let x: Int = add(10, 20);
    do exit(x);
}
```

Expected output: none. Exit code 30.

### 10.4 Match on Bool

```loon
module main;

fn abs(x: Int) [] -> Int {
    match x >= 0 {
        true -> x,
        false -> 0 - x,
    }
}

fn main() [IO] -> Unit {
    do print(int_to_string(abs(0 - 42)));
}
```

Expected output: `42`. Exit code 0.

### 10.5 Match on Int

```loon
module main;

fn describe(n: Int) [] -> String {
    match n {
        0 -> "zero",
        1 -> "one",
        _ -> "other",
    }
}

fn main() [IO] -> Unit {
    do print(describe(0));
    do print(describe(1));
    do print(describe(99));
}
```

Expected output:
```
zero
one
other
```
Exit code 0.

### 10.6 String Concatenation

```loon
module main;

fn greet(name: String) [IO] -> Unit {
    do print("Hello, " + name + "!");
}

fn main() [IO] -> Unit {
    do greet("Loon");
}
```

Expected output: `Hello, Loon!`. Exit code 0.

### 10.7 For Loop

```loon
module main;

fn main() [IO] -> Unit {
    for i in range(0, 5) {
        do print(int_to_string(i));
    };
}
```

Expected output:
```
0
1
2
3
4
```
Exit code 0.

Note: `for` loops are side-effect-only in Loon-0. Scalar accumulation requires `fold` (Stage 2). Array accumulation uses `arr[i] = expr` (section 4.5).

### 10.8 Arrays

```loon
module main;

fn main() [IO] -> Unit {
    let arr: Array<Int> = Array(3);
    arr[0] = 10;
    arr[1] = 20;
    arr[2] = 30;
    do print(int_to_string(arr[0] + arr[1] + arr[2]));
}
```

Expected output: `60`. Exit code 0.

### 10.9 Effects (Integration Test)

```loon
module main;

fn add(a: Int, b: Int) [] -> Int {
    a + b
}

fn greet(name: String) [IO] -> Unit {
    do print("Hello, " + name);
}

fn main() [IO] -> Unit {
    let sum: Int = add(3, 4);
    do print("Sum: " + int_to_string(sum));
    do greet("Loon");
}
```

Expected output:
```
Sum: 7
Hello, Loon
```
Exit code 0.

This is `examples/effects.loon` — the Stage 1 completion test.

## 11. What Is Not in Loon-0

| Feature | Why excluded | How Stage 2 handles it |
|---------|-------------|----------------------|
| Float type | Compilers don't need floating point | Added as a primitive type |
| ADTs / sum types | Match on integers handles all compiler decisions | Added with full exhaustiveness checking |
| Generics | `Array<Int>` is the only needed generic form | Full parametric polymorphism |
| String match arms | Token types are integer codes | Added with `string_equals` per arm |
| Effect verification | `do` is syntactic only in Loon-0 | Full effect set tracking and verification |
| Module imports | Single-file only | Multi-file with `imports`/`exports` |
| Option/Result | `do exit(1)` for errors | Algebraic error types with exhaustive match |
| Pipe operator | `f(g(x))` is equivalent | `x \|> g \|> f` syntax |
| `return` keyword | Not in Loon spec — last expression is return value | N/A — stays out |
| `type` declarations | No custom types in Loon-0 | Full ADT declarations |
| Closures | No first-class functions | Anonymous functions with captures |
| Variable shadowing | Simplifies stack slot assignment | Allowed in full Loon |
| `sequential` blocks | Everything is sequential in Loon-0 | Parallel-by-default with `sequential` as exception |
