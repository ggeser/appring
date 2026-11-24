# Experiments

Prototypes kept for what they showed, not maintained, and not part of
`just check`. Each folder has its own `flake.nix` and notes.

| Folder | What it tried | Result |
|---|---|---|
| [rust-ui/](rust-ui/) | The ring as a native Rust app: iced, cxx-qt (QML), egui, and egui on a real layer-shell surface | iced did not build; cxx-qt worked but could only centre on the monitor; plain egui could not position itself on Wayland; egui on layer-shell worked, centred on the cursor. Numbers and notes: [rust-ui/RESULTS.md](rust-ui/RESULTS.md) |

These are Linux/Wayland only, like the ring today.
