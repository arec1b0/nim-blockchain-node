## One-time std/logging setup for composition roots.
## Diagnostics go to stderr. Command results (help text, JSON, human-readable
## CLI output) stay on stdout and are not written here.
## Do not log private keys, signatures, seeds, or keystore file bodies.

import std/logging

var ready = false

proc configureLogging*(verbose: bool) =
  ## Call once from `main` or `runCLI`. A later call does not change the level.
  if ready:
    return
  let threshold = if verbose: lvlDebug else: lvlInfo
  setLogFilter(threshold)
  addHandler(newConsoleLogger(
    levelThreshold = threshold,
    fmtStr = "$levelname: $message",
    useStderr = true
  ))
  ready = true
