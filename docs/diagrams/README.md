# Architecture diagrams

## `spice-cdn-architecture.excalidraw`

Platform architecture diagram (technical layers + plain-English callouts).

**Open in:**

- [Excalidraw](https://excalidraw.com) — *Open* → choose this file
- [VS Code Excalidraw extension](https://marketplace.visualstudio.com/items?itemName=pomdtr.excalidraw-editor)
- Cursor with the same extension

**Regenerate** (canonical element list lives in `scripts/generate-architecture-diagram.mjs`):

```bash
node scripts/generate-architecture-diagram.mjs
```

This writes both `architecture-checkpoint.source.json` (MCP-style elements) and `spice-cdn-architecture.excalidraw` (standard Excalidraw format).

**After editing in the Excalidraw MCP widget**, export checkpoint JSON to `architecture-checkpoint.source.json`, then either update the generator script or run:

```bash
node scripts/mcp-elements-to-excalidraw.mjs \
  docs/diagrams/architecture-checkpoint.source.json \
  docs/diagrams/spice-cdn-architecture.excalidraw
```

The converter drops MCP-only pseudo-elements (`cameraUpdate`, `restoreCheckpoint`, `delete`) and expands shape `label` fields into bound text elements.
