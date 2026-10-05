JAVAC_FLAGS = -Xlint:all -Werror -encoding UTF-8 --release 17
SOURCES = $(wildcard src/seventh/*.java)
TESTS = $(wildcard tests/seventh/*.java)

build/classes/seventh/Main.class: $(SOURCES)
	javac $(JAVAC_FLAGS) -d build/classes $(SOURCES)

.PHONY: test clean
test: build/classes/seventh/Main.class $(TESTS)
	javac $(JAVAC_FLAGS) -cp build/classes -d build/tests $(TESTS)
	java -ea -cp build/classes:build/tests seventh.Tests

clean:
	rm -rf build
