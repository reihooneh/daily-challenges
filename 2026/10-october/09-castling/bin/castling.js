#!/usr/bin/env node
import { main } from '../src/cli.js';

process.exitCode = main(process.argv.slice(2), {
  out: (s) => process.stdout.write(s),
  err: (s) => process.stderr.write(s),
});
