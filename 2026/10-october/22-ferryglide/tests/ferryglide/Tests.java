package ferryglide;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

/** A small test runner: each check prints on failure; the exit code says whether all passed. */
public final class Tests {
    private static int checks = 0, failed = 0;
    private static final java.io.PrintStream RESULTS = System.out;  // still visible while output is silenced

    private static void check(boolean ok, String what) {
        checks++;
        if (!ok) {
            failed++;
            RESULTS.println("FAIL: " + what);
        }
    }

    private static void near(double a, double b, double tol, String what) {
        check(Math.abs(a - b) <= tol, what + " (" + a + " vs " + b + ")");
    }

    private static void rejects(String text, String fragment) {
        try {
            PlanParser.parse(text);
            check(false, "should reject: " + fragment);
        } catch (PlanParser.PlanException e) {
            check(e.getMessage().contains(fragment), "message '" + e.getMessage() + "' should mention '" + fragment + "'");
        }
    }

    static final String HEADER = """
            trip Test
            paddle 3
            window 06:00 to 10:00
            station Ref, flood 0
            event 05:00 slack
            event 08:00 flood 2
            event 11:00 slack
            event 14:00 ebb 2
            event 17:00 slack
            """;

    static Plan plan(String legs) throws PlanParser.PlanException {
        return PlanParser.parse(HEADER + legs);
    }

    public static void main(String[] args) throws Exception {
        // The command-line checks print reports; keep the test output to the results.
        java.io.PrintStream realOut = System.out, realErr = System.err;
        java.io.PrintStream quiet = new java.io.PrintStream(java.io.OutputStream.nullOutputStream());
        current();
        vectors();
        legs();
        planner();
        parser();
        System.setOut(quiet);
        System.setErr(quiet);
        try {
            files();
        } finally {
            System.setOut(realOut);
            System.setErr(realErr);
        }
        System.out.println(checks + " checks, " + failed + " failed");
        System.exit(failed == 0 ? 0 : 1);
    }

    static void current() throws Exception {
        Current c = new Current(plan("leg A: 1 nm, course 0, offset 0, ratio 1").station().events());
        near(c.at(300), 0, 1e-12, "slack");
        near(c.at(480), 2, 1e-12, "maximum flood");
        near(c.at(390), 2 * Math.sin(Math.PI / 4), 1e-12, "halfway to the maximum: rule of cosine");
        near(c.at(570), 2 * Math.cos(Math.PI / 4), 1e-12, "halfway back to slack");
        near(c.at(840), -2, 1e-12, "maximum ebb is negative");
        check(Double.isNaN(c.at(299)) && Double.isNaN(c.at(1021)), "outside the table is unknown, not zero");
        double prev = c.at(300);
        boolean smooth = true;
        for (int t = 301; t <= 1020; t++) {
            double v = c.at(t);
            if (Math.abs(v - prev) > 0.02) smooth = false;
            prev = v;
        }
        check(smooth, "the stream changes smoothly minute to minute");
    }

    static void vectors() throws Exception {
        Plan p = plan("leg A: 1 nm, course 90, offset 0, ratio 1");
        Navigator nav = new Navigator(new Current(p.station().events()), 3);
        Plan.Leg leg = p.legs().get(0);
        // At 08:00 the flood sets north (0°) at 2 kn; the course is east (90°): a pure cross-current.
        Navigator.Stream s = nav.stream(leg, 480);
        near(s.along(), 0, 1e-12, "cross-current has nothing along the course");
        near(Math.abs(s.cross()), 2, 1e-12, "all of it is across");
        near(nav.groundSpeed(s), Math.sqrt(9 - 4), 1e-12, "ferry glide: sqrt(P^2 - c^2)");
        // The stream pushes north (to port of an eastward course), so steer to the south of east.
        near(nav.heading(leg, s), 90 + Math.toDegrees(Math.asin(2.0 / 3)), 1e-9, "heading points up into the stream");
        Plan.Leg with = new Plan.Leg("with", 1, 0, 0, 1, 0);
        near(nav.groundSpeed(nav.stream(with, 480)), 5, 1e-12, "a following stream adds");
        near(nav.heading(with, nav.stream(with, 480)), 0, 1e-9, "no crab angle with a following stream");
        Plan.Leg against = new Plan.Leg("against", 1, 180, 0, 1, 0);
        near(nav.groundSpeed(nav.stream(against, 480)), 1, 1e-12, "a head stream subtracts");
        Navigator slow = new Navigator(new Current(p.station().events()), 1.5);
        check(Double.isNaN(slow.groundSpeed(slow.stream(leg, 480))), "can't hold a line across a stream faster than you");
        near(Navigator.norm(-30), 330, 1e-12, "directions wrap");
    }

