package changeling;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

/**
 * A market stall, read from a small text file:
 *
 * <pre>
 *   title     Saturday lemonade stand
 *   budget    150           # cash you can put in the float, in dollars
 *   customers 120           # cash customers in a day
 *   basket    1-3           # items each customer buys
 *   item lemonade 4.50 weight 5
 *   pays exact 15           # per cent of customers by how they pay
 *   pays smallest 45        # the smallest note that covers it
 *   pays 20 30              # a $20 note (from the ATM)
 *   pays 50 10
 * </pre>
 *
 * Every value is checked against an allow-list and a range. Errors give the line number
 * and the problem, never the offending text.
 */
public final class Stall {
    public record Item(String name, long cents, int weight) {}

    /** How a customer pays: exact money, the smallest covering note, or a particular note. */
    public enum PayKind { EXACT, SMALLEST, NOTE }

    public record Payment(PayKind kind, int note, int percent) {}

    public static final int MAX_BYTES = 64 * 1024;
    public static final int MAX_LINE = 200;
    public static final int MAX_ITEMS = 30;

    private static final Pattern NAME = Pattern.compile("[a-z][a-z0-9_-]{0,23}");
    private static final Pattern TITLE = Pattern.compile("[A-Za-z0-9 .,'&!?:-]{1,60}");
    private static final Pattern INT = Pattern.compile("\\d{1,5}");
    private static final Pattern RANGE = Pattern.compile("(\\d{1,2})-(\\d{1,2})");

    public String title = "My stall";
    public long budget = 15000;
    public int customers = 100;
    public int basketMin = 1;
    public int basketMax = 1;
    public final List<Item> items = new ArrayList<>();
    public final List<Payment> payments = new ArrayList<>();

    /** Same stall with one item's price changed: used to test price nudges. */
    public Stall withPrice(int itemIndex, long cents) {
        Stall s = new Stall();
        s.title = title;
        s.budget = budget;
        s.customers = customers;
        s.basketMin = basketMin;
        s.basketMax = basketMax;
        s.payments.addAll(payments);
        for (int i = 0; i < items.size(); i++) {
            Item it = items.get(i);
            s.items.add(i == itemIndex ? new Item(it.name(), cents, it.weight()) : it);
        }
        return s;
    }

    public static Stall parse(String text) throws InputException {
        if (text.length() > MAX_BYTES) throw new InputException(0, "the stall file is larger than 64 KB");
        Stall s = new Stall();
        boolean sawPays = false;
        String[] lines = text.split("\n", -1);
        for (int i = 0; i < lines.length; i++) {
            int n = i + 1;
            String raw = lines[i].endsWith("\r") ? lines[i].substring(0, lines[i].length() - 1) : lines[i];
            if (raw.length() > MAX_LINE) throw new InputException(n, "the line is longer than " + MAX_LINE + " characters");
            for (int k = 0; k < raw.length(); k++) {
                char c = raw.charAt(k);
                if ((c < 0x20 && c != '\t') || c > 0x7e) throw new InputException(n, "only plain printable ASCII text is allowed");
            }
            int hash = raw.indexOf('#');
            String line = (hash >= 0 ? raw.substring(0, hash) : raw).trim();
            if (line.isEmpty()) continue;
            String[] w = line.split("[ \t]+");
            switch (w[0]) {
                case "title" -> {
                    String t = line.substring(5).trim();
                    if (!TITLE.matcher(t).matches()) throw new InputException(n, "the title must be 1-60 letters, digits, spaces or . , ' & ! ? : -");
                    s.title = t;
                }
                case "budget" -> {
                    long b = w.length == 2 ? Money.parse(w[1]) : -1;
                    if (b < 0 || b > 500_000 || b % 5 != 0) throw new InputException(n, "the budget must be an amount from $0 to $5000, in 5c steps");
                    s.budget = b;
                }
                case "customers" -> s.customers = number(w, n, 1, 2000, "customers must be a whole number from 1 to 2000");
                case "basket" -> {
                    var m = w.length == 2 ? RANGE.matcher(w[1]) : null;
                    if (m != null && m.matches()) {
                        s.basketMin = Integer.parseInt(m.group(1));
                        s.basketMax = Integer.parseInt(m.group(2));
                    } else {
                        int b = number(w, n, 1, 10, "write the basket as N or N-M, from 1 to 10 items");
                        s.basketMin = b;
                        s.basketMax = b;
                    }
                    if (s.basketMin < 1 || s.basketMax > 10 || s.basketMin > s.basketMax)
                        throw new InputException(n, "write the basket as N or N-M, from 1 to 10 items");
                }
                case "item" -> {
                    if (w.length != 5 || !w[3].equals("weight")) throw new InputException(n, "write an item as: item NAME PRICE weight N");
                    if (!NAME.matcher(w[1]).matches()) throw new InputException(n, "the item name is not valid (a-z, 0-9, _ and -, starting with a letter)");
                    long price = Money.parse(w[2]);
                    if (price < 5 || price > 100_000) throw new InputException(n, "the price must be from $0.05 to $1000");
                    int weight = number(new String[] {"", w[4]}, n, 1, 1000, "the weight must be a whole number from 1 to 1000");
                    for (Item it : s.items) if (it.name().equals(w[1])) throw new InputException(n, "this item name is already used");
                    if (s.items.size() >= MAX_ITEMS) throw new InputException(n, "too many items (the limit is " + MAX_ITEMS + ")");
                    s.items.add(new Item(w[1], price, weight));
                }
                case "pays" -> {
                    if (w.length != 3) throw new InputException(n, "write it as: pays exact|smallest|5|10|20|50|100 PERCENT");
                    int pct = number(new String[] {"", w[2]}, n, 0, 100, "the share must be a whole per cent from 0 to 100");
                    Payment p = switch (w[1]) {
                        case "exact" -> new Payment(PayKind.EXACT, 0, pct);
                        case "smallest" -> new Payment(PayKind.SMALLEST, 0, pct);
                        case "5", "10", "20", "50", "100" -> new Payment(PayKind.NOTE, Money.indexOf(Long.parseLong(w[1]) * 100), pct);
                        default -> throw new InputException(n, "customers pay exact, smallest, or with a 5, 10, 20, 50 or 100 dollar note");
                    };
                    for (Payment q : s.payments)
                        if (q.kind() == p.kind() && q.note() == p.note()) throw new InputException(n, "this way of paying is already listed");
                    s.payments.add(p);
                    sawPays = true;
                }
                default -> throw new InputException(n, "unknown keyword (expected title, budget, customers, basket, item or pays)");
            }
        }
        if (s.items.isEmpty()) throw new InputException(0, "the stall has no items");
        if (!sawPays) {
            s.payments.add(new Payment(PayKind.EXACT, 0, 15));
            s.payments.add(new Payment(PayKind.SMALLEST, 0, 55));
            s.payments.add(new Payment(PayKind.NOTE, Money.indexOf(2000), 25));
            s.payments.add(new Payment(PayKind.NOTE, Money.indexOf(5000), 5));
        }
        int total = s.payments.stream().mapToInt(Payment::percent).sum();
        if (total != 100) throw new InputException(0, "the pays lines must add up to 100 per cent (they add up to " + total + ")");
        return s;
    }

    private static int number(String[] w, int line, int lo, int hi, String message) throws InputException {
        if (w.length != 2 || !INT.matcher(w[1]).matches()) throw new InputException(line, message);
        int v = Integer.parseInt(w[1]);
        if (v < lo || v > hi) throw new InputException(line, message);
        return v;
    }
}
