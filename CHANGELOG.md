# Changelog

## 0.4.1 (unreleased)

- Use VERSION as the packaged version source and verify fresh-host installation.
- Add maintainer quality commands and pin the development toolchain.
- Add `XLSXComposer.to_workbook/1` and `XLSXComposer.write/2`.
- Add HexDocs guides (overview, components, a tested example, comparison with Elixlsx) and ship them in the package.
- Remove the placeholder `example` function from `XLSXComposer` (breaking: it only returned `:ok`).
- Fix `XLSXComposer.Section.below/2`, `XLSXComposer.Section.to_the_right/2`, `XLSXComposer.Section.move_y_just_below/1` and `XLSXComposer.Section.move_x_just_right/1` for one-cell sections, which were treated as empty (breaking: a section with no cells now counts as empty whatever its corners).
