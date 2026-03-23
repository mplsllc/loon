/**
 * playground.js — WASM runtime glue for the Loon browser playground.
 *
 * Loads the Loon compiler (compiled to WASM with WASI imports) and runs it
 * in the browser. Each compilation gets a fresh WASM instance because the
 * compiler uses mutable globals that cannot be reset.
 *
 * No external dependencies — pure browser JavaScript, ES module exports.
 */

// Custom error used by proc_exit to break out of WASM execution
// without crashing the host. We throw this from the WASI shim and
// catch it in compile() so we can still read captured output.
class WASIExitError extends Error {
  constructor(code) {
    super(`WASI exit: ${code}`);
    this.code = code;
  }
}

export class LoonPlayground {
  constructor() {
    /** @type {WebAssembly.Instance|null} */
    this.wasmInstance = null;

    /** @type {WebAssembly.Memory|null} */
    this.memory = null;

    /** @type {ArrayBuffer|null} Cached .wasm binary for re-instantiation */
    this.wasmModule = null;

    /** Captured stdout text from the compiler */
    this.stdout = '';

    /** Captured stderr text from the compiler */
    this.stderr = '';

    /** Exit code set by proc_exit, or null if still running */
    this.exitCode = null;

    /** Source code string to feed via fd_read on stdin */
    this.sourceCode = '';

    /** How many bytes of sourceCode have been read so far */
    this._stdinOffset = 0;

    /** The argv strings to present to the compiler */
    this._args = [];
  }

  // --------------------------------------------------------------------------
  // Initialization — fetch and cache the WASM binary
  // --------------------------------------------------------------------------

  /**
   * Fetch the compiler WASM binary and cache it for repeated instantiation.
   * Call this once; compile() can then be called many times.
   *
   * @param {string} wasmUrl  URL to the compiler.wasm file
   */
  async init(wasmUrl = '/compiler.wasm') {
    const response = await fetch(wasmUrl);
    if (!response.ok) {
      throw new Error(`Failed to fetch ${wasmUrl}: ${response.status}`);
    }
    this.wasmModule = await response.arrayBuffer();
  }

  // --------------------------------------------------------------------------
  // WASI shim builders
  // --------------------------------------------------------------------------

  /**
   * Build the wasi_snapshot_preview1 import object.
   *
   * Each method closes over `this` so it can read/write the playground's
   * output buffers and source code. The memory reference is resolved lazily
   * (via this.memory) because it is only available after instantiation.
   */
  _buildWASI() {
    const self = this;
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();

    return {
      /**
       * fd_write(fd, iovs, iovs_len, nwritten_ptr) -> errno
       *
       * Write data to a file descriptor. The compiler writes compiled
       * output to fd=1 (stdout) and error messages to fd=2 (stderr).
       *
       * iovs points to an array of iovec structs in WASM linear memory.
       * Each iovec is two i32 values:
       *   - buf_ptr:  i32 pointer to the data buffer
       *   - buf_len:  i32 byte length of the buffer
       *
       * We decode each buffer as UTF-8 and append to the appropriate
       * output string. The total bytes written is stored at nwritten_ptr.
       */
      fd_write(fd, iovs, iovs_len, nwritten_ptr) {
        const mem = new DataView(self.memory.buffer);
        const bytes = new Uint8Array(self.memory.buffer);
        let totalWritten = 0;

        for (let i = 0; i < iovs_len; i++) {
          // Each iovec is 8 bytes: 4-byte pointer + 4-byte length
          const bufPtr = mem.getUint32(iovs + i * 8, true);
          const bufLen = mem.getUint32(iovs + i * 8 + 4, true);

          if (bufLen === 0) continue;

          const chunk = bytes.slice(bufPtr, bufPtr + bufLen);
          const text = decoder.decode(chunk);

          if (fd === 1) {
            self.stdout += text;
          } else if (fd === 2) {
            self.stderr += text;
          }
          // Other fds are silently ignored

          totalWritten += bufLen;
        }

        // Write the total number of bytes written back to WASM memory
        mem.setUint32(nwritten_ptr, totalWritten, true);

        // Return 0 (ESUCCESS)
        return 0;
      },

      /**
       * fd_read(fd, iovs, iovs_len, nread_ptr) -> errno
       *
       * Read data from a file descriptor. The compiler reads source code
       * from stdin (fd=0) via its _loon_read_file implementation, which
       * in WASM mode reads from fd 0.
       *
       * On the first call, we copy the user's source code into the
       * provided buffers. On subsequent calls (or once all bytes have
       * been consumed), we return 0 bytes to signal EOF.
       *
       * The iovec layout is identical to fd_write.
       */
      fd_read(fd, iovs, iovs_len, nread_ptr) {
        const mem = new DataView(self.memory.buffer);
        const bytes = new Uint8Array(self.memory.buffer);

        // Only stdin is supported
        if (fd !== 0) {
          mem.setUint32(nread_ptr, 0, true);
          return 8; // EBADF
        }

        const sourceBytes = encoder.encode(self.sourceCode);
        let totalRead = 0;

        for (let i = 0; i < iovs_len; i++) {
          const bufPtr = mem.getUint32(iovs + i * 8, true);
          const bufLen = mem.getUint32(iovs + i * 8 + 4, true);

          // How many bytes remain to be read from the source
          const remaining = sourceBytes.length - self._stdinOffset;
          if (remaining <= 0) break;

          // Copy as many bytes as fit in this buffer
          const toRead = Math.min(bufLen, remaining);
          bytes.set(
            sourceBytes.subarray(self._stdinOffset, self._stdinOffset + toRead),
            bufPtr
          );

          self._stdinOffset += toRead;
          totalRead += toRead;
        }

        // Write total bytes read back to WASM memory
        mem.setUint32(nread_ptr, totalRead, true);

        // Return 0 (ESUCCESS)
        return 0;
      },

      /**
       * proc_exit(code)
       *
       * Called when the compiler finishes (or hits a fatal error).
       * We record the exit code and throw a WASIExitError to break
       * out of WASM execution. The caller (compile()) catches this.
       *
       * We must NOT simply return — the compiler expects this call
       * to never return, and WASM would continue executing garbage
       * instructions after the call site.
       */
      proc_exit(code) {
        self.exitCode = code;
        throw new WASIExitError(code);
      },

      /**
       * args_sizes_get(argc_ptr, argv_buf_size_ptr) -> errno
       *
       * Returns the number of arguments and the total size of the
       * argument string buffer. The compiler uses this to allocate
       * space before calling args_get.
       *
       * argc_ptr:          pointer to store argument count (i32)
       * argv_buf_size_ptr: pointer to store total byte size of all
       *                    null-terminated argument strings (i32)
       */
      args_sizes_get(argc_ptr, argv_buf_size_ptr) {
        const mem = new DataView(self.memory.buffer);

        // Number of arguments
        mem.setUint32(argc_ptr, self._args.length, true);

        // Total buffer size: sum of (each string's UTF-8 bytes + 1 null terminator)
        let totalSize = 0;
        for (const arg of self._args) {
          totalSize += encoder.encode(arg).length + 1; // +1 for null terminator
        }
        mem.setUint32(argv_buf_size_ptr, totalSize, true);

        return 0;
      },

      /**
       * args_get(argv_ptr, argv_buf_ptr) -> errno
       *
       * Write argument pointers and string data into WASM memory.
       *
       * argv_ptr:     pointer to an array of i32 pointers, one per arg
       * argv_buf_ptr: pointer to a contiguous buffer where the null-
       *               terminated argument strings are written
       *
       * Layout after this call:
       *   argv[0] -> "loon\0"
       *   argv[1] -> "playground.loon\0"
       *   ...
       *
       * All pointers are i32 because WASM uses 32-bit linear memory
       * addresses.
       */
      args_get(argv_ptr, argv_buf_ptr) {
        const mem = new DataView(self.memory.buffer);
        const bytes = new Uint8Array(self.memory.buffer);

        let bufOffset = argv_buf_ptr;

        for (let i = 0; i < self._args.length; i++) {
          // Write the pointer to this argument string into argv[i]
          mem.setUint32(argv_ptr + i * 4, bufOffset, true);

          // Encode the argument string as UTF-8 and write into the buffer
          const encoded = encoder.encode(self._args[i]);
          bytes.set(encoded, bufOffset);
          bufOffset += encoded.length;

          // Null-terminate the string
          bytes[bufOffset] = 0;
          bufOffset += 1;
        }

        return 0;
      },
    };
  }

