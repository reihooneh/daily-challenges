package seventh;

import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;
import java.math.RoundingMode;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.InvalidPathException;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.util.Random;
import java.util.random.RandomGenerator;

/** Command line for Seventh Shuffle. */
public final class Main {
    static final String USAGE = String.join(System.lineSeparator(),
            "Usage:",
            "  seventh check FILE        how well shuffled is this deck? (use - for standard input)",
            "  seventh deal [options]    print a deck after some riffle shuffles",
            "        --shuffles K        number of riffle shuffles, 0 to 20 (default 7)",
            "        --cards N           deck size, 2 to 520 (default 52)",
            "        --seed S            repeatable result for demos (not for real games)",
            "  seventh table [--cards N] how close to random after 1 to 12 shuffles",
            "",
            "Deck files list cards from the top: either numbers (3 1 2 ...) or all 52",
            "cards (AS 10H QD 7C ...). The starting order is 1, 2, 3, ... or a new deck:",
            "spades, hearts, diamonds, clubs, each ace to king.",
            "",
            "Exit codes: 0 well shuffled (or done), 1 not shuffled enough, 2 error.");

    private Main() {
    }

    public static void main(String[] args) {
        System.exit(run(args, System.in, System.out, System.err));
    }

    /** Runs one command and returns the exit code. Never throws for bad input. */
    public static int run(String[] args, InputStream in, PrintStream out, PrintStream err) {
        try {
            if (args.length == 0) {
                err.println(USAGE);
                return 2;
            }
            switch (args[0]) {
                case "-h", "--help", "help" -> {
                    out.println(USAGE);
                    return 0;
                }
                case "check" -> {
                    if (args.length != 2) {
                        throw new InputException("check needs exactly one file (or -)");
                    }
                    Verdict verdict = Verdict.of(Deck.parse(read(args[1], in)));
                    out.print(verdict.describe());
                    return verdict.underShuffled ? 1 : 0;
                }
                case "deal" -> {
                    return deal(args, out);
                }
                case "table" -> {
                    return table(args, out);
                }
                default -> throw new InputException("unknown command (try: seventh --help)");
            }
        } catch (InputException e) {
            err.println("seventh: " + e.getMessage());
            return 2;
        }
    }

    private static int deal(String[] args, PrintStream out) throws InputException {
        int shuffles = 7;
        int cards = 52;
        Long seed = null;
        for (int i = 1; i < args.length; i += 2) {
            String value = i + 1 < args.length ? args[i + 1] : null;
            switch (args[i]) {
                case "--shuffles" -> shuffles = number(value, "--shuffles", 0, Riffle.MAX_SHUFFLES);
                case "--cards" -> cards = number(value, "--cards", 2, Deck.MAX_CARDS);
                case "--seed" -> seed = (long) number(value, "--seed", 0, Integer.MAX_VALUE);
                default -> throw new InputException("unknown option for deal");
            }
        }
        // SecureRandom by default: unpredictable. A seed makes the result
        // repeatable, and therefore predictable, so it is only for demos.
        RandomGenerator random = seed == null ? new SecureRandom() : new Random(seed);
        int[] deck = Shuffler.riffle(Shuffler.newDeck(cards), shuffles, random);
        out.println(Deck.format(deck, cards == 52));
        return 0;
    }

    private static int table(String[] args, PrintStream out) throws InputException {
        int cards = 52;
        if (args.length == 3 && args[1].equals("--cards")) {
            cards = number(args[2], "--cards", 2, Deck.MAX_CARDS);
        } else if (args.length != 1) {
            throw new InputException("table takes only --cards N");
        }
        out.printf("Distance from perfectly random, %d cards (1 = not random at all, 0 = perfect)%n%n", cards);
        for (int k = 1; k <= 12; k++) {
            double distance = Riffle.distanceFromRandom(cards, k).setScale(3, RoundingMode.HALF_UP).doubleValue();
            out.printf("  %2d shuffle%s  %.3f  %s%n", k, k == 1 ? " " : "s", distance, "#".repeat((int) Math.round(distance * 40)));
        }
        return 0;
    }

    static int number(String text, String option, int min, int max) throws InputException {
        if (text == null || !text.matches("[0-9]{1,10}")) {
            throw new InputException(option + " needs a whole number from " + min + " to " + max);
        }
        long value = Long.parseLong(text);
        if (value < min || value > max) {
            throw new InputException(option + " needs a whole number from " + min + " to " + max);
        }
        return (int) value;
    }

    /** Reads at most MAX_INPUT_CHARS + 1 bytes, so a huge file is never loaded in full. */
    static String read(String source, InputStream in) throws InputException {
        int limit = Deck.MAX_INPUT_CHARS + 1;
        byte[] bytes;
        try {
            if (source.equals("-")) {
                bytes = in.readNBytes(limit);
            } else {
                Path path = Path.of(source);
                if (!Files.isRegularFile(path)) {
                    throw new InputException("cannot read that file");
                }
                try (InputStream file = Files.newInputStream(path)) {
                    bytes = file.readNBytes(limit);
                }
            }
        } catch (IOException | InvalidPathException | SecurityException e) {
            throw new InputException("cannot read that file");
        }
        if (bytes.length >= limit) {
            throw new InputException("input is longer than " + Deck.MAX_INPUT_CHARS + " characters");
        }
        try {
            return StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(bytes)).toString();
        } catch (CharacterCodingException e) {
            throw new InputException("input is not valid UTF-8 text");
        }
    }
}
