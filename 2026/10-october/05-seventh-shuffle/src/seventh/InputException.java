package seventh;

/** A problem with what the user typed or supplied. The message is safe to print. */
public final class InputException extends Exception {
    private static final long serialVersionUID = 1L;

    public InputException(String message) {
        super(message);
    }
}
