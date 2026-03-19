# Loon-0 AST Format and Enum Contract

This document is the Stage 0 / Stage 1 interface contract. Every integer value
is locked. Changing any value here requires updating both `token_reader.asm`
and every codegen file that references the value.

## 1. Token Type Enum

The token reader converts text token type names (from the Stage 0 lexer output)
to these integer values.

| Value | Name | Lexer Output |
|-------|------|-------------|
| 0 | TOK_KW_FN | `KW_FN` |
| 1 | TOK_KW_LET | `KW_LET` |
| 2 | TOK_KW_TYPE | `KW_TYPE` |
| 3 | TOK_KW_MATCH | `KW_MATCH` |
| 4 | TOK_KW_FOR | `KW_FOR` |
| 5 | TOK_KW_IN | `KW_IN` |
| 6 | TOK_KW_DO | `KW_DO` |
| 7 | TOK_KW_MODULE | `KW_MODULE` |
| 8 | TOK_KW_IMPORTS | `KW_IMPORTS` |
| 9 | TOK_KW_EXPORTS | `KW_EXPORTS` |
| 10 | TOK_KW_SEQUENTIAL | `KW_SEQUENTIAL` |
| 11 | TOK_KW_TRUE | `KW_TRUE` |
| 12 | TOK_KW_FALSE | `KW_FALSE` |
| 13 | TOK_IDENT | `IDENT` |
| 14 | TOK_LIT_INT | `LIT_INT` |
| 15 | TOK_LIT_FLOAT | `LIT_FLOAT` |
| 16 | TOK_LIT_STRING | `LIT_STRING` |
| 17 | TOK_LBRACE | `LBRACE` |
| 18 | TOK_RBRACE | `RBRACE` |
| 19 | TOK_LPAREN | `LPAREN` |
| 20 | TOK_RPAREN | `RPAREN` |
| 21 | TOK_LBRACKET | `LBRACKET` |
| 22 | TOK_RBRACKET | `RBRACKET` |
| 23 | TOK_ASSIGN | `ASSIGN` |
| 24 | TOK_PLUS | `PLUS` |
| 25 | TOK_MINUS | `MINUS` |
| 26 | TOK_STAR | `STAR` |
| 27 | TOK_SLASH | `SLASH` |
| 28 | TOK_PERCENT | `PERCENT` |
| 29 | TOK_EQ | `EQ` |
| 30 | TOK_NEQ | `NEQ` |
| 31 | TOK_LT | `LT` |
| 32 | TOK_GT | `GT` |
| 33 | TOK_LTE | `LTE` |
| 34 | TOK_GTE | `GTE` |
| 35 | TOK_AND | `AND` |
| 36 | TOK_OR | `OR` |
| 37 | TOK_NOT | `NOT` |
| 38 | TOK_ARROW | `ARROW` |
| 39 | TOK_PIPE | `PIPE` |
| 40 | TOK_COLON | `COLON` |
| 41 | TOK_SEMICOLON | `SEMICOLON` |
| 42 | TOK_COMMA | `COMMA` |
| 43 | TOK_DOT | `DOT` |
| 44 | TOK_EOF | `EOF` |

Total: 45 token types (0-44).

## 2. Token Memory Layout (20 bytes)

```
Offset  Size  Field
0       1     token_type      (enum value 0-44)
1       3     padding         (unused, zero)
4       4     string_offset   (byte offset into string table; 0 if no value)
8       4     string_length   (byte count; 0 if no value)
12      4     line            (1-indexed)
16      4     col             (1-indexed)
```

Tokens with values: TOK_IDENT, TOK_LIT_INT, TOK_LIT_FLOAT, TOK_LIT_STRING.
All others have string_offset=0 and string_length=0.

Max tokens: 262144 / 20 = **13107**.

## 3. AST Node Type Enum

