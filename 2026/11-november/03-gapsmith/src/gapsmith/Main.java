package gapsmith;

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
 * gapsmith LAYOUT-FILE   finds the reversing loops in a track plan, where to cut the rails, and how to wire it.
 * gapsmith -             reads the layout from standard input.
 * Exit codes: 0 no cuts needed, 1 a plan with cuts (or none found), 2 bad usage or input.
 */
public final class Main {
    private Main() {}

    public static void main(String[] args) {
        System.setOut(new PrintStream(new FileOutputStream(FileDescriptor.out), true, StandardCharsets.UTF_8));
        System.setErr(new PrintStream(new FileOutputStream(FileDescriptor.err), true, StandardCharsets.UTF_8));
        System.exit(run(args));
    }

    static int run(String[] args) {
        if (args.length != 1 || args[0].startsWith("--")) {
            System.err.println("usage: gapsmith LAYOUT-FILE   (or - for standard input)");
            return 2;
        }
        try {
            String text = args[0].equals("-") ? decode(readLimited(System.in)) : decode(readFile(args[0]));
            Layout layout = Layout.parse(text);
            Planner.Plan plan = Planner.plan(layout);
            System.out.print(Report.render(layout, plan));
            return plan.alreadyFine() ? 0 : 1;
        } catch (Layout.LayoutException | IOException e) {
            System.err.println("gapsmith: " + e.getMessage());
            return 2;
        }
    }

    /** Reads a regular file (not a link, device or directory) of at most 64 KB. The path is never echoed. */
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
            throw new IOException("the layout file does not exist");
        }
        if (a.isSymbolicLink()) throw new IOException("the layout file is a symbolic link; give the real file");
        if (!a.isRegularFile()) throw new IOException("the layout file is not a regular file");
        if (a.size() > Layout.MAX_BYTES) throw new IOException("the layout file is larger than 64 KB");
        try (InputStream in = Files.newInputStream(p, LinkOption.NOFOLLOW_LINKS)) {
            return readLimited(in);
        }
    }

    static byte[] readLimited(InputStream in) throws IOException {
        byte[] data = in.readNBytes(Layout.MAX_BYTES + 1);
        if (data.length > Layout.MAX_BYTES) throw new IOException("the layout file is larger than 64 KB");
        return data;
    }

    /** Strict UTF-8: invalid bytes are an error, not silently replaced. */
    static String decode(byte[] data) throws IOException {
        try {
            String s = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(data)).toString();
            return s.startsWith("\uFEFF") ? s.substring(1) : s;
        } catch (CharacterCodingException e) {
            throw new IOException("the layout file is not valid UTF-8 text");
        }
    }
}
