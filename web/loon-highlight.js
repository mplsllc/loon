// loon-highlight.js — Loon syntax highlighter for the playground editor
// Pure ES module, no dependencies. Lexer-based tokenization.

const KEYWORDS = new Set([
  'fn', 'let', 'type', 'match', 'for', 'in', 'do',
  'module', 'imports', 'exports', 'sequential', 'true', 'false'
]);

const TYPES = new Set([
  'Int', 'String', 'Bool', 'Unit', 'Array',
  'Public', 'Sensitive', 'Restricted', 'Hashed',
  'Result', 'Option'
]);

const BUILTINS = new Set([
  'print', 'print_raw', 'exit', 'int_to_string', 'string_concat',
  'read_file', 'get_arg', 'hash_password', 'expose', 'len', 'range', 'array'
]);

const EFFECTS = new Set([
  'IO', 'Crypto', 'Audit', 'FileIO'
]);

// Word-boundary operators (checked separately from symbol operators)
const WORD_OPERATORS = new Set(['and', 'or', 'not']);

// Multi-char symbol operators, longest first
const SYMBOL_OPERATORS = ['->', '|>', '==', '!=', '<=', '>='];
const SINGLE_OPERATORS = new Set(['+', '-', '*', '/', '%', '=', '<', '>']);

function escapeHTML(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function span(cls, text) {
  return `<span class="${cls}">${escapeHTML(text)}</span>`;
}

function isIdentStart(ch) {
  return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch === '_';
}

function isIdentChar(ch) {
  return isIdentStart(ch) || (ch >= '0' && ch <= '9');
}

function isDigit(ch) {
  return ch >= '0' && ch <= '9';
}

export function highlight(source) {
  const out = [];
  let i = 0;
  const len = source.length;

  while (i < len) {
    const ch = source[i];

    // Line comments
    if (ch === '/' && i + 1 < len && source[i + 1] === '/') {
      let end = i;
      while (end < len && source[end] !== '\n') end++;
      out.push(span('hl-comment', source.slice(i, end)));
      i = end;
      continue;
    }

    // Strings
    if (ch === '"') {
      let end = i + 1;
      while (end < len && source[end] !== '"') {
        if (source[end] === '\\' && end + 1 < len) end++; // skip escaped char
        end++;
      }
      if (end < len) end++; // consume closing quote
      out.push(span('hl-string', source.slice(i, end)));
      i = end;
      continue;
    }

    // Identifiers and keywords
    if (isIdentStart(ch)) {
      let end = i;
      while (end < len && isIdentChar(source[end])) end++;
      const word = source.slice(i, end);

      if (KEYWORDS.has(word)) {
        out.push(span('hl-keyword', word));
      } else if (TYPES.has(word)) {
        out.push(span('hl-type', word));
      } else if (BUILTINS.has(word)) {
        out.push(span('hl-builtin', word));
      } else if (EFFECTS.has(word)) {
        out.push(span('hl-effect', word));
      } else if (WORD_OPERATORS.has(word)) {
        out.push(span('hl-operator', word));
      } else {
        out.push(escapeHTML(word));
      }
      i = end;
      continue;
    }

    // Numbers (integer and float)
    if (isDigit(ch)) {
      let end = i;
      while (end < len && isDigit(source[end])) end++;
      if (end < len && source[end] === '.' && end + 1 < len && isDigit(source[end + 1])) {
        end++; // consume dot
        while (end < len && isDigit(source[end])) end++;
      }
      out.push(span('hl-number', source.slice(i, end)));
      i = end;
      continue;
    }

    // Multi-char symbol operators
    let matched = false;
    for (const op of SYMBOL_OPERATORS) {
      if (source.startsWith(op, i)) {
        out.push(span('hl-operator', op));
        i += op.length;
        matched = true;
        break;
      }
    }
    if (matched) continue;

    // Single-char operators
    if (SINGLE_OPERATORS.has(ch)) {
      out.push(span('hl-operator', ch));
      i++;
      continue;
    }

    // Everything else (whitespace, punctuation, braces, etc.) — unstyled
    out.push(escapeHTML(ch));
    i++;
  }

  return out.join('');
}

export function highlightCSS() {
  return `
.hl-keyword  { color: var(--teal-400); }
.hl-type     { color: #e0a858; }
.hl-builtin  { color: #6dd3dc; }
.hl-effect   { color: #c792ea; }
.hl-string   { color: var(--green-500); }
.hl-comment  { color: var(--gray-500); font-style: italic; }
.hl-number   { color: #f78c6c; }
.hl-operator { color: var(--gray-300); }
`;
}