| Value | Name | Description |
|-------|------|-------------|
| 0 | NODE_MODULE | Module declaration. `string_ref` = module name. |
| 1 | NODE_FN_DECL | Function declaration. `string_ref` = function name. `child_count` = param count. `first_child` = first PARAM node (sibling chain contains exactly `child_count` PARAMs). `extra` = node index of body BLOCK. |
| 2 | NODE_PARAM | Function parameter. `string_ref` = param name. `type_info` = declared type. |
| 3 | NODE_BLOCK | Block expression. Children are statements + optional return expr. |
| 4 | NODE_LET | Let binding. `string_ref` = variable name. `type_info` = declared type (or inferred). First child = initializer expression. |
| 5 | NODE_EXPR_STMT | Expression statement (value discarded). First child = expression. |
| 6 | NODE_RETURN_EXPR | Return-position expression (value kept in rax). First child = expression. |
| 7 | NODE_INT_LIT | Integer literal. `string_ref` = digit string in string table. `extra` = parsed integer value if it fits in 32 bits; otherwise `extra` = 0xFFFFFFFF and codegen must parse the decimal string from `string_ref`/`string_len`. |
| 8 | NODE_STR_LIT | String literal. `string_ref` = string content in string table. |
| 9 | NODE_BOOL_LIT | Boolean literal. `extra` = 0 (false) or 1 (true). |
| 10 | NODE_IDENT_REF | Variable reference. `string_ref` = variable name. `extra` = stack offset (set by codegen). |
| 11 | NODE_BINOP | Binary operation. `sub_type` = operator (see BINOP sub_types). Left child, right child. `type_info` = result type. |
| 12 | NODE_UNARY_NOT | Logical NOT. One child. |
| 13 | NODE_UNARY_NEG | Arithmetic negation. One child. |
| 14 | NODE_CALL | Function call. `string_ref` = function name. Children = argument expressions. |
| 15 | NODE_DO_EXPR | `do` prefix. One child (the call expression). Codegen identical to child. |
| 16 | NODE_MATCH | Match expression. `child_count` = number of arms. `extra` = node index of discriminant expression. `first_child` = first ARM node (sibling chain contains exactly `child_count` ARM nodes). |
| 17 | NODE_MATCH_ARM | One arm of a match. `extra` = pattern value (integer literal or 0/1 for bool). `sub_type` = 1 if wildcard arm, 0 if literal arm. First child = body expression. |
| 18 | NODE_FOR | For loop. `string_ref` = loop variable name. Children: start expr, end expr, body block. |
| 19 | NODE_ARRAY_NEW | Array constructor. First child = size expression. |
| 20 | NODE_ARRAY_GET | Array index read. `string_ref` = array variable name. First child = index expression. |
| 21 | NODE_ARRAY_SET | Array index write (statement). `string_ref` = array variable name. First child = index expression. Second child = value expression. |

Total: 22 node types (0-21).

## 4. BINOP Sub-type Enum

Stored in the `sub_type` field (offset 1) of `NODE_BINOP` nodes.

| Value | Name | Operator | Notes |
|-------|------|----------|-------|
| 0 | BINOP_ADD | `+` | Int addition or String concatenation (check `type_info`) |
| 1 | BINOP_SUB | `-` | Int only |
| 2 | BINOP_MUL | `*` | Int only |
| 3 | BINOP_DIV | `/` | Int only |
| 4 | BINOP_MOD | `%` | Int only |
| 5 | BINOP_EQ | `==` | Returns Bool |
| 6 | BINOP_NEQ | `!=` | Returns Bool |
| 7 | BINOP_LT | `<` | Returns Bool |
| 8 | BINOP_GT | `>` | Returns Bool |
| 9 | BINOP_LTE | `<=` | Returns Bool |
| 10 | BINOP_GTE | `>=` | Returns Bool |
| 11 | BINOP_AND | `&&` | Bool only |
| 12 | BINOP_OR | `\|\|` | Bool only |

Total: 13 operator sub-types (0-12).

