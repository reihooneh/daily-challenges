package ferryglide;

import java.io.FileDescriptor;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.InvalidPathException;
import java.nio.file.LinkOption;
import java.nio.file.NoSuchFileException;
import java.nio.file.Path;
import java.nio.file.attribute.BasicFileAttributes;

/**
 * ferryglide PLAN-FILE   finds when to leave so the tide helps you across.
 * ferryglide -           reads the plan from standard input.
 * Exit codes: 0 a good departure exists, 1 none in the window, 2 bad usage or input.
 */
public final class Main {
    private Main() {}

    public static void main(String[] args) {
        // Always print UTF-8 (degree signs), whatever the terminal's locale says.
        System.setOut(new PrintStream(new FileOutputStream(FileDescriptor.out), true, StandardCharsets.UTF_8));
        System.setErr(new PrintStream(new FileOutputStream(FileDescriptor.err), true, StandardCharsets.UTF_8));
        System.exit(run(args));
    }

    static int run(String[] args) {
        if (args.length != 1 || args[0].startsWith("--")) {
            System.err.println("usage: ferryglide PLAN-FILE   (or - for standard input)");
            return 2;
        }
        try {
            String text = args[0].equals("-") ? decode(readLimited(System.in)) : decode(readFile(args[0]));
            Plan plan = PlanParser.parse(text);
            Planner.Result r = Planner.plan(plan);
            System.out.print(Report.render(plan, r));
            return r.best() != null ? 0 : 1;
        } catch (PlanParser.PlanException e) {
            System.err.println("ferryglide: " + e.getMessage());
            return 2;
        } catch (IOException e) {
            System.err.println("ferryglide: " + e.getMessage());
            return 2;
        }
    }

    /** Reads a regular file (not a link, device or directory) of at most 64 KB. */
    static byte[] readFile(String name) throws IOException {
        Path p;
        try {
            p = Path.of(name);
        } catch (InvalidPathException e) {
            throw new IOException("that file name isn't valid");
        }
        BasicFileAttributes a;
        try {
            a = Files.readAttributes(p, BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS);
        } catch (NoSuchFileException e) {
            throw new IOException(clean(name) + " does not exist");
        }
        if (a.isSymbolicLink()) throw new IOException(clean(name) + " is a symbolic link; give the real file");
        if (!a.isRegularFile()) throw new IOException(clean(name) + " is not a regular file");
        if (a.size() > PlanParser.MAX_BYTES) throw new IOException("the plan is larger than 64 KB");
        try (InputStream in = Files.newInputStream(p, LinkOption.NOFOLLOW_LINKS)) {
            return readLimited(in);
        }
    }

    static byte[] readLimited(InputStream in) throws IOException {
        byte[] data = in.readNBytes(PlanParser.MAX_BYTES + 1);
        if (data.length > PlanParser.MAX_BYTES) throw new IOException("the plan is larger than 64 KB");
        return data;
    }

    /** Strict UTF-8: invalid bytes are an error, not silently replaced. */
    static String decode(byte[] data) throws IOException {
        try {
            String s = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(data)).toString();
            return s.startsWith("\uFEFF") ? s.substring(1) : s;
        } catch (CharacterCodingException e) {
            throw new IOException("the plan is not valid UTF-8 text");
        }
    }

    /** Only plain characters of a file name go into messages. */
    static String clean(String name) {
        int slash = Math.max(name.lastIndexOf('/'), name.lastIndexOf('\\'));
        String base = name.substring(slash + 1);
        String s = base.replaceAll("[^\\w .,-]", "?");
        return s.length() > 60 ? s.substring(0, 60) : s;
    }
}
