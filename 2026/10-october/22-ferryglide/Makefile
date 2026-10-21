JAVAC_FLAGS = -Xlint:all -Werror -encoding UTF-8 --release 21
SOURCES = $(wildcard src/ferryglide/*.java)
TESTS = $(wildcard tests/ferryglide/*.java)

build/classes/ferryglide/Main.class: $(SOURCES)
	javac $(JAVAC_FLAGS) -d build/classes $(SOURCES)

.PHONY: test clean
test: build/classes/ferryglide/Main.class $(TESTS)
	javac $(JAVAC_FLAGS) -cp build/classes -d build/tests $(TESTS)
	java -ea -cp build/classes:build/tests ferryglide.Tests

clean:
	rm -rf build
