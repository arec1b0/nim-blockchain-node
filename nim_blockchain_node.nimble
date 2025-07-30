# nim_blockchain_node.nimble

version       = "0.1.0"
author        = "arec1b0"
description   = "A high-performance blockchain node implementation in Nim"
license       = "MIT"
srcDir        = "src"
bin           = @["main", "blockchain_cli"]

# Dependencies
requires "nim >= 2.2.2"

task build, "Compile blockchain node executable":
  exec "nim c -d:release src/main.nim"

task cli, "Compile CLI executable":
  exec "nim c -d:release src/blockchain_cli.nim"

task buildAll, "Compile all executables":
  exec "nim c -d:release src/main.nim"
  exec "nim c -d:release src/blockchain_cli.nim"

task test, "Run all tests":
  exec "nim c -r tests/unit_tests/core_engine_tests.nim"
  exec "nim c -r tests/unit_tests/cryptography_tests.nim"
  exec "nim c -r tests/unit_tests/network_tests.nim"
  exec "nim c -r tests/unit_tests/storage_tests.nim"
  exec "nim c -r tests/unit_tests/cli_tests.nim"
  exec "nim c -r tests/integration_tests/node_integration_tests.nim"