    static void legs() throws Exception {
        Plan p = plan("leg Still: 2 nm, course 45, offset 0, ratio 0");
        Navigator nav = new Navigator(new Current(p.station().events()), 3);
        Navigator.LegRun r = nav.runLeg(p.legs().get(0), 400);
        check(r.ok(), "still water leg completes");
        near(r.minutes(), 40, 1e-6, "2 nm at 3 kn takes 40 minutes");
        Plan.Leg fair = new Plan.Leg("fair", 2, 0, 0, 1, 0);
        Plan.Leg foul = new Plan.Leg("foul", 2, 180, 0, 1, 0);
        double tFair = nav.runLeg(fair, 450).minutes(), tFoul = nav.runLeg(foul, 450).minutes();
        check(tFair < 40 && tFoul > 40, "a fair stream shortens the leg, a foul one lengthens it");
        // Integrating the stream must agree with distance = average speed x time.
        Navigator.LegRun fr = nav.runLeg(fair, 450);
        double dist = 0;
        for (double t = fr.start(); t < fr.end(); t += 0.001) dist += (3 + new Current(p.station().events()).at(t)) * 0.001 / 60;
        near(dist, 2, 0.01, "integration agrees with a fine-grained check");
        Navigator weak = new Navigator(new Current(p.station().events()), 1.0);
        Navigator.LegRun stuck = weak.runLeg(new Plan.Leg("stuck", 1, 180, 0, 1, 0), 470);
        check(!stuck.ok() && stuck.failure().contains("stops you"), "a 1 kn paddler can't beat a 2 kn head stream");
        Navigator.LegRun late = nav.runLeg(p.legs().get(0), 1015);
        check(!late.ok() && late.failure().contains("end of the current table"), "running past the table is reported");
        Navigator.LegRun offset = nav.runLeg(new Plan.Leg("shifted", 1, 0, 60, 1, 0), 300);
        check(offset.ok() || offset.failure().contains("table"), "offset legs look up the reference at t - offset");
        near(nav.stream(new Plan.Leg("shifted", 1, 0, 60, 1, 0), 540).along(), 2, 1e-12, "an hour's offset moves the maximum an hour later");
    }

    static void planner() throws Exception {
        Plan p = PlanParser.parse(Files.readString(Path.of("examples/the-rip.txt")));
        Planner.Result r = Planner.plan(p);
        check(r.best() != null && !r.windows().isEmpty(), "the example has a good departure");
        for (Navigator.Trip t : r.trips()) {
            if (t.ok()) {
                check(t.minutes() >= r.best().minutes() - 1e-9, "best is the quickest good trip");
                check(t.maxOpposing() <= p.maxOpposing() + 1e-9 && t.maxCross() <= p.maxCross() + 1e-9, "good trips keep within limits");
            }
        }
        for (Planner.Window w : r.windows()) {
            check(w.from() <= w.to() && w.fastest() <= w.slowest(), "windows are well formed");
        }
        double legsSum = 0;
        for (Navigator.LegRun l : r.best().legs()) legsSum += l.minutes();
        near(legsSum, r.best().minutes(), 1e-6, "legs follow on without gaps");
        String report = Report.render(p, r);
        check(report.contains("Best: leave at") && report.contains("Good times to leave"), "report has the plan");
        // Impossible limits: nothing qualifies, and the report says so.
        Plan strict = PlanParser.parse(Files.readString(Path.of("examples/the-rip.txt")).replace("limit opposing 1.0", "limit opposing 0").replace("limit cross 2.0", "limit cross 0"));
        Planner.Result none = Planner.plan(strict);
        check(none.best() == null && none.windows().isEmpty(), "zero limits leave no good departure");
        check(Report.render(strict, none).contains("No departure in the window keeps within your limits"), "and says so");
        check(Report.clock(24 * 60 + 5).equals("00:05 (+1d)"), "clock shows the next day");
    }

