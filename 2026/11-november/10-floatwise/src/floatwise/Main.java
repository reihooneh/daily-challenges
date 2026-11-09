package floatwise;

import java.io.IOException;
import java.io.PrintStream;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.BasicFileAttributes;

/** Command line: floatwise chart.txt [--max-float N] [--svg out.svg] */
public final class Main {

    static final String USAGE = """
            usage: floatwise chart.txt [--max-float N] [--svg out.svg]

            Finds the floats in a stranded colourwork chart that are too long and chooses where
            to catch them, so the catches don't line up and show through.""";

    private Main() {}

    /** A mistake in how the program was called or in its files: shown to the user as it is. */
    static final class UsageException extends Exception {
        private static final long serialVersionUID = 1L;

        UsageException(String message) {
            super(message);
        }
    }

    public static void main(String[] args) {
        PrintStream out = new PrintStream(new java.io.FileOutputStream(java.io.FileDescriptor.out), true, StandardCharsets.UTF_8);
        PrintStream err = new PrintStream(new java.io.FileOutputStream(java.io.FileDescriptor.err), true, StandardCharsets.UTF_8);
        System.exit(run(args, out, err));
    }

    static int run(String[] args, PrintStream out, PrintStream err) {
        try {
            String file = null;
            String svg = null;
            Integer maxFloat = null;
            for (int i = 0; i < args.length; i++) {
                String a = args[i];
                switch (a) {
                    case "-h", "--help" -> {
                        out.println(USAGE);
                        return 0;
                    }
                    case "--max-float" -> {
                        String v = i + 1 < args.length ? args[++i] : "";
                        if (!v.matches("\\d{1,2}") || Integer.parseInt(v) < 2 || Integer.parseInt(v) > 12) {
                            throw new UsageException("--max-float must be a whole number from 2 to 12");
                        }
                        maxFloat = Integer.parseInt(v);
                    }
                    case "--svg" -> {
                        svg = i + 1 < args.length ? args[++i] : "";
                        if (!svg.endsWith(".svg") || svg.length() < 5) {
                            throw new UsageException("--svg needs a file name ending in .svg");
                        }
                    }
                    default -> {
                        if (a.startsWith("-")) {
                            throw new UsageException("unknown option (see --help)");
                        }
                        if (file != null) {
                            throw new UsageException("give one chart file");
                        }
                        file = a;
                    }
                }
            }
            if (file == null) {
                throw new UsageException("give a chart file (see --help)");
            }
            Chart chart = Chart.parse(read(Path.of(file)));
            if (maxFloat != null) {
                chart = new Chart(chart.title(), chart.inTheRound(), maxFloat, chart.repeats(), chart.colours(), chart.rows());
            }
            Planner planner = new Planner(chart);
            Planner.Plan plan = planner.plan();
            out.print(Report.text(chart, plan, planner.evenlySpaced(), planner.floats()));
            if (svg != null) {
                write(Path.of(svg), Report.svg(chart, plan));
                out.println("\nDrawing saved to " + Path.of(svg).getFileName());
            }
            return 0;
        } catch (UsageException | Chart.ChartException e) {
            err.println("floatwise: " + e.getMessage());
            return 1;
        } catch (RuntimeException e) {
            err.println("floatwise: unexpected error");
            return 2;
        }
    }

    /** Reads a chart: a regular file (not a link), at most 64 KB, strictly valid UTF-8. */
    static String read(Path path) throws UsageException {
        try {
            BasicFileAttributes attrs = Files.readAttributes(path, BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS);
            if (!attrs.isRegularFile()) {
                throw new UsageException("the chart must be a regular file");
            }
            if (attrs.size() > Chart.MAX_BYTES) {
                throw new UsageException("the chart file is larger than 64 KB");
            }
            byte[] bytes = Files.readAllBytes(path);
            if (bytes.length > Chart.MAX_BYTES) {
                throw new UsageException("the chart file is larger than 64 KB");
            }
            return StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(bytes))
                    .toString();
        } catch (CharacterCodingException e) {
            throw new UsageException("the chart file is not valid UTF-8 text");
        } catch (IOException e) {
            throw new UsageException("cannot open the chart file");
        }
    }

    /** Writes the drawing to a new file only: never overwrites or follows a link. */
    static void write(Path path, String content) throws UsageException {
        try {
            Files.writeString(path, content, StandardCharsets.UTF_8, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE);
        } catch (java.nio.file.FileAlreadyExistsException e) {
            throw new UsageException("the drawing file already exists; choose a new name");
        } catch (IOException e) {
            throw new UsageException("cannot write the drawing file");
        }
    }
}
