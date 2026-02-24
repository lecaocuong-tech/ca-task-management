# REST API Layer - TaskManager Delphi 13 Project

## Architecture Overview

The REST API layer has been added to the existing TaskManager project, allowing external clients
(Postman, Frontend SPA, Mobile app, ...) to access services through HTTP/JSON.

### Overall Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    CLIENT (Browser, Postman, cURL)       │
│                                                         │
│  POST /api/auth/login   { "username":"admin",           │
│                           "password":"admin123" }        │
└──────────────────────────┬──────────────────────────────┘
                           │ HTTP Request
                           ▼
┌─────────────────────────────────────────────────────────┐
│              THttpApiServer (Indy TIdHTTPServer)        │
│  - Listens on port 8080                                 │
│  - Each request runs on its own thread (Indy thread)    │
│  - Wrap Indy objects → IApiRequest / IApiResponse       │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    TApiRouter                            │
│  - Matches URL pattern: /api/tasks/:id                   │
│  - Extracts path params: id=42                           │
│  - Dispatches through middleware chain                   │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│              MIDDLEWARE PIPELINE (Chain of Resp.)        │
│                                                         │
│  1. TCorsMiddleware     → Add CORS headers               │
│  2. TLoggingMiddleware  → Log request/response + timing  │
│  3. TRateLimitMiddleware→ Token bucket rate limiting     │
│  4. TAuthMiddleware     → Validate Bearer token          │
│                                                         │
│  Each middleware can:                                    │
│  - Call Next() → forward to next middleware              │
│  - Write Response directly → short-circuit (e.g. 401)    │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    CONTROLLERS                           │
│                                                         │
│  TAuthController  → /api/auth/*  (login, register, ...)  │
│  TTaskController  → /api/tasks/* (CRUD tasks)            │
│  TUserController  → /api/users/* (admin management)      │
│                                                         │
│  Controllers call existing Services:                     │
│  IAuthenticationService, ITaskService, IUserService      │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│              EXISTING SERVICE LAYER                       │
│  (No need to change anything!)                            │
│                                                         │
│  AuthenticationService → UserRepository → Database       │
│  TaskService → TaskRepository → Database                 │
│  UserService → UserRepository → Database                 │
└─────────────────────────────────────────────────────────┘
```

## Directory Structure (Clean Architecture)

```
src/API/
├── Contracts/                  # ◆ Interface declarations (DIP - Dependency Inversion)
│   └── ApiInterfaces.pas       #   IApiRequest, IApiResponse, IApiMiddleware, IApiRouter,
│                               #   ITokenManager, IApiServer, TRouteHandler, TTokenInfo
│
├── Server/                     # ◆ HTTP Infrastructure (Indy wrapper, routing engine)
│   ├── HttpServer.pas          #   TApiRequest, TApiResponse, THttpApiServer
│   └── ApiRouter.pas           #   TApiRouter - URL pattern matching + middleware chain
│
├── Middleware/                  # ◆ Cross-cutting concerns (Chain of Responsibility)
│   ├── ApiMiddleware.pas       #   TCorsMiddleware, TRateLimitMiddleware,
│   │                           #   TAuthMiddleware, TLoggingMiddleware
│   └── ApiSecurityBridge.pas   #   TApiSecurityBridge - bridges API token → ISecurityContext
│
├── Auth/                       # ◆ Authentication infrastructure
│   └── TokenManager.pas        #   TTokenManager - GUID-based session tokens (thread-safe)
│
├── Controllers/                # ◆ Request handlers (thin → delegate to services)
│   ├── AuthController.pas      #   POST login/register/logout, GET me
│   ├── TaskController.pas      #   GET/POST/PUT/DELETE tasks, PATCH status
│   └── UserController.pas      #   Admin user management CRUD
│
├── Serialization/              # ◆ JSON serialization/deserialization
│   └── JsonHelper.pas          #   TJsonHelper - Domain ↔ JSON conversion utilities
│
└── Startup/                    # ◆ Composition Root (wires everything together)
    └── ApiServer.pas           #   TApiServerManager - DI wiring, lifecycle management
```

### Design Principles (SOLID)

| Directory        | SOLID Principle       | Purpose                                    |
|------------------|-----------------------|--------------------------------------------|
| `Contracts/`     | **D** - Dependency Inversion | All depend on abstraction, not concrete |
| `Server/`        | **S** - Single Responsibility | Only handles HTTP infrastructure (Indy, routing)   |
| `Middleware/`    | **O** - Open/Closed          | Add new middleware without modifying old code     |
| `Auth/`          | **S** - Single Responsibility | Only handles token authentication          |
| `Controllers/`   | **S** - Single Responsibility | Each controller handles 1 resource         |
| `Serialization/` | **S** - Single Responsibility | Only handles Domain ↔ JSON conversion              |
| `Startup/`       | **S** - Single Responsibility | Only handles DI wiring and lifecycle                 |

## Important REST Concepts

### 1. HTTP Methods (REST Verbs)

| Method   | Purpose          | Example                  | Idempotent? |
|----------|------------------|--------------------------|-------------|
| `GET`    | Read data        | `GET /api/tasks`         | ✅ Yes      |
| `POST`   | Create new       | `POST /api/tasks`        | ❌ No       |
| `PUT`    | Update entirely  | `PUT /api/tasks/5`       | ✅ Yes      |
| `DELETE` | Delete           | `DELETE /api/tasks/5`    | ✅ Yes      |
| `PATCH`  | Partial update   | `PATCH /api/tasks/5/status` | ❌ No       |

### 2. HTTP Status Codes

| Code  | Meaning              | When to Use                      |
|-------|----------------------|----------------------------------|
| `200` | OK                   | Request succeeded                |
| `201` | Created              | New resource created successfully |
| `204` | No Content           | Success, no body (CORS)  |
| `400` | Bad Request          | Invalid input data    |
| `401` | Unauthorized         | Not authenticated / token expired    |
| `403` | Forbidden            | No permission (e.g. not Admin) |
| `404` | Not Found            | Resource does not exist            |
| `429` | Too Many Requests    | Exceeded rate limit               |
| `500` | Internal Server Error| Unidentified server error         |

### 3. Authentication Flow (Bearer Token)

```
1. Client sends credentials:
   POST /api/auth/login
   Body: { "username": "admin", "password": "admin123" }

2. Server returns token:
   {
     "success": true,
     "data": {
       "token": "GUID-BASED-TOKEN-STRING",
       "tokenType": "Bearer",
       "expiresAt": "2026-02-13T15:30:00.000Z"
     }
   }

3. Client includes token in all subsequent requests:
   GET /api/tasks
   Headers:
     Authorization: Bearer GUID-BASED-TOKEN-STRING

4. Server validates token via TAuthMiddleware:
   - Find token in TTokenManager (in-memory dictionary)
   - Check if expired
   - Set context values (userId, username, role)
   - If invalid → return 401
```

### 4. Middleware Pipeline (Chain of Responsibility)

```
Each middleware receives 3 parameters: (Request, Response, Next)

Request arrives → [CORS] → [Logging] → [RateLimit] → [Auth] → [Controller]
                    │          │           │            │
                    │          │           │            └─ Token invalid?
                    │          │           │               → 401, STOP
                    │          │           └─ Over rate limit?
                    │          │               → 429, STOP
                    │          └─ Log: "GET /api/tasks [127.0.0.1]"
                    └─ Add headers: Access-Control-Allow-Origin: *

If middleware does NOT call Next() → request is blocked (short-circuit)
If middleware CALLS Next() → forward to next middleware/handler
```

### 5. URL Routing with Path Parameters

```pascal
// Register route with pattern
Router.AddRoute(hmGET, '/api/tasks/:id', HandleGetTaskById);

// When request arrives: GET /api/tasks/42
// Router matches pattern, extracts: id = "42"
// Controller retrieves: ARequest.GetContextValue('path:id') → "42"
```

## API Endpoints

### Health Check
```
GET /api/health
→ 200 { "success": true, "data": { "status": "healthy", "version": "1.0.0" } }
```

### Authentication

#### Login
```
POST /api/auth/login
Content-Type: application/json

{ "username": "admin", "password": "admin123" }

→ 200 {
    "success": true,
    "data": {
      "token": "ABC-DEF-GHI-...",
      "tokenType": "Bearer",
      "username": "admin",
      "role": "Admin",
      "expiresAt": "2026-02-13T15:30:00.000Z"
    }
  }

→ 401 { "success": false, "error": { "code": 401, "message": "Invalid credentials" } }
```

#### Register
```
POST /api/auth/register
Content-Type: application/json

{ "username": "newuser", "password": "pass123456" }

→ 201 {
    "success": true,
    "data": { "id": 3, "username": "newuser", "role": "User", ... }
  }
```

#### Get Current User
```
GET /api/auth/me
Authorization: Bearer <token>

→ 200 {
    "success": true,
    "data": { "userId": 1, "username": "admin", "role": "Admin" }
  }
```

#### Logout
```
POST /api/auth/logout
Authorization: Bearer <token>

→ 200 { "success": true, "data": { "message": "Logged out successfully" } }
```

### Tasks

#### List Tasks
```
GET /api/tasks
Authorization: Bearer <token>

Query params:
  ?status=Pending|InProgress|Done   (filter)
  ?page=1&pageSize=10               (pagination)
  ?all=true                         (admin: all tasks)

→ 200 {
    "success": true,
    "data": [
      { "id": 1, "userId": 1, "title": "...", "status": "Pending", ... },
      { "id": 2, "userId": 1, "title": "...", "status": "Done", ... }
    ]
  }
```

#### Get Task by ID
```
GET /api/tasks/5
Authorization: Bearer <token>

→ 200 { "success": true, "data": { "id": 5, "title": "...", ... } }
→ 404 { "success": false, "error": { "code": 404, "message": "Task not found" } }
```

#### Create Task
```
POST /api/tasks
Authorization: Bearer <token>
Content-Type: application/json

{ "title": "Buy groceries", "description": "Milk, eggs, bread" }

→ 201 { "success": true, "data": { "id": 6, "title": "Buy groceries", ... } }
```

#### Update Task
```
PUT /api/tasks/5
Authorization: Bearer <token>
Content-Type: application/json

{ "title": "Updated title", "description": "Updated desc" }

→ 200 { "success": true, "data": { "id": 5, "title": "Updated title", ... } }
```

#### Delete Task
```
DELETE /api/tasks/5
Authorization: Bearer <token>

→ 200 { "success": true, "data": { "message": "Task 5 deleted successfully" } }
```

#### Change Task Status
```
PATCH /api/tasks/5/status
Authorization: Bearer <token>
Content-Type: application/json

{ "status": "InProgress" }

→ 200 { "success": true, "data": { "message": "Status updated", "newStatus": "InProgress" } }
```

### Users (Admin Only)

#### List Users
```
GET /api/users
Authorization: Bearer <admin-token>

→ 200 { "success": true, "data": [...] }
→ 403 { "success": false, "error": { "code": 403, "message": "Admin role required" } }
```

#### Create User
```
POST /api/users
Authorization: Bearer <admin-token>
Content-Type: application/json

{ "username": "john", "password": "pass123456", "role": "User" }

→ 201 { "success": true, "data": { "id": 4, "username": "john", ... } }
```

#### Update User  
```
PUT /api/users/4
Authorization: Bearer <admin-token>
Content-Type: application/json

{ "password": "newpassword", "role": "Admin" }

→ 200 { "success": true, "data": { "message": "User 4 updated" } }
```

#### Delete User
```
DELETE /api/users/4
Authorization: Bearer <admin-token>

→ 200 { "success": true, "data": { "message": "User 4 deleted" } }
```

## Test with cURL

```bash
# 1. Health check
curl http://localhost:8080/api/health

# 2. Login
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}'

# 3. Get token from response, save to variable
TOKEN="paste-token-here"

# 4. Get current user info
curl http://localhost:8080/api/auth/me \
  -H "Authorization: Bearer $TOKEN"

# 5. Create new task
curl -X POST http://localhost:8080/api/tasks \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"title":"Learn REST API","description":"Study HTTP methods and status codes"}'

# 6. Get task list
curl http://localhost:8080/api/tasks \
  -H "Authorization: Bearer $TOKEN"

# 7. Update status
curl -X PATCH http://localhost:8080/api/tasks/1/status \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"status":"InProgress"}'

# 8. Delete task
curl -X DELETE http://localhost:8080/api/tasks/1 \
  -H "Authorization: Bearer $TOKEN"

# 9. Logout
curl -X POST http://localhost:8080/api/auth/logout \
  -H "Authorization: Bearer $TOKEN"
```

## Test with PowerShell

```powershell
# 1. Health check
Invoke-RestMethod -Uri "http://localhost:8080/api/health"

# 2. Login
$loginBody = @{ username = "admin"; password = "admin123" } | ConvertTo-Json
$loginResp = Invoke-RestMethod -Uri "http://localhost:8080/api/auth/login" `
  -Method POST -Body $loginBody -ContentType "application/json"
$token = $loginResp.data.token

# 3. Headers for authenticated requests
$headers = @{ Authorization = "Bearer $token" }

# 4. Get tasks
Invoke-RestMethod -Uri "http://localhost:8080/api/tasks" -Headers $headers

# 5. Create task
$taskBody = @{ title = "Learn Delphi REST"; description = "Study API patterns" } | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:8080/api/tasks" `
  -Method POST -Body $taskBody -ContentType "application/json" -Headers $headers

# 6. Filter tasks by status
Invoke-RestMethod -Uri "http://localhost:8080/api/tasks?status=Pending" -Headers $headers

# 7. Pagination
Invoke-RestMethod -Uri "http://localhost:8080/api/tasks?page=1&pageSize=5" -Headers $headers
```

## Technical Explanation

### Why use Indy (TIdHTTPServer)?

1. **Comes with Delphi** - No need to install additional packages
2. **Multi-threaded** - Each request runs on its own thread, automatically
3. **Cross-platform** - Runs on Windows, Linux, macOS
4. **Battle-tested** - Used in thousands of Delphi projects

### Token vs JWT

| Criteria         | Session Token (used here) | JWT                          |
|------------------|---------------------------|------------------------------|
| Storage         | Server-side (in-memory)   | Client-side (self-contained) |
| Validation       | Lookup dictionary O(1)    | Verify signature             |
| Revocation       | Delete from dictionary    | Difficult (needs blacklist)   |
| Scalability      | Single server             | Multi-server (stateless)     |
| Complexity       | Simple                    | Requires crypto library      |

For learning purposes, Session Token is simpler and more intuitive.

### Dependency Inversion in API Layer

```
ApiServer (Composition Root)
  ├── depends on → IServiceContainer (abstraction)
  ├── depends on → IApiRouter (abstraction)
  ├── depends on → ITokenManager (abstraction)
  └── does NOT depend on → Database, Repository (details)

Controllers
  ├── depend on → ITaskService, IUserService (abstractions)
  └── do NOT depend on → TaskRepository, DatabaseManager (details)
```

### Thread Safety

```
Indy Thread 1 ─────────┐
                        ├──→ Router (read-only after startup) ──→ Controller ──→ Service
Indy Thread 2 ─────────┤    
                        │    TokenManager (TCriticalSection)
Indy Thread 3 ─────────┘    DatabaseManager (thread-safe SQLite)
```

- Router: routes registered at startup, read-only during dispatch
- TokenManager: protected by TCriticalSection
- Services/Repositories: use existing thread-safety mechanisms
