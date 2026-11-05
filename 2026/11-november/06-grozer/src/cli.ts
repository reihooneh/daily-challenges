#!/usr/bin/env node
import { closeSync, constants, fstatSync, openSync, readSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { InputError, MAX_INPUT, parse } from "./parse.js";
import { analyse, render, svg } from "./report.js";

const USAGE =
  "usage: grozer [--svg] <design.txt>   (or - to read standard input)\n" +
  "Finds the pieces of a stained-glass design that can't be cut, and the fewest lead lines that fix them.\n" +
  "--svg prints a drawing of the panel with the suggested lead lines instead of the report.\n";

const UNREADABLE = "the design file could not be read (it must be a regular file, not a link)";

/** Reads at most MAX_INPUT + 1 bytes from a regular file (never through a link) or standard input. */
export function readBounded(path: string): string {
  let fd: number;
  try {
    fd = path === "-" ? 0 : openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  } catch {
    throw new InputError(0, UNREADABLE);
  }
  try {
    if (path !== "-" && !fstatSync(fd).isFile()) throw new InputError(0, UNREADABLE);
    const buf = Buffer.alloc(MAX_INPUT + 1);
    let used = 0;
    for (;;) {
      let n = 0;
      try {
        n = readSync(fd, buf, used, buf.length - used, null);
      } catch (e) {
        if ((e as NodeJS.ErrnoException).code === "EAGAIN") continue;
        throw new InputError(0, UNREADABLE);
      }
      if (n === 0) break;
      used += n;
      if (used >= buf.length) break;
    }
    if (used > MAX_INPUT) throw new InputError(0, "the design file is larger than 64 KB");
    try {
      return new TextDecoder("utf-8", { fatal: true }).decode(buf.subarray(0, used));
    } catch {
      throw new InputError(0, "the design file is not valid UTF-8 text");
    }
  } finally {
    if (path !== "-") closeSync(fd);
  }
}

/** The whole command. Exit codes: 0 every piece can be cut as drawn, 1 some can't, 2 bad usage or input. */
export function main(args: string[], write: (s: string) => void, warn: (s: string) => void, read = readBounded): number {
  const drawing = args[0] === "--svg";
  const rest = drawing ? args.slice(1) : args;
  if (rest.length !== 1 || rest[0]!.startsWith("--") || rest[0] === "-h") {
    warn(USAGE);
    return 2;
  }
  try {
    const design = parse(read(rest[0]!));
    const results = analyse(design);
    write(drawing ? svg(design, results) : render(design, results));
    return results.every((r) => r.fix === null) ? 0 : 1;
  } catch (e) {
    if (e instanceof InputError) {
      warn(`grozer: ${e.message}\n`);
      return 2;
    }
    throw e;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = main(
    process.argv.slice(2),
    (s) => process.stdout.write(s),
    (s) => process.stderr.write(s),
  );
}
