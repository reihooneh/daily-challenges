package spoonfit;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Kitchen units, measuring kits, and reading amounts like "2 1/4 cups". */
public final class Measures {
    private Measures() {}

    /** A region's spoon and cup sizes in millilitres. Australia's tablespoon is 20 ml, not 15. */
    public enum Region {
        AU(5.0, 20.0, 250.0), US(4.92892, 14.7868, 236.588), UK(5.0, 15.0, 250.0);

        public final double tsp, tbsp, cup;

        Region(double tsp, double tbsp, double cup) {
            this.tsp = tsp;
            this.tbsp = tbsp;
            this.cup = cup;
        }

        public static Region parse(String s) {
            try {
                return Region.valueOf(s.toUpperCase(Locale.ROOT));
            } catch (IllegalArgumentException e) {
                throw new BadInput("region must be au, us or uk");
            }
        }
    }

    /** One measure in a kit: what it's called and how much it holds. */
    public record Measure(String name, double ml) {}

    public static final class BadInput extends RuntimeException {
        private static final long serialVersionUID = 1L;

        public BadInput(String message) {
            super(message);
        }
    }

    private static final Pattern AMOUNT = Pattern.compile(
            "^(\\d{1,4}(?:\\.\\d{1,3})?)?(?:\\s*(\\d{1,2})/(\\d{1,2}))?\\s*([a-zA-Z]+)\\b\\s*(.*)$");

    /** Millilitres in one of a unit, or NaN if the unit isn't a volume. */
    public static double unitMl(String unit, Region r) {
        return switch (unit.toLowerCase(Locale.ROOT)) {
            case "tsp", "teaspoon", "teaspoons", "t" -> r.tsp;
            case "tbsp", "tablespoon", "tablespoons", "tbs" -> r.tbsp;
            case "cup", "cups", "c" -> r.cup;
            case "ml", "millilitre", "millilitres", "milliliter", "milliliters" -> 1.0;
            case "l", "litre", "litres", "liter", "liters" -> 1000.0;
            default -> Double.NaN;
        };
    }

    /** A parsed recipe line: the amount in ml (NaN when it isn't a volume), and the rest. */
    public record Line(double ml, String ingredient, String original) {}

    public static Line parseLine(String raw, Region r) {
        String line = raw.strip();
        if (line.length() > 200) throw new BadInput("a recipe line is longer than 200 characters");
        for (char c : line.toCharArray()) if (Character.isISOControl(c)) throw new BadInput("a recipe line contains a control character");
        Matcher m = AMOUNT.matcher(line);
        if (!m.matches() || (m.group(1) == null && m.group(2) == null)) return new Line(Double.NaN, line, line);
        double whole = m.group(1) == null ? 0 : Double.parseDouble(m.group(1));
        double frac = 0;
        if (m.group(2) != null) {
            int num = Integer.parseInt(m.group(2)), den = Integer.parseInt(m.group(3));
            if (den == 0 || num >= den) throw new BadInput("\"" + line + "\" has a fraction that isn't between 0 and 1");
            frac = (double) num / den;
        }
        double unit = unitMl(m.group(4), r);
        if (Double.isNaN(unit)) return new Line(Double.NaN, line, line);
        double ml = (whole + frac) * unit;
        if (!(ml > 0) || ml > 5000) throw new BadInput("\"" + line + "\" must be between 0 and 5 litres");
        return new Line(ml, m.group(5).isBlank() ? "(unnamed)" : m.group(5), line);
    }

    /** A kit as a comma list like "1 cup, 1/3 cup, 1 tbsp, 1/2 tsp", in the kit's region. */
    public static List<Measure> parseKit(String text, Region r) {
        if (text.length() > 500) throw new BadInput("the kit list is too long");
        List<Measure> out = new ArrayList<>();
        for (String part : text.split(",")) {
            Line l = parseLine(part, r);
            if (Double.isNaN(l.ml()) || !l.ingredient().equals("(unnamed)")) throw new BadInput("\"" + part.strip() + "\" isn't a measure like 1/4 cup");
            if (l.ml() < 0.5 || l.ml() > 1000) throw new BadInput("measures must hold 0.5 ml to 1 litre");
            out.add(new Measure(l.original(), l.ml()));
        }
        if (out.isEmpty() || out.size() > 16) throw new BadInput("a kit has 1 to 16 measures");
        out.sort((a, b) -> Double.compare(b.ml(), a.ml()));
        return out;
    }

    public static List<Measure> standardKit(Region r) {
        String cups = "1 cup, 1/2 cup, 1/3 cup, 1/4 cup";
        String spoons = r == Region.US ? "1 tbsp, 1 tsp, 1/2 tsp, 1/4 tsp, 1/8 tsp" : "1 tbsp, 1 tsp, 1/2 tsp, 1/4 tsp";
        return parseKit(cups + ", " + spoons, r);
    }
}
