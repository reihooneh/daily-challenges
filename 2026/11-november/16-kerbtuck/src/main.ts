#!/usr/bin/env node
// The command-line entry point.
import { run } from './cli.js';

process.exitCode = run(process.argv.slice(2), (s) => console.log(s), (s) => console.error(s));
