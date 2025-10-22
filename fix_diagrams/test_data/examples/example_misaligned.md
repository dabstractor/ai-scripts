# Misaligned Diagram Example

Here's an example of a diagram with misaligned boxes that commonly occurs when AI generates ASCII diagrams:

## System Architecture
```
┌─────────────────┐     ┌─────────────────┐
│   Frontend      │────▶│    API Gateway  │
│   React App     │     │   Load Balancer │
└─────────────────┘     └────────────────────┘
         │                        │
         ▼                        ▼
┌─────────────────┐     ┌──────────────────┐
│   User Cache    │     │   Auth Service   │
│     Redis       │     │   OAuth/JWT      │
└────────────────────┘     └──────────────────┘
```

## Data Flow
```
┌──────────────┐     ┌─────────────────┐     ┌───────────────┐
│   Client     │────▶│   Web Server    │────▶│  Database     │
│   Browser    │     │   Express.js    │     │  PostgreSQL   │
└──────────────┘     └─────────────────┘     └────────────────┘
         ▲                        │                        ▲
         │                        ▼                        │
┌──────────────┐     ┌─────────────────┐     ┌───────────────┐
│   Local      │◀────│   Static Files  │◀────│   Backup      │
│   Storage    │     │   CDN           │     │   Service     │
└─────────────────┘     └─────────────────┘     └───────────────┘
```

## Alternate Data Flow
```
                     ┌─────────────────┐    
┌──────────────┐     │   Web Server    │     ┌───────────────┐
│   Client     │────▶│   Express.js    │────▶│  Database     │
│   Browser    │     │     Graph       │     │  PostgreSQL   │
└──────────────┘     │     REST         │    └────────────────┘
                     └────────────────┘
         ▲                        │                        ▲
         │                        ▼                        │
┌──────────────┐     ┌─────────────────┐     ┌───────────────┐
│   Local      │◀────│   Static Files  │◀────│   Backup      │
│   Storage    │     │   CDN           │     │   Service     │
└─────────────────┘     └─────────────────┘     └───────────────┘
```

## Microservices
```
┌─────────────────────┐
│   Service A         │
│   User Management   │
└─────────────────┘

┌─────────────────────┐     ┌─────────────────────┐
│   Service B         │────▶│   Service C         │
│   Payment Processing│     │   Notification      │
└─────────────────────────┘     └──────────────────────┘
         │                                 │
         ▼                                 ▼
┌─────────────────────┐     ┌─────────────────────┐
│   Service D         │     │   Service E         │
│   Analytics         │     │   File Storage      │
└────────────────────────────┘     └─────────────────────┘
```

Run `python3 fix_diagram.py example_misaligned.md` to fix these misaligned boxes.
