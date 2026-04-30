# AGENTS.md

## Preset Agent Logos

- Preset Agent icons must use SVG assets sourced from LobeHub Icons (`@lobehub/icons`).
- Use LobeHub mono assets consistently so preset Agent icons stay visually coordinated. Export the brand `Mono` component as a plain SVG path with `fill="#111111"` and no background shape.
- Keep logo SVG files in `Sources/Resources/AgentLogos/` and name them after the `BuiltInAgent.logoName` value.
- Do not mix icon sources for preset Agents. If LobeHub does not have a needed logo, add a temporary SF Symbols fallback through `iconName` and document the missing LobeHub asset in the change.
- When adding a preset Agent, update `BuiltInAgent` in `Sources/Models/Agent.swift` with `displayName`, `iconName`, `logoName`, and `skillsDirectoryName`.
- The SwiftPM resource bundle may flatten processed SVG files to the bundle root. Keep `AgentLogoLoader` able to load both `AgentLogos/<name>.svg` and `<name>.svg`.
- `AgentLogo` inverts SVG logos in dark mode, so new preset SVGs should remain single-color dark glyphs.
