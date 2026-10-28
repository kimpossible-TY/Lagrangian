#!/usr/bin/env node
// Supported executable; terminal responsibilities live in terminal/.
import { main } from "./terminal/cli.mjs";

main().catch((error) => {
  process.stderr.write(`Lagrangian Reader: ${error.message}\n`);
  process.exitCode = 1;
});
