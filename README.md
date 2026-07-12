# login-demo

A tiny two-service app for practicing the CI/CD → ECR → ECS/Fargate pipeline.

- **frontend/** — React + Vite + TypeScript. A login form; shows "logged in as X".
- **backend/** — NestJS + TypeScript. In-memory login, session via an httpOnly cookie.

The two are **separate services** but share **one origin** (nginx proxies `/api/*`
to the backend), so the session-cookie login works without any CORS setup.

```
login-demo/
├── docker-compose.yml        # run both together locally (one origin)
├── .gitignore
├── backend/                  # NestJS API  (image #1 -> ECR)
│   ├── Dockerfile            # multi-stage, non-root
│   ├── .dockerignore
│   ├── package.json
│   ├── tsconfig.json
│   ├── nest-cli.json
│   └── src/
│       ├── main.ts           # bootstrap + session middleware + /api prefix
│       ├── session.d.ts      # types req.session.user
│       ├── app.module.ts
│       └── auth/
│           ├── auth.module.ts
│           ├── auth.controller.ts   # POST /api/auth/login | GET /me | POST /logout
│           └── auth.service.ts      # in-memory user store (demo / password123)
└── frontend/                 # React SPA  (image #2 -> ECR)
    ├── Dockerfile            # build with node, serve with nginx
    ├── .dockerignore
    ├── nginx.conf            # serves static + proxies /api -> backend
    ├── package.json
    ├── tsconfig.json
    ├── vite.config.ts        # dev proxy /api -> localhost:3000
    ├── index.html
    └── src/
        ├── main.tsx
        ├── api.ts            # fetch helpers (credentials: 'include')
        └── App.tsx           # the login UI
```

## Run it

### Option A — Docker (closest to production, one origin)
```bash
docker compose up --build
# open http://localhost:8080   (log in with demo / password123)
```

### Option B — bare metal (two terminals, Vite dev-proxies /api)
```bash
# terminal 1
cd backend  && npm install && npm run start:dev     # :3000
# terminal 2
cd frontend && npm install && npm run dev           # http://localhost:5173
```

## Endpoints
- `POST /api/auth/login`  `{ "username": "demo", "password": "password123" }`
- `GET  /api/auth/me`     → `{ "user": { "username": "demo" } | null }`
- `POST /api/auth/logout`

## Caveats (deliberate, for later lessons)
- **Memory-only users + sessions**: reset on restart and are **not shared across
  replicas**. Deploy with `DesiredCount: 1`; "shared state needs a real store
  (Postgres/Redis)" is the next lesson.
- **Plaintext password compare**: real apps hash (bcrypt/argon2). Out of scope here.
- **nginx runs as root**: fine for now; harden to nginx-unprivileged later.
- **`npm install` in Dockerfiles**: switch to `npm ci` once a `package-lock.json`
  is committed (run `npm install` locally once to generate it).

## How this maps to the pipeline (delivery-fluency-summary.md)
- **Stage 1** — these two apps + their Dockerfiles.  ← you are here
- **Stage 2** — GitHub Actions: lint/typecheck → build → scout → push (per service, path-filtered).
- **Stage 3** — push both images to **ECR**.
- **Stage 4** — ECS/Fargate behind an ALB; ALB routes `/api/*` → backend, `/` → frontend
  (replacing nginx's proxy role from local dev).

## Commit convention

This repo follows [**Conventional Commits**](https://www.conventionalcommits.org).
Format:

```
<type>(<scope>): <short description>

[optional body]
[optional footer]
```

- **description**: imperative, lowercase, no trailing period
  ("add logout endpoint", not "Added logout endpoint.").
- Completes the sentence *"If applied, this commit will ___."*

### Types

| type | when |
|---|---|
| `feat` | a new feature |
| `fix` | a bug fix |
| `refactor` | code change that neither fixes a bug nor adds a feature |
| `build` | build system / Dockerfile / dependencies |
| `ci` | CI / pipeline (GitHub Actions) changes |
| `chore` | tooling / config, no app-logic change |
| `docs` | documentation only |
| `test` | adding or adjusting tests |
| `style` | formatting only (whitespace, semicolons) |
| `perf` | performance improvement |

### Scopes (this monorepo)

Use the scope to mark **which part** of the repo the commit touches — matches the
folder names (and the path-filtered CI):

- `backend`  — the NestJS API
- `frontend` — the React SPA
- `repo`     — root / cross-cutting (docker-compose, root gitignore, README, monorepo tooling)

Pick one spelling and stay consistent (full words, matching the folders).

### Examples

```
chore(repo): initialize login-demo monorepo
feat(backend): add in-memory session login endpoints
feat(frontend): add login form and session state
fix(backend): use default import for express-session
build(backend): add multi-stage non-root Dockerfile
build(frontend): add nginx-based Dockerfile with /api proxy
chore(repo): add docker-compose for local one-origin dev
ci(backend): add build-and-push workflow
docs(repo): document run instructions and caveats
```

### Notes

- **Breaking changes**: add `!` after the scope, or a `BREAKING CHANGE:` footer —
  e.g. `feat(backend)!: switch session store to Redis`.
- **One logical change per commit.** Split by scope when FE/BE changes are
  independent; a genuinely coupled change (new endpoint + the UI calling it) can be
  one commit — pick the primary scope, or use `repo` if it truly spans both.
- Enforcement (commitlint + husky) is intentionally **not** set up yet — follow the
  convention by hand for now; add the guardrail later as a `chore(repo):` commit.
- Conventional Commits are also the on-ramp to automated changelogs / semantic
  version bumps (`feat` → minor, `fix` → patch, `!` → major) via tools like
  `semantic-release` — worth writing this way now even before wiring that up.

## Branching model

This repo follows **GitHub Flow** — one long-lived branch plus short-lived feature
branches merged via pull request. Chosen because the project is solo/experimental
(lots of throwaway spikes: DB, Redis, EFS, Lambda…) and continuously deployed — the
formality of Gitflow (`develop` / `release/*` / `hotfix/*`) solves problems this
project doesn't have.

### The rules

- **`main`** is always deployable and protected — no direct pushes; everything lands via PR.
- Every change/experiment gets a **short-lived branch** off `main`.
- Open a **PR** (even solo — the PR is where CI runs and where you review your own diff).
- **Squash-merge** into `main` (keeps history one-commit-per-feature, pairs with Conventional Commits), then **delete the branch**.
- Abandoned experiment? Just delete the branch — `main` never saw it.

### Branch naming

Prefix with the change type and encode the area, mirroring the commit scopes
(`backend` / `frontend` / `repo` / `infra`):

```
feat/backend-postgres          # attach a real DB
feat/backend-redis-sessions    # move sessions out of memory
feat/frontend-signup-form
feat/infra-efs                 # shared storage experiment
feat/infra-lambda-thumbnails   # a Lambda spike
chore/repo-commitlint
fix/backend-session-cookie
```

Keep the branch prefix aligned with the eventual commit's `type(scope)` so the
history reads consistently (branch `feat/backend-postgres` → commit
`feat(backend): add postgres user store`).

### Typical loop (and how it meets the pipeline)

```
git switch -c feat/backend-postgres     # branch off main
# ...work, commit (Conventional Commits)...
git push -u origin feat/backend-postgres
# open PR  -> CI runs (lint / typecheck / build / scout)
# review the diff -> squash-merge to main -> delete branch
# merge to main -> deploy to dev -> (approval gate) -> deploy to prod
```

### Notes

- **Experiments are branches.** Trying Redis vs in-memory, EFS vs S3, a Lambda idea —
  each is its own `feat/*` branch; merge the keepers, delete the dead ends. `main`
  stays clean.
- **Branch protection** (require PR + passing CI before merge) is worth turning on in
  the GitHub repo settings once the first workflow exists — it's what makes "always
  deployable `main`" real rather than aspirational.
- **Not trunk-based (yet).** Committing straight to `main` + feature flags is the more
  advanced model; GitHub Flow gives PR-gated CI without that machinery. Graduate later
  if desired.