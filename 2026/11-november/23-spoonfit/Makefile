JAVAC_FLAGS = -Xlint:all -Werror -encoding UTF-8 --release 21
SOURCES = $(wildcard src/spoonfit/*.java)
TESTS = $(wildcard tests/spoonfit/*.java)

build/classes/spoonfit/Main.class: $(SOURCES)
	javac $(JAVAC_FLAGS) -d build/classes $(SOURCES)

.PHONY: test run clean
test: build/classes/spoonfit/Main.class $(TESTS)
	javac $(JAVAC_FLAGS) -cp build/classes -d build/tests $(TESTS)
	java -ea -cp build/classes:build/tests spoonfit.Tests

run: build/classes/spoonfit/Main.class
	java -cp build/classes spoonfit.Main examples/brownies.txt --scale 1.5

clean:
	rm -rf build
