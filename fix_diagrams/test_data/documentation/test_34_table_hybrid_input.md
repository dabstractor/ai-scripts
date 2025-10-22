# Table Hybrid Test

Here's a regular table:

| Column 1 | Column 2 |
|----------|----------|
| Value A  | Value B  |

And here's a diagram:

```
┌─────────────┐     ┌─────────────┐
│   Service   │────▶│   Service   │
│     A       │     │     B       │
└─────────────┘     └─────────────┘
```

Back to table:

| Service | Status |
|---------|--------|
| A       | Active |
| B       | Pending |
```