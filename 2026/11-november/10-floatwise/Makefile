JAVAC_FLAGS = -Xlint:all -Werror -encoding UTF-8 --release 21
SOURCES = $(wildcard src/floatwise/*.java)
TESTS = $(wildcard tests/floatwise/*.java)

build/classes/floatwise/Main.class: $(SOURCES)
	javac $(JAVAC_FLAGS) -d build/classes $(SOURCES)

.PHONY: test clean
test: build/classes/floatwise/Main.class $(TESTS)
	javac $(JAVAC_FLAGS) -cp build/classes -d build/tests $(TESTS)
	java -ea -cp build/classes:build/tests floatwise.Tests

clean:
	rm -rf build
