# Corrupted Box Characters Test

```
┌────────────┐     ┌─────────────┐
│   Valid     │────▶│   Corrupted │
│   Box       │     │   �nput    │
└────────────┘     └────────────┘
        │                   │
        ▼                   ▼
┌────────────┐     ┌─────────────┐
│   Data      │     │   Output    │
│   Stream    │     │   Handler   │
└────────────┘     └─────────────┘
```

Another example with mixed corruption:
```
┌─────┐     ┌─────┐
│ A   │────▶│ B � │
└─────┘     └─────┘
```