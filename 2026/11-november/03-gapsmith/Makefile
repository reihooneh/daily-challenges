JAVAC_FLAGS = -Xlint:all -Werror -encoding UTF-8 --release 21
SOURCES = $(wildcard src/gapsmith/*.java)
TESTS = $(wildcard tests/gapsmith/*.java)

build/classes/gapsmith/Main.class: $(SOURCES)
	javac $(JAVAC_FLAGS) -d build/classes $(SOURCES)

.PHONY: test clean
test: build/classes/gapsmith/Main.class $(TESTS)
	javac $(JAVAC_FLAGS) -cp build/classes -d build/tests $(TESTS)
	java -ea -cp build/classes:build/tests gapsmith.Tests

clean:
	rm -rf build
