RM=rm -f

TEST_FILES := $(wildcard ./tests/*_test.ml)
# This is for windows
ifeq ($(OS),Windows_NT)
SHELL=C:/Windows/System32/cmd.exe
endif

all: typer debug tests

typer: 
	ocamlbuild src/main.byte
	mv _build/src/main.byte _build/typer # move and rename executable

debug: 
	ocamlbuild tests/prelexer_debug.native -I src  # debug print
	mv _build/tests/prelexer_debug.native _build/prelexer_debug
	ocamlbuild tests/lexer_debug.byte -I src     # debug print
	mv _build/tests/lexer_debug.byte _build/lexer_debug
	#  Debug Print
	ocamlbuild tests/full_debug.native -I src
	mv _build/tests/full_debug.native _build/full_debug

tests: 
	# Build tests
	$(foreach test, $(TEST_FILES), ocamlbuild $(subst ./,,$(subst .ml,.byte,$(test))) -I src;)

	# Run tests
	ocamlbuild tests/utest_main.native
	./_build/tests/utest_main.native

# Make language doc    
doc-tex:
	texi2pdf ./doc/manual.texi --pdf --build=clean

# Make implementation doc
doc-ocaml:
	ocamldoc 

.PHONY: typer
.PHONY: debug
.PHONY: tests
