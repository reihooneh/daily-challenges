package changeling;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Australian cash: amounts are whole cents, held in a long so they never overflow or drift like doubles. */
public final class Money {
    /** Every Australian coin and note, smallest first, in cents. */
    public static final int[] DENOMS = {5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000};
    /** The ones that come in bank rolls, and how many coins a roll holds. */
    public static final int[] ROLL = {40, 40, 20, 20, 20, 25, 0, 0, 0, 0, 0};

    private static final Pattern AMOUNT = Pattern.compile("\\$?(\\d{1,4})(?:\\.(\\d{1,2}))?");

    private Money() {}

    /** "4.50", "$4.5" or "4" in dollars to cents. Returns -1 if it isn't a plain amount. */
    public static long parse(String text) {
        Matcher m = AMOUNT.matcher(text);
        if (!m.matches()) return -1;
        long cents = Long.parseLong(m.group(1)) * 100;
        if (m.group(2) != null) {
            String frac = m.group(2).length() == 1 ? m.group(2) + "0" : m.group(2);
            cents += Long.parseLong(frac);
        }
        return cents;
    }

    /**
     * Cash totals are rounded to the nearest 5 cents in Australia, since 1c and 2c coins
     * were withdrawn: totals ending in 1 or 2 round down, 3 or 4 round up.
     */
    public static long roundCash(long cents) {
        return (cents + 2) / 5 * 5;
    }

    public static String format(long cents) {
        return String.format("$%d.%02d", cents / 100, cents % 100);
    }

    /** "50c", "$2", "$20": the way people name a coin or note. */
    public static String name(int denomIndex) {
        int c = DENOMS[denomIndex];
        return c < 100 ? c + "c" : "$" + (c / 100);
    }

    public static boolean isCoin(int denomIndex) {
        return DENOMS[denomIndex] <= 200;
    }

    public static int indexOf(long cents) {
        for (int i = 0; i < DENOMS.length; i++) if (DENOMS[i] == cents) return i;
        return -1;
    }
}
