ASM = nasm
ASMFLAGS = -f elf64
LD = ld

TARGETS = echo classify keywords lexer

all: $(TARGETS)

echo: echo.asm
	$(ASM) $(ASMFLAGS) -o echo.o echo.asm
	$(LD) -o echo echo.o
	rm -f echo.o

classify: classify.asm
	$(ASM) $(ASMFLAGS) -o classify.o classify.asm
	$(LD) -o classify classify.o
	rm -f classify.o

keywords: keywords.asm
	$(ASM) $(ASMFLAGS) -o keywords.o keywords.asm
	$(LD) -o keywords keywords.o
	rm -f keywords.o

lexer: lexer.asm
	$(ASM) $(ASMFLAGS) -o lexer.o lexer.asm
	$(LD) -o lexer lexer.o
	rm -f lexer.o

test-echo: echo
	@echo "=== Testing echo ==="
	./echo ../examples/hello.loon | diff - ../examples/hello.loon && echo "PASS" || echo "FAIL"

test-lexer: lexer
	@echo "=== Testing lexer ==="
	@./lexer ../examples/hello.loon | diff - ../expected/hello.tokens && echo "PASS hello" || echo "FAIL hello"
	@./lexer ../examples/shapes.loon | diff - ../expected/shapes.tokens && echo "PASS shapes" || echo "FAIL shapes"
	@./lexer ../examples/effects.loon | diff - ../expected/effects.tokens && echo "PASS effects" || echo "FAIL effects"

clean:
	rm -f $(TARGETS) *.o

.PHONY: all clean test-echo test-lexer
