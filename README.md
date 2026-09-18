# retailcloud API Test Automation

Automated Newman/CI runner for the retailcloud **Catalog Service API** and
**Console Service API** Postman collections. Everything in this folder is
self-contained: collections, environments, a local runner script, and a
GitHub Actions workflow.

## What's in here

```
collections/
  retailcloud_catalog_crud.postman_collection.json       142 requests, full CRUD, idempotent-safe
  retailcloud_catalog_qa_gap_tests.postman_collection.json  85 requests, QA gap-coverage scenarios
  retailcloud_console_crud.postman_collection.json       111 requests, full CRUD, idempotent-safe
environments/
  retailcloud_catalog_local / _dev  .postman_environment.json
  retailcloud_console_local / _uat / _production .postman_environment.json
scripts/
  run-tests.sh            the real test runner (Newman + HTML/JSON reports)
  dev-mock-server.js       a fake API for smoke-testing this pipeline without live credentials
.github/workflows/
  api-tests.yml            CI workflow: push / PR / daily schedule / manual run
```

## Why the collections are safe to run more than once

Every Create/Replace/Update request that carries an "identifying" field
(name, code, sku, etc.) appends `{{$timestamp}}` to it, so re-running the
same collection twice in a row never collides with data the previous run
left behind. A few resources also accept a client-supplied primary key in
the request body itself (Catalog's Item/Menu Page `id`, Console's Table
Group/Table `tableGroupID`/`tableID`) — those are randomized on Create and
then kept in sync with the id actually captured from the Create response
for every later Replace/Update/PUT, so the body id never drifts from the
path id.

**Known limitation:** five Console resources have no single obvious unique
text field to randomize and were left as-is: **Table Booking, Tip Setup,
CDS Configuration**, and the two bulk-action endpoints (**Bulk Update
Tables**, **Batch Update Order Routing**). Repeated runs against those
specific requests may still hit uniqueness conflicts depending on how the
live API enforces them — worth a manual look before relying on them in an
unattended nightly run.

The **QA Gap Coverage** collection is different on purpose: two of its test
folders (01 and 12) intentionally reuse a static name to verify the API
*rejects* duplicates. That's the point of those specific tests, not a bug —
they're expected to need a fresh environment (or tolerate a 409 on the
"first" create step) if you run them back-to-back without resetting test
data in between.

## Running locally

```bash
npm install

# Point at a real environment via env vars:
export CATALOG_BASE_URL=https://dev-platform.rc.fyi
export CATALOG_ACCESS_TOKEN=<bearer token>
export CONSOLE_BASE_URL=https://uat-api.retailcloud.com/console
export CONSOLE_ACCESS_TOKEN=<bearer token>

npm test                 # all three collections
npm run test:catalog     # Catalog CRUD + Catalog QA Gap only
npm run test:console     # Console CRUD only
```

Reports land in `reports/<UTC timestamp>/`, one `.report.html` (open it in
a browser) and one `.report.json` per collection, plus a `reports/latest`
symlink to the most recent run.

Alternatively, point at one of the committed environment files instead of
env vars (fill in `access_token` locally — never commit a real token):

```bash
export CATALOG_ENV_FILE=environments/retailcloud_catalog_dev.postman_environment.json
export CATALOG_ACCESS_TOKEN=<bearer token>
npm run test:catalog
```

### Trying it without real credentials

`scripts/dev-mock-server.js` is a zero-dependency fake API that echoes back
whatever you send it with a generated id, so you can confirm the runner,
variable-chaining, and report generation all work before you have a live
token:

```bash
node scripts/dev-mock-server.js 4000 &
CATALOG_BASE_URL=http://localhost:4000 CATALOG_ACCESS_TOKEN=dummy \
CONSOLE_BASE_URL=http://localhost:4000 CONSOLE_ACCESS_TOKEN=dummy \
  npm test
```

It won't produce a clean pass on the QA Gap collection or on requests that
check specific business rules (404 handling, uniqueness enforcement,
immutable fields) — those genuinely need the real API. It's only meant to
prove the pipeline plumbing works.

## CI (GitHub Actions)

`.github/workflows/api-tests.yml` runs on every push to `main`, every pull
request, once a day at 06:00 UTC, and on demand (`workflow_dispatch`, with
an optional `scope` input to run just `catalog` or just `console`).

Before it'll pass, add these as repository secrets (**Settings → Secrets
and variables → Actions → New repository secret**):

| Secret | Example |
|---|---|
| `CATALOG_BASE_URL` | `https://dev-platform.rc.fyi` |
| `CATALOG_ACCESS_TOKEN` | bearer token for a Catalog test account |
| `CONSOLE_BASE_URL` | `https://uat-api.retailcloud.com/console` |
| `CONSOLE_ACCESS_TOKEN` | bearer token for a Console test account |

Every run uploads the HTML + JSON reports as a downloadable artifact
(`api-test-reports-<run number>`, kept 30 days) and posts a one-line
summary to the run's Job Summary tab. The job fails (and the workflow goes
red) if any collection has a failed assertion, so it's safe to use as a
required PR check.

### Adjusting the schedule or trigger

Edit the `on:` block in `.github/workflows/api-tests.yml` — for example,
change `cron: "0 6 * * *"` to run more or less often, or drop the
`schedule:` block entirely if you only want push/PR/manual runs.

## Extending this

- To add a new resource's requests to the idempotency pattern, look at how
  `TEXT_FIELD_MAP` / `ID_SYNC_MAP` were used when these collections were
  generated — the same shape of fix applies to any newly added Create
  request that reuses static example data.
- To wire in Slack/email notification on failure, add a step after "Fail
  the job if any collection failed" that reads `reports/<dir>/*.report.json`
  and posts a summary — the JSON reporter output has per-request pass/fail
  detail if you want more than the CLI summary.