    static void parser() throws Exception {
        Plan p = plan("leg A to B: 1.5 nm, course 359.5, offset -20, ratio 0.75, flood 45\nleg B to C: 2 nm, course 10, offset +5, ratio 1");
        check(p.legs().size() == 2, "two legs");
        near(p.legs().get(0).floodSet(), 45, 0, "a leg's own flood direction");
        near(p.legs().get(1).floodSet(), 0, 0, "otherwise the station's");
        check(p.legs().get(0).offset() == -20 && p.legs().get(1).offset() == 5, "signed offsets");
        Plan wrap = PlanParser.parse("""
                paddle 3
                window 22:00 to 02:00
                station S, flood 90
                event 21:00 slack
                event 23:30 ebb 1
                event 02:10 slack
                leg L: 1 nm, course 0, offset 0, ratio 1
                """);
        check(wrap.station().events().get(2).time() == 26 * 60 + 10, "tables run past midnight");
        check(wrap.windowEnd() == 26 * 60, "windows run past midnight");
        rejects(HEADER.replace("paddle 3\n", ""), "paddle line");
        rejects(HEADER + "leg A: 1 nm, course 0, offset 0, ratio 1\nevent 18:00 slack", "alternate between slack");
        rejects(HEADER.replace("ebb 2", "flood 2") + "leg A: 1 nm, course 0, offset 0, ratio 1", "take turns");
        rejects(HEADER, "at least one leg");
        rejects(HEADER + "leg A: 99 nm, course 0, offset 0, ratio 1", "distance must be between");
        rejects(HEADER + "leg A: 1 nm, course 400, offset 0, ratio 1", "direction must be between");
        rejects(HEADER + "leg A: 1 nm, course 0, offset 500, ratio 1", "offset must be within");
        rejects(HEADER + "leg A: 1 nm, course 0, offset 0, ratio 1\npaddle 99", "paddle speed must be between");
        rejects(HEADER + "leg A: 1 nm, course 0, offset 0, ratio 1\nwindow 25:00 to 26:00", "times are");
        rejects(HEADER + "leg A: 1 nm, course 0, offset 0, ratio 1\nhello", "lines start with");
        rejects(HEADER + "leg <script>: 1 nm, course 0, offset 0, ratio 1", "leg line isn't in the expected form");
        rejects(HEADER + "leg A: 1e3 nm, course 0, offset 0, ratio 1", "leg line");
        rejects(HEADER + "trip \u001b[31mred", "control or hidden");
        rejects(HEADER + "trip right‮left", "control or hidden");
        rejects(HEADER + "trip " + "x".repeat(300), "longer than");
        rejects("#".repeat(70_000), "larger than 64 KB");
        rejects(HEADER + "station Other, flood 10\nleg A: 1 nm, course 0, offset 0, ratio 1", "only one reference station");
        StringBuilder many = new StringBuilder(HEADER);
        for (int i = 0; i < 31; i++) many.append("leg L").append(i).append(": 1 nm, course 0, offset 0, ratio 1\n");
        rejects(many.toString(), "more than 30 legs");
        rejects(HEADER.replace("event 05:00 slack\n", "").replace("event 08:00 flood 2\n", "").replace("event 11:00 slack\n", "").replace("event 14:00 ebb 2\n", "") + "leg A: 1 nm, course 0, offset 0, ratio 1", "at least 3 events");
    }

    static void files() throws Exception {
        Path dir = Files.createTempDirectory("ferryglide");
        List<Path> made = new ArrayList<>();
        try {
            Path real = dir.resolve("plan.txt");
            Files.writeString(real, HEADER + "leg A: 1 nm, course 0, offset 0, ratio 1\n");
            made.add(real);
            check(Main.readFile(real.toString()).length > 0, "reads a plain file");
            Path link = dir.resolve("link.txt");
            Files.createSymbolicLink(link, real);
            made.add(link);
            expectIo(() -> Main.readFile(link.toString()), "symbolic link");
            expectIo(() -> Main.readFile(dir.toString()), "not a regular file");
            expectIo(() -> Main.readFile("/dev/zero"), "not a regular file");
            expectIo(() -> Main.readFile(dir.resolve("missing\u001b.txt").toString()), "missing?.txt does not exist");
            Path big = dir.resolve("big.txt");
            Files.write(big, new byte[70_000]);
            made.add(big);
            expectIo(() -> Main.readFile(big.toString()), "larger than 64 KB");
            expectIo(() -> Main.decode(new byte[] {0x70, (byte) 0xff, (byte) 0xfe}), "not valid UTF-8");
            check(Main.decode("﻿paddle".getBytes(StandardCharsets.UTF_8)).equals("paddle"), "a byte-order mark is dropped");
            check(Main.run(new String[] {real.toString()}) == 1 || Main.run(new String[] {real.toString()}) == 0, "runs on a valid plan");
            check(Main.run(new String[] {"examples/the-rip.txt"}) == 0, "exit 0 when a good departure exists");
            check(Main.run(new String[] {}) == 2 && Main.run(new String[] {"--help"}) == 2, "usage errors exit 2");
            check(Main.run(new String[] {big.toString()}) == 2, "bad input exits 2");
        } finally {
            for (Path p : made) Files.deleteIfExists(p);
            Files.deleteIfExists(dir);
        }
    }

    interface IoAction {
        void run() throws IOException;
    }

    static void expectIo(IoAction a, String fragment) {
        try {
            a.run();
            check(false, "expected an error mentioning " + fragment);
        } catch (IOException e) {
            check(e.getMessage().contains(fragment), "'" + e.getMessage() + "' should mention '" + fragment + "'");
        }
    }
}
