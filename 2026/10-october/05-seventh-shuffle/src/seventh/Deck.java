package seventh;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Reads a deck order from text and turns it into a permutation.
 *
 * <p>Two notations are accepted:
 * <ul>
 *   <li>numbers: {@code 3 1 2 5 4} (any deck size; must use each of 1..n once)</li>
 *   <li>cards: {@code AS 2S ... KC} (a full 52-card deck, each card once)</li>
 * </ul>
 * The result is an int array where {@code order[i]} is the card (0-based, in
 * "new deck" order) found at position i from the top.
 */
public final class Deck {
    public static final int MAX_CARDS = 520; // ten decks
    public static final int MAX_INPUT_CHARS = 16_384;

    private static final String RANKS = "A23456789TJQK";
    private static final String SUITS = "SHDC";

    private Deck() {
    }

    /** Parses deck text. Never echoes the input back in an error message. */
    public static int[] parse(String text) throws InputException {
        if (text == null) {
            throw new InputException("no deck given");
        }
        if (text.length() > MAX_INPUT_CHARS) {
            throw new InputException("input is longer than " + MAX_INPUT_CHARS + " characters");
        }
        List<String> tokens = new ArrayList<>();
        for (String line : text.split("\\R", -1)) {
            int hash = line.indexOf('#');
            String content = hash >= 0 ? line.substring(0, hash) : line;
            for (String token : content.split("[\\s,]+")) {
                if (!token.isEmpty()) {
                    tokens.add(token);
                }
            }
        }
        if (tokens.size() < 2) {
            throw new InputException("a deck needs at least 2 cards");
        }
        if (tokens.size() > MAX_CARDS) {
            throw new InputException("a deck can have at most " + MAX_CARDS + " cards");
        }

        boolean numeric = isNumber(tokens.get(0));
        int n = tokens.size();
        if (!numeric && n != 52) {
            throw new InputException("card notation needs exactly 52 cards, but " + n + " were given");
        }
        int[] order = new int[n];
        boolean[] seen = new boolean[n];
        for (int i = 0; i < n; i++) {
            int card = numeric ? numberToCard(tokens.get(i), n, i) : nameToCard(tokens.get(i), i);
            if (seen[card]) {
                throw new InputException("card " + (i + 1) + " in the list is a duplicate");
            }
            seen[card] = true;
            order[i] = card;
        }
        return order;
    }

    private static boolean isNumber(String token) {
        if (token.isEmpty() || token.length() > 3) {
            return false;
        }
        for (int i = 0; i < token.length(); i++) {
            char c = token.charAt(i);
            if (c < '0' || c > '9') {
                return false;
            }
        }
        // "10S" style card names are not numbers, but "10" alone is.
        return true;
    }

    private static int numberToCard(String token, int n, int index) throws InputException {
        if (!isNumber(token)) {
            throw new InputException("card " + (index + 1) + " in the list is not a number between 1 and " + n);
        }
        int value = Integer.parseInt(token);
        if (value < 1 || value > n) {
            throw new InputException("card " + (index + 1) + " in the list is not a number between 1 and " + n);
        }
        return value - 1;
    }

    private static int nameToCard(String token, int index) throws InputException {
        String name = token.toUpperCase(Locale.ROOT)
                .replace('♠', 'S').replace('♥', 'H').replace('♦', 'D').replace('♣', 'C');
        if (name.startsWith("10")) {
            name = "T" + name.substring(2);
        }
        if (name.length() != 2 || RANKS.indexOf(name.charAt(0)) < 0 || SUITS.indexOf(name.charAt(1)) < 0) {
            throw new InputException("card " + (index + 1) + " in the list is not a card (use names like AS, 10H, QD, 7C)");
        }
        return SUITS.indexOf(name.charAt(1)) * 13 + RANKS.indexOf(name.charAt(0));
    }

    /** Formats a deck the way it would be typed in. Cards for 52, numbers otherwise. */
    public static String format(int[] order, boolean asCards) {
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < order.length; i++) {
            if (i > 0) {
                out.append(asCards && i % 13 == 0 ? '\n' : ' ');
            }
            if (asCards) {
                char rank = RANKS.charAt(order[i] % 13);
                out.append(rank == 'T' ? "10" : String.valueOf(rank)).append(SUITS.charAt(order[i] / 13));
            } else {
                out.append(order[i] + 1);
            }
        }
        return out.toString();
    }
}
