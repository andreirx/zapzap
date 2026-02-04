# ZapZap Native — Build Sequence
#
# The critical dependency chain:
#   Rust source → wasm-pack → pkg/ → npm install → Vite
#
# If you change ANY Rust code, you MUST run `make wasm` before
# the browser will see the changes. Vite only serves the JS/WASM
# from pkg/, it does NOT rebuild Rust automatically.

.PHONY: all wasm install dev build test check clean

# Default: rebuild everything and start dev server
all: wasm install dev

# ---- Step 1: Compile Rust → WASM ----
# This produces crates/zapzap/pkg/ with .wasm + JS glue + .d.ts
wasm:
	wasm-pack build crates/zapzap --target web

# ---- Step 2: Link WASM package into node_modules ----
# package.json has "zapzap-sim": "file:crates/zapzap/pkg"
# npm install creates the symlink/copy so Vite can resolve it
install:
	npm install

# ---- Step 3: Start Vite dev server ----
dev:
	npm run dev

# ---- Production build ----
build: wasm install
	npm run build

# ---- Tests ----
# Run all verification checks
test: test-rust test-wasm test-ts

# Rust unit tests (native, no WASM)
test-rust:
	cargo test -p zapzap-sim

# Verify WASM target compiles (fast, no wasm-pack overhead)
test-wasm:
	cargo check --target wasm32-unknown-unknown -p zapzap-sim

# TypeScript type check
test-ts:
	npx tsc --noEmit

# ---- Convenience ----
# Rebuild WASM + reinstall + run all checks
rebuild: wasm install test

# Clean build artifacts
clean:
	cargo clean
	rm -rf crates/zapzap/pkg
	rm -rf node_modules
	rm -rf dist
