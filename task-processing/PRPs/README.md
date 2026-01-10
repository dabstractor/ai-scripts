# Planning Requirements Protocols (PRPs)

PRPs are comprehensive planning documents that enable **one-pass implementation success** through systematic research and context curation.

## Directory Structure

```
PRPs/
├── README.md              # This file
├── templates/
│   └── prp_base.md        # Base template for new PRPs
├── ai_docs/               # Cached documentation for AI agents
└── XXX-feature-name.md    # Individual PRP documents
```

## PRP Naming Convention

PRPs follow the pattern: `{XXX}-{feature-name}.md`
- `XXX` = 3-digit sequential number (001, 002, etc.)
- `feature-name` = kebab-case description

## PRP Purpose

Each PRP provides:
1. **Goal** - Clear feature goal, deliverable, and success definition
2. **Context** - All references, URLs, and codebase patterns needed
3. **Implementation Tasks** - Dependency-ordered, specific actions
4. **Validation Gates** - Project-specific commands to verify success

## Key Principle

> "If someone knew nothing about this codebase, would they have everything needed to implement this successfully?"

PRPs are designed for AI implementation agents who receive only:
- The PRP content
- Training data knowledge
- Access to codebase files (but need guidance on which ones)

## Current PRPs

| ID | Name | Status | Task Reference |
|----|------|--------|----------------|
| 001 | PlatformIO Configuration | Ready | P1.M1.T1.S1 |
| 002 | Task Status Commands | Ready | - |
