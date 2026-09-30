# Appearance & themes

NetCrux uses the shared theme engine that runs across the EDACrux suite, so a palette you settle on in one app looks the same in the next. Everything on this page lives in one place: open **Settings** (++cmd+comma++ / ++ctrl+comma++) and select the **Appearance** category. Appearance also holds the app's **Language** picker (English, 中文, 日本語, 한국어).

## Light or dark {#mode}

There is no separate light/dark setting: brightness follows the active color preset. Pick **Crux Light** for a light interface and any of the other presets for a dark one. **View → Toggle Theme** (++cmd+shift+k++ / ++ctrl+shift+k++) flips between the two built-in presets: from any dark preset it activates Crux Light, and from Crux Light it activates Crux Dark. Like choosing a preset, it replaces any per-token color overrides. When the operating system reports that its *increase contrast* accessibility setting is on, NetCrux also hardens its borders to fully opaque outlines.

## Color theme presets {#presets}

Under **Presets**, the preset picker selects the palette itself. NetCrux ships six built-ins.

| Preset | Brightness |
|---|---|
| Crux Dark *(default)* | Dark |
| Crux Light | Light |
| Solarized Dark | Dark |
| High Contrast Dark | Dark |
| Oscilloscope | Dark |
| OLED XR | Dark |

## Per-token color overrides {#overrides}

On top of the active preset you can override individual colors, token by token, under **Color overrides**. The overrides are grouped into a single category, **Application chrome**, holding 14 tokens:

- Scaffold background
- Panel background
- Panel header background
- Panel header foreground
- Toolbar background
- Toolbar icon
- Toolbar icon (active)
- Status bar background
- Status bar foreground
- Splitter
- Splitter (hover)
- Tab bar background
- Tab bar (selected)
- Tab bar label

!!! note "Scope of per-token theming"

    Per-token theming covers application chrome only. The schematic canvas does not expose its own theme tokens, so canvas colors follow the active preset and cannot be overridden individually.

## Theme packs {#packs}

A complete theme travels as a `.crux-theme.json` file — a **theme pack**. The **Theme packs** browser in `Settings → Appearance` imports packs and exports the current theme. Imported packs are installed into the `themes` directory inside NetCrux's application-support folder, and the default export file name is `netcrux-theme.crux-theme.json`.

Your active preset and any token overrides persist across launches.

!!! note "Next steps"

    For what each themed surface is called, see [The interface](interface.md). For key bindings, see [Keyboard & mouse reference](keyboard-mouse.md).