  // --------------------------------------------------------------------------
  // Compilation
  // --------------------------------------------------------------------------

  /**
   * Compile Loon source code using the WASM compiler.
   *
   * @param {string} source   Loon source code to compile
   * @param {object} options  Optional settings
   * @param {string[]} options.args  Custom argv (default: ["loon", "/dev/stdin"])
   * @returns {{ stdout: string, stderr: string, exitCode: number }}
   */
  async compile(source, options = {}) {
    if (!this.wasmModule) {
      throw new Error('Call init() before compile()');
    }

    // Reset all per-compilation state
    this.stdout = '';
    this.stderr = '';
    this.exitCode = null;
    this.sourceCode = source;
    this._stdinOffset = 0;

    // Set up argv. Default args tell the compiler to read from stdin.
    // The compiler determines behavior based on argv:
    //   - "loon /dev/stdin"            -> default NASM compilation (syntax check)
    //   - "loon --target llvm /dev/stdin" -> LLVM IR output
    this._args = options.args || ['loon', '/dev/stdin'];

    // Build the WASI import object
    const wasiImports = this._buildWASI();

    // Instantiate a fresh WASM instance for each compilation.
    // The compiler uses mutable globals (bump allocator pointer, parser
    // state, etc.) that cannot be reset, so we must create a new instance.
    const { instance } = await WebAssembly.instantiate(
      this.wasmModule,
      {
        wasi_snapshot_preview1: wasiImports,
      }
    );

    // Grab the memory export — all WASI shims read/write through this
    this.memory = instance.exports.memory;

    try {
      // Call the compiler's entry point. The WASI standard export is
      // "_start" for command-style modules.
      instance.exports._start();
    } catch (err) {
      if (err instanceof WASIExitError) {
        // Normal exit via proc_exit — exitCode is already recorded
      } else {
        // Unexpected error — record it as a compiler crash
        this.stderr += `\nInternal error: ${err.message}\n`;
        if (this.exitCode === null) {
          this.exitCode = 1;
        }
      }
    }

    // If the compiler returned normally without calling proc_exit,
    // treat it as a successful exit
    if (this.exitCode === null) {
      this.exitCode = 0;
    }

    return {
      stdout: this.stdout,
      stderr: this.stderr,
      exitCode: this.exitCode,
    };
  }
}

// ---------------------------------------------------------------------------
// Convenience function
// ---------------------------------------------------------------------------

/**
 * One-shot compile: create a playground, load the WASM, compile, return results.
 *
 * @param {string} source    Loon source code
 * @param {string} wasmUrl   URL to compiler.wasm (default: '/compiler.wasm')
 * @returns {Promise<{ stdout: string, stderr: string, exitCode: number }>}
 */
export async function compileLoon(source, wasmUrl = '/compiler.wasm') {
  const pg = new LoonPlayground();
  await pg.init(wasmUrl);
  return pg.compile(source);
}

export default LoonPlayground;