## 5. Builtin Sub-type Enum

Stored in `sub_type` field of `NODE_CALL` nodes when the function name matches a builtin.

| Value | Name | Function |
|-------|------|----------|
| 0 | BUILTIN_NONE | Not a builtin (user-defined function) |
| 1 | BUILTIN_PRINT | `print` |
| 2 | BUILTIN_PRINT_RAW | `print_raw` |
| 3 | BUILTIN_INT_TO_STRING | `int_to_string` |
| 4 | BUILTIN_STRING_LENGTH | `string_length` |
| 5 | BUILTIN_STRING_EQUALS | `string_equals` |
| 6 | BUILTIN_STRING_CHAR_AT | `string_char_at` |
| 7 | BUILTIN_READ_FILE | `read_file` |
| 8 | BUILTIN_EXIT | `exit` |

Total: 9 values (0-8). `BUILTIN_NONE` (0) means the call is to a user-defined function — codegen emits a `call` to the function label.

The parser sets `sub_type` on `NODE_CALL` by comparing `string_ref` against the builtin name table at parse time. If no match, `sub_type = BUILTIN_NONE`.

## 6. Type Info Enum

Stored in the `type_info` field (offset 24) of AST nodes.

| Value | Name | Type |
|-------|------|------|
| 0 | TYPE_INT | `Int` |
| 1 | TYPE_BOOL | `Bool` |
| 2 | TYPE_STRING | `String` |
| 3 | TYPE_UNIT | `Unit` |
| 4 | TYPE_ARRAY | `Array` |
| 5 | TYPE_UNKNOWN | Not yet determined |

Nodes with `type_info = TYPE_UNKNOWN` at codegen entry are treated as `TYPE_INT`. This is the defined fallback for the `+` operator when neither operand is a known string.

## 7. AST Node Memory Layout (32 bytes)

```
Offset  Size  Field
0       1     node_type       (enum value 0-21, see section 3)
1       1     sub_type        (BINOP operator or BUILTIN id, see sections 4-5)
2       2     padding         (unused, zero)
4       4     string_ref      (byte offset into string table)
8       4     string_len      (byte count of referenced string)
12      4     child_count     (number of direct children)
16      4     first_child     (node index of first child, or 0xFFFFFFFF if none)
20      4     next_sibling    (node index of next sibling, or 0xFFFFFFFF if none)
24      4     type_info       (enum value 0-5, see section 6)
28      4     extra           (per-node data: stack offset, int value, bool value, etc.)
```

Sentinel value for "no child" / "no sibling": `0xFFFFFFFF` (all bits set).

Max nodes: 524288 / 32 = **16384**.

## 8. String Table

A flat byte buffer. Strings are stored contiguously. Each string is referenced
by (offset, length) pairs in token and AST node records.

String table entries are not null-terminated. They are length-delimited.

Max size: **131072 bytes** (128KB).

## 9. Global State Variables

All in `.bss`, all 8 bytes (qword):

| Label | Description |
|-------|-------------|
| `tok_count` | Number of tokens read |
| `tok_pos` | Parser's current position in token array |
| `node_count` | Number of AST nodes allocated |
| `str_pos` | Current write position in string table |
| `bump_pos` | Current write position in bump heap |
| `label_counter` | Codegen: next unique label ID |
| `dump_ast_flag` | 1 if `--dump-ast` was passed |

## 10. Match Arm Pattern Encoding

The `sub_type` field of `NODE_MATCH_ARM` distinguishes wildcard from literal:

| `sub_type` | Meaning | `extra` value |
|-----------|---------|--------------|
| 0 | Literal pattern | N (the integer value, or 0/1 for bool) |
| 1 | Wildcard `_` | unused (0) |

Codegen checks: if `sub_type == 1`, emit the default/wildcard branch (unconditional jump).
Otherwise, emit `cmp rax, extra` and conditional jump to the arm body.
