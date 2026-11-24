package spoonfit;

import java.io.IOException;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.regex.Pattern;

/** spoonfit RECIPE.txt [--scale X] [--from us|au|uk] [--kit au|us|uk|"1 cup, 1 tbsp, ..."] */
public final class Main {
    private Main() {}

    static final long MAX_BYTES = 32 * 1024;
    static final int MAX_LINES = 200;
    private static final Pattern STRICT = Pattern.compile("(?i)\\b(baking soda|bicarb|baking powder|salt|yeast|cream of tartar)\\b");

    record Options(Path recipe, double scale, Measures.Region from, String kit, Measures.Region kitRegion) {}

    static Options options(String[] args) {
        Path recipe = null;
        double scale = 1;
        Measures.Region from = Measures.Region.US, kitRegion = Measures.Region.AU;
        String kit = null;
        for (int i = 0; i < args.length; i++) {
            String a = args[i];
            if (a.startsWith("--")) {
                if (i + 1 >= args.length) throw new Measures.BadInput(a + " needs a value");
                String v = args[++i];
                switch (a) {
                    case "--scale" -> {
                        try {
                            scale = Double.parseDouble(v);
                        } catch (NumberFormatException e) {
                            throw new Measures.BadInput("--scale needs a number");
                        }
                        if (!(scale >= 0.05 && scale <= 20)) throw new Measures.BadInput("--scale must be between 0.05 and 20");
                    }
                    case "--from" -> from = Measures.Region.parse(v);
                    case "--kit" -> {
                        if (v.matches("(?i)au|us|uk")) kitRegion = Measures.Region.parse(v);
                        else kit = v;
                    }
                    default -> throw new Measures.BadInput("unknown option " + a.replaceAll("\\p{Cntrl}", ""));
                }
            } else if (recipe == null) {
                recipe = Path.of(a);
            } else {
                throw new Measures.BadInput("only one recipe at a time");
            }
        }
        if (recipe == null) throw new Measures.BadInput("usage: spoonfit RECIPE.txt [--scale X] [--from us|au|uk] [--kit au|us|uk|LIST]");
        return new Options(recipe, scale, from, kit, kitRegion);
    }

    static String describe(Planner.Plan p) {
        List<String> parts = new ArrayList<>();
        for (Planner.Scoop s : p.add()) parts.add((s.count() > 1 ? s.count() + " x " : "") + s.measure().name());
        String out = String.join(" + ", parts);
        if (p.takeOut() != null) out += ", less " + p.takeOut().name();
        return out;
    }

    static String run(Options o, String text) {
        List<Measures.Measure> kit = o.kit() == null ? Measures.standardKit(o.kitRegion()) : Measures.parseKit(o.kit(), o.kitRegion());
        Planner planner = new Planner(kit);
        StringBuilder sb = new StringBuilder();
        sb.append(String.format(Locale.ROOT, "Scaled by %s, from %s measures, with your %s kit (%d measures).%n%n",
                trim(o.scale()), o.from(), o.kit() == null ? o.kitRegion() : "own", kit.size()));
        String[] lines = text.split("\\R", -1);
        if (lines.length > MAX_LINES) throw new Measures.BadInput("the recipe has more than " + MAX_LINES + " lines");
        for (String raw : lines) {
            if (raw.isBlank() || raw.strip().startsWith("#")) continue;
            Measures.Line l = Measures.parseLine(raw, o.from());
            if (Double.isNaN(l.ml())) {
                sb.append(String.format(Locale.ROOT, "  %-28s %s%n", clip(l.original()), "(not a volume: scale by hand)"));
                continue;
            }
            double target = l.ml() * o.scale();
            if (target > Planner.MAX_ML) throw new Measures.BadInput("\"" + l.original() + "\" scales past 2 litres");
            boolean strict = STRICT.matcher(l.ingredient()).find();
            Planner.Plan p = planner.plan(target, strict ? 0.02 : 0.05, true);
            String err = Math.abs(p.error()) < 0.0005 ? "exact" : String.format(Locale.ROOT, "%+.1f%%", p.error() * 100);
            boolean within = Math.abs(p.error()) <= (strict ? 0.02 : 0.05) + 1e-9;
            sb.append(String.format(Locale.ROOT, "  %-28s %7.1f ml  %-38s %s%s%n", clip(l.ingredient()), target, describe(p), err,
                    within ? "" : "  (closest your kit can do)"));
        }
        return sb.toString();
    }

    static String trim(double d) {
        return d == Math.rint(d) ? String.valueOf((long) d) : String.valueOf(d);
    }

    static String clip(String s) {
        return s.length() > 28 ? s.substring(0, 25) + "..." : s;
    }

    static String read(Path p) throws IOException {
        if (!Files.isRegularFile(p, LinkOption.NOFOLLOW_LINKS) || Files.size(p) > MAX_BYTES) {
            throw new Measures.BadInput("the recipe must be a regular file under 32 KB");
        }
        byte[] bytes = Files.readAllBytes(p);
        try {
            return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(java.nio.ByteBuffer.wrap(bytes)).toString();
        } catch (CharacterCodingException e) {
            throw new Measures.BadInput("the recipe isn't UTF-8 text");
        }
    }

    public static void main(String[] args) {
        try {
            Options o = options(args);
            System.out.print(run(o, read(o.recipe())));
        } catch (Measures.BadInput e) {
            System.err.println("spoonfit: " + e.getMessage());
            System.exit(2);
        } catch (IOException e) {
            System.err.println("spoonfit: can't read the recipe");
            System.exit(2);
        }
    }
}
