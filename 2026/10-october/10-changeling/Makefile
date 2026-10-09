JAVAC_FLAGS = -Xlint:all -Werror -encoding UTF-8 --release 17
SOURCES = $(wildcard src/changeling/*.java)
TESTS = $(wildcard tests/changeling/*.java)

build/classes/changeling/Main.class: $(SOURCES)
	javac $(JAVAC_FLAGS) -d build/classes $(SOURCES)

.PHONY: test clean
test: build/classes/changeling/Main.class $(TESTS)
	javac $(JAVAC_FLAGS) -cp build/classes -d build/tests $(TESTS)
	java -ea -cp build/classes:build/tests changeling.Tests

clean:
	rm -rf build
