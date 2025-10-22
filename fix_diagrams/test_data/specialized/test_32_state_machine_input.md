# State Machine Diagram Test

```
┌──────────┐     ┌──────────┐
│  Idle    │────▶│ Running  │
│  State   │     │  State   │
└──────────┘     └──────────┘
  │     ▲           │     ▲
  ▼     │           ▼     │
┌──────────┐     ┌──────────┐
│  Error   │────▶│ Paused   │
│  State   │     │  State   │
└──────────┘     └──────────┘
```