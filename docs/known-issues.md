# Loon Known Issues

**As of v0.5.2: No known compiler limitations.**

All previously documented issues have been resolved:

| Issue | Status | Fix |
|-------|--------|-----|
| Match nesting depth limit | **Resolved** | Depth-indexed g[] slots support 15+ levels |
| >3 Array/String params | **Resolved** | Stack-based calling convention for params 4+ |
| Negative match patterns | **Resolved** | Parser handles `-N` in match arms |
| Chained string concat | **Resolved** | Left operand saved to g[] scratch before right eval |
| Scope limit (40 names) | **Resolved** | Name table relocated to g[4400+], supports 800 names |
| g[] slot collisions | **Resolved** | Full slot map documented, no overlapping ranges |

## Gauntlet Status

```
NASM: 97/97
LLVM: 61/61
Known gaps: 0
```

## Reporting Issues

Report bugs at [github.com/mplsllc/loon/issues](https://github.com/mplsllc/loon/issues).
