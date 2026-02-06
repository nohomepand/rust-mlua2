@echo off
chdir "%~dp0"
cargo build --release
copy /B /Y "target\release\rust-mlua2.exe" "rust-mlua2.exe"
