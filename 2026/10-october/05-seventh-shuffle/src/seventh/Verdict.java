package seventh;

import java.math.BigDecimal;
import java.math.RoundingMode;

/** Everything Seventh Shuffle concludes about one deck order. */
public final class Verdict {
    /** Evidence needed before calling a deck under-shuffled: 20 to 1. */
    public static final BigDecimal THRESHOLD = BigDecimal.valueOf(20);

    public final int cards;
    public final int risingSequences;
    public final int minimumShuffles;
    public final int mostLikelyShuffles;
    /** How many times likelier this order is after the most likely count than in a random deck. */
    public final BigDecimal evidence;
    public final boolean underShuffled;

    private Verdict(int cards, int rising, int minimum, int likely, BigDecimal evidence) {
        this.cards = cards;
        this.risingSequences = rising;
        this.minimumShuffles = minimum;
        this.mostLikelyShuffles = likely;
        this.evidence = evidence;
        this.underShuffled = evidence.compareTo(THRESHOLD) >= 0;
    }

    public static Verdict of(int[] order) {
        int n = order.length;
        int r = Riffle.risingSequences(order);
        int likely = Riffle.mostLikelyShuffles(n, r);
        return new Verdict(n, r, Riffle.minimumShuffles(r), likely, Riffle.likelihoodRatio(n, r, likely));
    }

    public String describe() {
        StringBuilder out = new StringBuilder();
        double expected = (cards + 1) / 2.0;
        out.append(String.format("Cards:              %d%n", cards));
        out.append(String.format("Rising sequences:   %d   (a well-shuffled deck of this size averages %.1f)%n",
                risingSequences, expected));
        out.append(String.format("Fewest shuffles:    %d   (each riffle can at most double the rising sequences)%n",
                minimumShuffles));
        if (underShuffled) {
            out.append(String.format("Most likely:        %d riffle shuffle%s%n",
                    mostLikelyShuffles, mostLikelyShuffles == 1 ? "" : "s"));
            out.append(String.format("Evidence:           this order is %s times more likely after %d shuffle%s "
                            + "than in a truly random deck%n",
                    readable(evidence), mostLikelyShuffles, mostLikelyShuffles == 1 ? "" : "s"));
            out.append(String.format("%nVERDICT: not shuffled enough. The original order is still showing.%n"));
        } else {
            out.append(String.format("Evidence:           no shuffle count explains this order much better than chance "
                    + "(best ratio %s to 1)%n", readable(evidence)));
            out.append(String.format("%nVERDICT: consistent with a well-shuffled deck.%n"));
        }
        return out.toString();
    }

    /** 3.2, 150, 4.1 million, 10^31 ... never a wall of digits. */
    static String readable(BigDecimal value) {
        if (value.compareTo(BigDecimal.valueOf(1000)) < 0) {
            return value.setScale(value.compareTo(BigDecimal.TEN) < 0 ? 1 : 0, RoundingMode.HALF_UP).toPlainString();
        }
        int digits = value.precision() - value.scale(); // digits before the decimal point
        if (digits <= 6) {
            return String.format("%,d", value.setScale(0, RoundingMode.HALF_UP).longValueExact());
        }
        if (digits <= 9) {
            return value.movePointLeft(6).setScale(1, RoundingMode.HALF_UP).toPlainString() + " million";
        }
        return "about 10^" + (digits - 1);
    }
}
