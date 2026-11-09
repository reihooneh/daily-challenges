package floatwise;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * A stranded colourwork chart: its colours, its rows, and how it is knitted.
 *
 * <p>Rows are stored bottom first, so {@code rows.get(0)} is round (or row) 1, the first one
 * knitted, even though the file lists them top first, the way a chart is printed. Column 0 is
 * the left edge of the chart as printed; knitters count stitches from the right.
 */
public record Chart(
        String title,
        boolean inTheRound,
        int maxFloat,
        int repeats,
        Map<Character, Colour> colours,
        List<String> rows) {

    /** One yarn: its chart symbol, its name, and the colour used to draw it. */
    public record Colour(char symbol, String name, String hex) {}

    public static final int MAX_BYTES = 64 * 1024;
    public static final int MAX_WIDTH = 64;
    public static final int MAX_ROWS = 200;
    public static final int MAX_COLOURS = 8;

    private static final Pattern NAME = Pattern.compile("[\\p{L}\\p{N} '()-]{1,30}");
    private static final Pattern TITLE = Pattern.compile("[\\p{L}\\p{N} ',.()&-]{1,60}");
    private static final Pattern HEX = Pattern.compile("#[0-9a-fA-F]{6}");
    private static final Pattern SYMBOL = Pattern.compile("[!-~]");
    private static final String[] DEFAULT_HEX = {
        "#f2ead8", "#1f3a5f", "#b33a3a", "#3f7d4e", "#d9a441", "#6b4c8a", "#2b2b2b", "#8fb8c9"
    };

    /** A problem with the chart file, with the line it was found on. */
    public static final class ChartException extends Exception {
        private static final long serialVersionUID = 1L;

        ChartException(int line, String message) {
            super(line > 0 ? "line " + line + ": " + message : message);
        }
    }

    public Chart {
        colours = Map.copyOf(colours);
        rows = List.copyOf(rows);
    }

    public int width() {
        return rows.get(0).length();
    }

    public int height() {
        return rows.size();
    }

    public char at(int row, int column) {
        return rows.get(row).charAt(column);
    }

    /** "Round 3" or "Row 3", counting from 1 at the bottom. */
    public String rowName(int row) {
        return (inTheRound ? "Round " : "Row ") + (row + 1);
    }

    /** The stitch number a knitter reads: counted from the right of the repeat, from 1. */
    public int stitchNumber(int column) {
        return width() - column;
    }

    /** Reads a chart file's text. */
    public static Chart parse(String text) throws ChartException {
        if (text.length() > MAX_BYTES) {
            throw new ChartException(0, "the chart is larger than 64 KB");
        }
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            boolean control = Character.isISOControl(c) && c != '\n' && c != '\r' && c != '\t';
            int type = Character.getType(c);
            if (control || type == Character.FORMAT || type == Character.SURROGATE || type == Character.PRIVATE_USE) {
                throw new ChartException(0, "the chart contains control or invisible formatting characters");
            }
        }
        String[] lines = text.split("\r?\n", -1);
        String title = "Untitled chart";
        boolean round = true;
        int maxFloat = 5;
        int repeats = 1;
        Map<Character, Colour> colours = new LinkedHashMap<>();
        List<String> printed = new ArrayList<>();
        List<Integer> printedLines = new ArrayList<>();
        boolean inChart = false;
        java.util.Set<String> seen = new java.util.HashSet<>();

        for (int k = 0; k < lines.length; k++) {
            int line = k + 1;
            String raw = lines[k];
            if (inChart) {
                String row = raw.strip();
                if (row.isEmpty() || row.startsWith("//")) {
                    continue;
                }
                if (printed.size() >= MAX_ROWS) {
                    throw new ChartException(line, "a chart can have at most " + MAX_ROWS + " rows");
                }
                printed.add(row);
                printedLines.add(line);
                continue;
            }
            String body = raw.strip();
            if (body.isEmpty() || body.startsWith("//")) {
                continue;
            }
            if (body.equals("chart:")) {
                inChart = true;
                continue;
            }
            int colon = body.indexOf(':');
            String key = colon > 0 ? body.substring(0, colon).strip() : body.split("\\s+")[0];
            String value = colon > 0 ? body.substring(colon + 1).strip() : body.substring(key.length()).strip();
            if (!key.equals("colour") && !seen.add(key)) {
                throw new ChartException(line, key + " is given twice");
            }
            switch (key) {
                case "title" -> {
                    if (!TITLE.matcher(value).matches()) {
                        throw new ChartException(line, "a title is 1-60 letters, digits, spaces and simple punctuation");
                    }
                    title = value;
                }
                case "knit" -> {
                    if (!value.equals("round") && !value.equals("flat")) {
                        throw new ChartException(line, "knit must be \"round\" or \"flat\"");
                    }
                    round = value.equals("round");
                }
                case "max-float" -> maxFloat = integer(value, line, 2, 12);
                case "repeats" -> repeats = integer(value, line, 1, 500);
                case "colour" -> {
                    // colour <symbol> <name words> [#rrggbb]
                    String[] parts = value.split("\\s+");
                    if (parts.length < 2 || !SYMBOL.matcher(parts[0]).matches()) {
                        throw new ChartException(line, "write a colour as: colour <one symbol> <name> [#rrggbb]");
                    }
                    char symbol = parts[0].charAt(0);
                    String hex = null;
                    int end = parts.length;
                    if (HEX.matcher(parts[end - 1]).matches()) {
                        hex = parts[end - 1].toLowerCase(java.util.Locale.ROOT);
                        end--;
                    }
                    String name = String.join(" ", java.util.Arrays.copyOfRange(parts, 1, end));
                    if (!NAME.matcher(name).matches()) {
                        throw new ChartException(line, "a colour name is 1-30 letters, digits and spaces");
                    }
                    if (colours.containsKey(symbol)) {
                        throw new ChartException(line, "that symbol already has a colour");
                    }
                    if (colours.size() >= MAX_COLOURS) {
                        throw new ChartException(line, "at most " + MAX_COLOURS + " colours");
                    }
                    colours.put(symbol, new Colour(symbol, name, hex != null ? hex : DEFAULT_HEX[colours.size()]));
                }
                default -> throw new ChartException(line, "unknown setting (use title, knit, max-float, repeats, colour, chart:)");
            }
        }

        if (colours.size() < 2) {
            throw new ChartException(0, "declare at least two colours, e.g. \"colour . cream\" and \"colour x navy\"");
        }
        if (printed.isEmpty()) {
            throw new ChartException(0, "no chart: add a line \"chart:\" followed by the rows");
        }
        int width = printed.get(0).length();
        if (width < 2 || width > MAX_WIDTH) {
            throw new ChartException(printedLines.get(0), "a row must be 2-" + MAX_WIDTH + " stitches wide");
        }
        for (int r = 0; r < printed.size(); r++) {
            String row = printed.get(r);
            int line = printedLines.get(r);
            if (row.length() != width) {
                throw new ChartException(line, "row is " + row.length() + " stitches but the first row is " + width);
            }
            for (int c = 0; c < width; c++) {
                if (!colours.containsKey(row.charAt(c))) {
                    throw new ChartException(line, "stitch " + (width - c) + " uses a symbol with no colour");
                }
            }
        }
        List<String> bottomFirst = new ArrayList<>(printed);
        java.util.Collections.reverse(bottomFirst);
        return new Chart(title, round, maxFloat, repeats, colours, bottomFirst);
    }

    private static int integer(String value, int line, int lo, int hi) throws ChartException {
        if (!value.matches("\\d{1,4}")) {
            throw new ChartException(line, "expected a whole number");
        }
        int v = Integer.parseInt(value);
        if (v < lo || v > hi) {
            throw new ChartException(line, "must be between " + lo + " and " + hi);
        }
        return v;
    }
}
