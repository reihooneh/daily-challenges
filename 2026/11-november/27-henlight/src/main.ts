#!/usr/bin/env node
import { run } from './cli.js';

const { out, code } = run(process.argv.slice(2));
(code === 0 ? process.stdout : process.stderr).write(`${out}\n`);
process.exitCode = code;
