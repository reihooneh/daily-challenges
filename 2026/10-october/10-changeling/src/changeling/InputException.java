package changeling;

/** A problem with the input: one line of text naming where and what, never repeating the input. */
public final class InputException extends Exception {
    private static final long serialVersionUID = 1L;

    public InputException(int line, String message) {
        super(line > 0 ? "line " + line + ": " + message : message);
    }
}
