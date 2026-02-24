# TaskManager Project Architecture (Delphi 13)

## Architecture Overview

This project is a comprehensive demonstration of **Clean Architecture** principles applied to a Delphi desktop application with REST API support. It showcases best practices including **SOLID principles**, **Domain-Driven Design (DDD)**, and modern software engineering patterns.

### 1. Core Architectural Principles

#### **Clean Architecture**
The project strictly separates concerns into independent layers with clear dependency flows:

- **Direction of Dependencies**: All dependencies point toward the center (Domain Layer)
- **Independence**: Each layer can be tested, modified, and deployed independently
- **Replaceable**: Implementations (Repositories, Services) can be swapped without affecting business logic
- **Framework Agnostic**: Core business logic is independent of Delphi VCL, Indy HTTP, or FireDAC

#### **SOLID Principles**

| Principle | Implementation | Example |
|-----------|-----------------|---------|
| **S** - Single Responsibility | Each class has only one reason to change | `TAuthenticationService` only handles auth; `TPermissionGuard` only handles permissions |
| **O** - Open/Closed | Open for extension, closed for modification | API middleware pipeline: add new middleware without modifying existing code |
| **L** - Liskov Substitution | Derived types are substitutable for base types | All repositories implement `ITaskRepository`; controllers use interface, not concrete class |
| **I** - Interface Segregation | Many specific interfaces better than one general-purpose | `ITaskRepository`, `IUserRepository` instead of single `IRepository` |
| **D** - Dependency Inversion | Depend on abstractions, not concretions | Services depend on `IRepository`, not concrete `TTaskRepository` |

#### **Domain-Driven Design (DDD)**

- **Domain Layer Purity**: Domain models have zero external dependencies
- **Entities & Value Objects**: `TUser`/`TTask` are entities; `TPasswordCredential` is a value object
- **Domain Events**: Capture meaningful business state changes (`TTaskStatusChangedEvent`, `TUserCreatedEvent`)
- **Collect-then-Dispatch Pattern**: Domain events are collected during operations and dispatched after persistence
- **Ubiquitous Language**: Code mirrors business terminology (Status, Role, Specification)
- **Bounded Contexts**: Task management, User management, Security are separate concerns

## 2. Project Layers

| # | Layer | Directory | Purpose |
|---|-------|-----------|---------|
| 1 | **Domain Layer** (innermost) | `src/Domain/` | Entities, Value Objects, Domain Events, Specifications. No dependencies — pure business rules |
| 2 | **Interfaces Layer** (abstractions) | `src/Interfaces/` | Declares all contracts (19 interfaces). All layers depend on this instead of concrete implementations |
| 3 | **Application Layer** | `src/UseCases/` | Orchestrates workflows, DTOs, input validation/sanitization, domain event dispatch |
| 4 | **Business Logic Layer** | `src/Services/` | Enforces business rules, permission checks, authentication, password hashing |
| 5 | **Infrastructure Layer** | `src/Infrastructure/` | Persistence (SQLite/FireDAC), caching (in-memory TTL), event dispatching, data seeding |
| 6 | **Presentation Layer** | `src/UI/` + `src/API/` | UI: VCL Windows forms. API: REST endpoints with Indy HTTP server, middleware pipeline |
| 7 | **Cross-Cutting Concerns** | `src/Common/`, `src/Core/`, `src/Security/`, `src/Threading/`, `src/DependencyInjection/` | Logger, Result monad, SecurityContext, input sanitizer, rate limiter, background jobs, DI container |

---

## 3. Main Call Flow

```
User Click (UI)  /  HTTP Request (API)
        │                    │
        ▼                    ▼
    UseCases            Controllers
   (sanitize,          (parse JSON,
    validate)           auth token)
        │                    │
        └────────┬───────────┘
                 ▼
            Services
     (business rules, permissions)
                 │
                 ▼ (qua interfaces)
          Repositories
     (SQL, FireDAC, SQLite)
                 │
                 ▼
           Database (SQLite)
```

---
## 4. Layer Dependency Diagram
```mermaid
graph TD
    subgraph Presentation["PRESENTATION LAYER"]
        UI["UI (VCL Forms)"]
        API["API(REST / Indy HTTP)"]
    end

    subgraph Application["APPLICATION LAYER"]
        UC["UseCases(Orchestrators)"]
        DTO["UseCases/DTOs(Data Transfer Objects)"]
    end

    subgraph Business["BUSINESS LOGIC LAYER"]
        SVC["Services(Task, User, Auth, Permission)"]
    end

    subgraph DomainLayer["DOMAIN LAYER (innermost)"]
        DOM["Domain(Entities, Value Objects)"]
        EVT["Domain(Domain Events)"]
        SPEC["Domain(Specifications)"]
    end

    subgraph Infra["INFRASTRUCTURE LAYER"]
        REPO["Infrastructure(Repositories)"]
        DB["Infrastructure(DatabaseManager)"]
        CACHE["Infrastructure(CacheManager)"]
        EVTD["Infrastructure(EventDispatcher)"]
        SEED["Infrastructure(DataSeeder)"]
    end

    subgraph CrossCutting["CROSS-CUTTING"]
        IFACE["Interfaces(AppInterfaces / InfraInterfaces)"]
        COMMON["Common(Result, Logger)"]
        CORE["Core(SecurityContext)"]
        SEC["Security(Sanitizer, RateLimiter)"]
        THR["Threading(BackgroundJobs, JobManager)"]
        DI["DependencyInjection(ServiceContainer)"]
    end

    UI -->|"calls"| UC
    UI -->|"uses"| IFACE
    API -->|"calls"| SVC
    API -->|"uses"| IFACE

    UC -->|"calls"| SVC
    UC -->|"uses"| SEC
    UC -->|"uses"| EVTD

    SVC -->|"depends on"| IFACE

    IFACE -->|"references"| DOM
    IFACE -->|"references"| COMMON

    REPO -->|"implements"| IFACE
    REPO -->|"uses"| DB
    REPO -->|"uses"| DOM

    CACHE -->|"implements"| IFACE
    EVTD -->|"implements"| IFACE
    SEED -->|"implements"| IFACE

    THR -->|"calls"| SVC
    DI -->|"wires ALL"| Infra
    DI -->|"wires ALL"| Business
    DI -->|"wires ALL"| CrossCutting

    CORE -->|"uses"| IFACE
    SEC -->|"uses"| IFACE

    style DomainLayer fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style Presentation fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
    style Application fill:#fff3e0,stroke:#e65100,stroke-width:2px
    style Business fill:#fce4ec,stroke:#c62828,stroke-width:2px
    style Infra fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px
    style CrossCutting fill:#fffde7,stroke:#f9a825,stroke-width:2px

```
