//! `cargo run -p usagebar_core --example reap -- --dry-run`: the same entry `usagebar reap` reaches, for
//! reconciliation runs that should not need an Xcode build.
fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut out = std::io::stdout().lock();
    std::process::exit(usagebar_core::reap::main(&args, &mut out));
}
