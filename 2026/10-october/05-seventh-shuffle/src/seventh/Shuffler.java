package seventh;

import java.util.random.RandomGenerator;

/**
 * Simulates a human riffle shuffle using the Gilbert-Shannon-Reeds model,
 * which matches how people really shuffle surprisingly well:
 *
 * <ol>
 *   <li>Cut the deck roughly in half (flip a coin per card to decide the size
 *       of the top half).</li>
 *   <li>Drop cards one at a time from the two halves; the bigger a half is,
 *       the more likely the next card falls from it.</li>
 * </ol>
 */
public final class Shuffler {
    private Shuffler() {
    }

    public static int[] newDeck(int n) {
        int[] deck = new int[n];
        for (int i = 0; i < n; i++) {
            deck[i] = i;
        }
        return deck;
    }

    /** Returns a new array; the input is left untouched. */
    public static int[] riffle(int[] deck, RandomGenerator random) {
        int n = deck.length;
        int cut = 0;
        for (int i = 0; i < n; i++) {
            if (random.nextBoolean()) {
                cut++;
            }
        }
        int[] result = new int[n];
        int left = 0;
        int right = cut;
        for (int i = 0; i < n; i++) {
            int leftRemaining = cut - left;
            int rightRemaining = n - right;
            boolean fromLeft = random.nextInt(leftRemaining + rightRemaining) < leftRemaining;
            result[i] = fromLeft ? deck[left++] : deck[right++];
        }
        return result;
    }

    public static int[] riffle(int[] deck, int times, RandomGenerator random) {
        int[] current = deck.clone();
        for (int i = 0; i < times; i++) {
            current = riffle(current, random);
        }
        return current;
    }
}
