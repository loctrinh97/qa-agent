# `/do-cucumber-task` Sub-project 2 (PomGenerator-equivalent) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `commands/do-cucumber-task.md` so that after it generates `features/<MODULE>.feature` (Sub-project 1, already shipped), it also generates the real page object (`frontend`), screen object (`mobile`), or API client (`backend`) — plus a locator file for frontend/mobile — grounded in whatever selector/endpoint source was already resolved earlier in the same run.

**Architecture:** No new command file. New sections inserted into the existing `commands/do-cucumber-task.md`, physically between its current "Generate the feature file" section and its current "Report" section. Same prose-driven, no-companion-script pattern as the rest of this file.

**Tech Stack:** Markdown prompt command, generating TypeScript. Frontend: `@playwright/test` + `pages/BasePage.ts` (already scaffolded by `/init new`). Mobile: WebdriverIO `$('~...')` element access (matches `/init new`'s mobile devDependencies). Backend: `@playwright/test`'s `APIRequestContext` (`request` fixture) — no new dependency.

## Global Constraints

- Reference design: `docs/superpowers/specs/2026-07-24-do-cucumber-task-pomgenerator-design.md`.
- **No new command, no `QA_ROOT` workspace resolution.** Everything reads/writes relative to cwd, exactly like the rest of `do-cucumber-task.md` already does.
- **Never re-fetch, never re-open a live Playwright/Appium session, never re-ask the user for a selector source.** Reuse exactly what "Resolve the grounding/selector source" and "Verify step wording" already resolved earlier in the same run.
- **Never invent a selector or endpoint.** When no grounded source exists for a specific element/endpoint, write a `// TODO: unverified — <reason>` stub instead — never a plausible-looking guess.
- **Never overwrite an existing page object / screen object / API client / locators file wholesale.** If one exists for the module, merge in new methods/entries and leave existing ones untouched.
- Frontend locator priority: `getByRole` → `getByLabel` → `getByTestId` → `getByText` → CSS (last resort). Mobile: `accessibility id` → `UiSelector.text()`/`NSPredicate` → `resourceId`/class chain → `description()` → XPath (last resort).
- Backend has no locator file — HTTP method/path/request shape live inline in the API client, sourced from `.claude/docs/backend/api-contracts.md` or `spec.md`.
- Methods group semantically (one action/assertion, possibly spanning several Gherkin step lines) — not a rigid one-method-per-step mapping. Backend is the exception: one method per endpoint is already a natural 1:1 unit.
- **This project's memory rule (`lian-qa-plugin`): never run `git commit` on `main` as the agent.** Every task below ends with a **display-only suggested commit** (same pattern already used in `commands/spec.md`'s "After the spec is finalized" section) — print it for the user to run themselves; do not execute it.
- No automated test framework exists for this markdown-prompt project. "Testing" a task means: (a) grep-based structural verification that the new section landed correctly and in the right place, and (b) a scratch-directory smoke test that manually walks the new prose instructions against constructed sample data, writing real files via the Write tool and inspecting their content — the same technique already used throughout `docs/superpowers/plans/2026-07-23-do-cucumber-task.md`.

---

## Task 1: Class name derivation + grounding-source re-read

**Files:**
- Modify: `commands/do-cucumber-task.md` (insert between the current "Generate the feature file" section and the current "Report" section)

**Interfaces:**
- Consumes: `MODULE` (kebab-case, already set earlier in the file), `PLATFORM`, `SELECTOR_SOURCE`, and whatever scanned-docs content / live snapshot the earlier "Verify step wording" section already captured.
- Produces: `CLASS` (PascalCase) — consumed by every later task's generated file/class names.

- [ ] **Step 1: Locate the insertion point**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "Never write raw selectors\|^## Report" commands/do-cucumber-task.md
```
Expected: the "Never write raw selectors..." line, then the "## Report" heading, in that order, with nothing else between them.

- [ ] **Step 2: Insert the new sections**

Use the Edit tool on `commands/do-cucumber-task.md`:

old_string:
```
Never write raw selectors (CSS/XPath/testid strings) into any step —
quoted text is UI copy only, verified or explicitly marked unverified.

## Report
```

new_string:
```
Never write raw selectors (CSS/XPath/testid strings) into any step —
quoted text is UI copy only, verified or explicitly marked unverified.

## Determine the class name

```bash
CLASS=$(echo "$MODULE" | awk -F'-' '{for(i=1;i<=NF;i++){$i=toupper(substr($i,1,1)) substr($i,2)}}1' OFS='')
echo "CLASS=$CLASS"
```
(e.g. `user-login` → `UserLogin`)

## Re-read the grounding source (no re-fetch, no new live session)

Reuse exactly what "Resolve the grounding/selector source" and "Verify step
wording" already resolved above in this same run — never re-open a
browser/Appium session, never re-ask the user, never re-fetch scanned docs
from scratch.

- `frontend`/`mobile`, `SELECTOR_SOURCE=scanned` → the already-read content
  of `.claude/docs/frontend/components.md` or `.claude/docs/mobile/screens.md`.
- `frontend`/`mobile`, `SELECTOR_SOURCE=live` → the live Playwright/Appium
  snapshot already captured during "Verify step wording" — reuse it. If
  that session is no longer available (e.g. it timed out before this
  point), do not reopen it — treat every element that needed it as
  unverified for the sections below.
- `backend` → `.claude/docs/backend/api-contracts.md` if present, else
  `specs/<NNN>-<MODULE>/spec.md`'s Description/ACs.
- `SELECTOR_SOURCE=none` (or no source available for backend either) →
  every element/endpoint in this module is unverified.

## Report
```

- [ ] **Step 3: Verify the sections landed correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^## Determine the class name\|^## Re-read the grounding source\|^## Report" commands/do-cucumber-task.md
```
Expected: 3 lines, in that exact order.

- [ ] **Step 4: Smoke test — class name derivation**

```bash
test_class() {
  MODULE="$1"
  CLASS=$(echo "$MODULE" | awk -F'-' '{for(i=1;i<=NF;i++){$i=toupper(substr($i,1,1)) substr($i,2)}}1' OFS='')
  echo "$MODULE -> $CLASS"
}
test_class "user-login"
test_class "checkout-payment"
test_class "order-minimum"
```
Expected: `user-login -> UserLogin`, `checkout-payment -> CheckoutPayment`, `order-minimum -> OrderMinimum`.

- [ ] **Step 5: Smoke test — source re-read branches (manual walkthrough)**

Using the `checkout-payment` scenario from the Sub-project 1 plan's Task 4
(`PLATFORM=frontend`, `SELECTOR_SOURCE=scanned`), confirm the "Re-read the
grounding source" text routes to reading
`.claude/docs/frontend/components.md` — no new browser call, no new
question to the user. Then walk through a second constructed case:
`PLATFORM=backend`, no `.claude/docs/backend/` content, but a `spec.md`
with 2 ACs referencing a `$10` minimum order amount — confirm the text
routes to reading `spec.md`'s Description/ACs for grounding, not asking the
user anything new.

- [ ] **Step 6: Suggested commit (display-only — do not run)**

```bash
git add commands/do-cucumber-task.md
git commit -m "Add /do-cucumber-task class-name derivation and grounding-source reuse"
```
Per this project's governance, do not execute this — show it to the user and let them run it themselves.

---

## Task 2: Scan existing project style

**Files:**
- Modify: `commands/do-cucumber-task.md` (insert between Task 1's new content and "## Report")

**Interfaces:**
- Consumes: `PLATFORM`, `CLASS`, `MODULE` from Task 1.
- Produces: whichever existing file content (if any) later tasks must merge into, instead of overwrite.

- [ ] **Step 1: Locate the insertion point**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "every element/endpoint in this module is unverified\.\|^## Report" commands/do-cucumber-task.md
```
Expected: the last line of Task 1's "Re-read the grounding source" section, then "## Report", in that order.

- [ ] **Step 2: Insert the new section**

Use the Edit tool on `commands/do-cucumber-task.md`:

old_string:
```
- `SELECTOR_SOURCE=none` (or no source available for backend either) →
  every element/endpoint in this module is unverified.

## Report
```

new_string:
```
- `SELECTOR_SOURCE=none` (or no source available for backend either) →
  every element/endpoint in this module is unverified.

## Scan existing project style

```bash
case "$PLATFORM" in
  frontend) ls pages/*.ts locators/*.ts 2>/dev/null ;;
  mobile)   ls pages/mobile/*.ts locators/mobile/*.ts 2>/dev/null ;;
  backend)  ls api-clients/*.ts 2>/dev/null ;;
esac
```

If a file already exists for this exact module (`pages/<CLASS>Page.ts`,
`pages/mobile/<CLASS>Screen.ts`, or `api-clients/<CLASS>Client.ts`), read
it now — the generation below merges into it (adds new methods/entries for
anything new, leaves existing ones untouched) rather than overwriting it.
If empty/missing, use the default conventions below with no prior style to
match.

## Report
```

- [ ] **Step 3: Verify the section landed correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^## Scan existing project style\|^## Report" commands/do-cucumber-task.md
```
Expected: 2 lines, in that order.

- [ ] **Step 4: Smoke test — each platform's ls branch**

```bash
SCRATCH=/private/tmp/do-cucumber-pom-style-check
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/pages" "$SCRATCH/locators" "$SCRATCH/pages/mobile" "$SCRATCH/locators/mobile" "$SCRATCH/api-clients"
cd "$SCRATCH"

echo "=== frontend, empty ==="
ls pages/*.ts locators/*.ts 2>/dev/null || echo "(empty — use defaults)"

echo "=== frontend, existing file ==="
touch pages/LoginPage.ts locators/login.locators.ts
ls pages/*.ts locators/*.ts 2>/dev/null

echo "=== mobile, empty ==="
ls pages/mobile/*.ts locators/mobile/*.ts 2>/dev/null || echo "(empty — use defaults)"

echo "=== backend, empty ==="
ls api-clients/*.ts 2>/dev/null || echo "(empty — use defaults)"

rm -rf "$SCRATCH"
```
Expected: the empty cases print "(empty — use defaults)"; the "existing
file" case lists `pages/LoginPage.ts` and `locators/login.locators.ts` —
confirming the branch that should trigger "read it, merge" in later tasks.

- [ ] **Step 5: Suggested commit (display-only — do not run)**

```bash
git add commands/do-cucumber-task.md
git commit -m "Add /do-cucumber-task existing-project-style scan step"
```
Do not execute — display for the user.

---

## Task 3: Generate the locator/endpoint file

**Files:**
- Modify: `commands/do-cucumber-task.md` (insert between Task 2's new content and "## Report")

**Interfaces:**
- Consumes: `PLATFORM`, `CLASS`, `MODULE`, the re-read grounding source (Task 1), existing file content if any (Task 2).
- Produces: `locators/<MODULE>.locators.ts` (frontend) or `locators/mobile/<MODULE>.locators.ts` (mobile) on disk — consumed by Task 4's page/screen object import. Backend produces nothing here (explicitly skipped).

- [ ] **Step 1: Locate the insertion point**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "use the default conventions below with no prior style to\|^match\.\|^## Report" commands/do-cucumber-task.md
```
Expected: the last two lines of Task 2's section, then "## Report".

- [ ] **Step 2: Insert the new section**

Use the Edit tool on `commands/do-cucumber-task.md`:

old_string:
```
If empty/missing, use the default conventions below with no prior style to
match.

## Report
```

new_string:
```
If empty/missing, use the default conventions below with no prior style to
match.

## Generate the locator/endpoint file

Skip this section entirely for `backend` — HTTP method/path stay inline in
the API client (see "Generate the page object / screen object / API
client" below); there is no separate locator file for backend.

**`frontend`** — write (or merge new entries into) `locators/<MODULE>.locators.ts`:

```typescript
import { Page } from '@playwright/test';

export const get<CLASS>Locators = (page: Page) => ({
  <elementName>: page.<real-locator-call>,
  // ^ grounded — built from the resolved scanned-docs entry or live snapshot
  <otherElementName>: undefined as any, // TODO: unverified — <element description>
});
```

Selector priority order (already established for this plugin): `getByRole`
→ `getByLabel` → `getByTestId` → `getByText` → CSS (last resort). One entry
per UI element referenced by a step in `features/<MODULE>.feature`.
Grounded elements get a real locator call; ungrounded elements get a
`// TODO: unverified — <description>` comment instead — never invent a
plausible-looking selector.

**`mobile`** — write (or merge new entries into) `locators/mobile/<MODULE>.locators.ts`:

```typescript
export const get<CLASS>Locators = () => ({
  <elementName>: '~<real-accessibility-id>',
  // ^ grounded — Android/iOS accessibility id from scanned docs or live inspection
  <otherElementName>: '', // TODO: unverified — <element description>
});
```

Android/iOS priority order (already established for this plugin):
`accessibility id` → `UiSelector.text()`/`NSPredicate` → `resourceId`/class
chain → `description()` → XPath (last resort).

If a locators file already exists for this module, add new entries for any
new element referenced by the feature file; leave existing entries
untouched.

## Report
```

- [ ] **Step 3: Verify the section landed correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^## Generate the locator/endpoint file\|^## Report" commands/do-cucumber-task.md
```
Expected: 2 lines, in that order.

- [ ] **Step 4: Smoke test — frontend, grounded + unverified elements**

```bash
SCRATCH=/private/tmp/do-cucumber-pom-locators-fe
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/locators"
cd "$SCRATCH"
```

Using the same `checkout-payment` scenario data (2 ACs: "successful
payment" references a "Pay now" button verified via scanned docs as
`data-testid="pay-now-button"`; "declined payment" references an "error
banner" with no grounded source). Following the new section's instructions,
use the Write tool to create a real `locators/checkout-payment.locators.ts`:

```bash
cat locators/checkout-payment.locators.ts
```
Expected: a real file exporting `getCheckoutPaymentLocators(page)`, with
`payNowButton: page.getByTestId('pay-now-button')` (grounded, real call)
and `errorBanner: undefined as any, // TODO: unverified — error banner
shown on declined payment` (stub) — confirming both branches (grounded and
TODO-stub) are producible from the instructions as written.

```bash
rm -rf "$SCRATCH"
```

- [ ] **Step 5: Smoke test — mobile locator file**

```bash
SCRATCH=/private/tmp/do-cucumber-pom-locators-mobile
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/locators/mobile"
cd "$SCRATCH"
```

Construct a small mobile scenario (module `app-login`, one grounded
element `usernameField` with accessibility id `username-input` from
scanned `.claude/docs/mobile/screens.md`). Write a real
`locators/mobile/app-login.locators.ts` via the Write tool per the
section's mobile branch.

```bash
cat locators/mobile/app-login.locators.ts
rm -rf "$SCRATCH"
```
Expected: exports `getAppLoginLocators()` (no `page` arg), with
`usernameField: '~username-input'`.

- [ ] **Step 6: Confirm backend skip**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
awk '/^## Generate the locator\/endpoint file$/,/^## Generate the page object/' commands/do-cucumber-task.md | grep -i "skip this section entirely for \`backend\`"
```
Expected: one match — confirms the backend-skip instruction is present and
unambiguous.

- [ ] **Step 7: Suggested commit (display-only — do not run)**

```bash
git add commands/do-cucumber-task.md
git commit -m "Add /do-cucumber-task locator/endpoint file generation (frontend + mobile)"
```
Do not execute — display for the user.

---

## Task 4: Generate the page object / screen object / API client

**Files:**
- Modify: `commands/do-cucumber-task.md` (insert between Task 3's new content and "## Report")

**Interfaces:**
- Consumes: `CLASS`, `MODULE`, `PLATFORM`, the locator file from Task 3 (frontend/mobile), the re-read grounding source (Task 1).
- Produces: `pages/<CLASS>Page.ts`, `pages/mobile/<CLASS>Screen.ts`, or `api-clients/<CLASS>Client.ts` on disk — this is the artifact reported in Task 5's updated Report section.

- [ ] **Step 1: Locate the insertion point**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "leave existing entries\|^untouched\.\|^## Report" commands/do-cucumber-task.md
```
Expected: the last two lines of Task 3's section, then "## Report".

- [ ] **Step 2: Insert the new section**

Use the Edit tool on `commands/do-cucumber-task.md`:

old_string:
```
If a locators file already exists for this module, add new entries for any
new element referenced by the feature file; leave existing entries
untouched.

## Report
```

new_string:
```
If a locators file already exists for this module, add new entries for any
new element referenced by the feature file; leave existing entries
untouched.

## Generate the page object / screen object / API client

**`frontend`** — write (or merge new methods into) `pages/<CLASS>Page.ts`:

```typescript
import { Page, Locator, expect } from '@playwright/test';
import { BasePage } from './BasePage';
import { get<CLASS>Locators } from '../locators/<MODULE>.locators';

export class <CLASS>Page extends BasePage {
  readonly <elementName>: Locator;

  constructor(page: Page) {
    super(page);
    const loc = get<CLASS>Locators(page);
    this.<elementName> = loc.<elementName>;
  }

  async <actionMethodName>(/* params from the Gherkin step(s) */): Promise<void> {
    // implementation using this.<elementName>
  }

  async expect<AssertionName>(/* params */): Promise<void> {
    // assertion using this.<elementName> and expect()
  }
}
```

Rules:
- Extend `BasePage` from `pages/BasePage.ts`.
- Import locators from `locators/<MODULE>.locators.ts` — never inline a raw
  selector directly in the page object.
- Methods represent a semantic action or assertion, grouping the Gherkin
  step(s) that describe it — NOT a rigid one-method-per-step-line mapping.
  (e.g. a single `login(email, password)` method may implement "When I
  enter my email" + "And I enter my password" + "And I click Sign In" if
  the feature phrases login across separate steps.)
- All `Locator` properties `readonly`, typed `Locator`.
- If the page object already exists for this module, add new methods for
  any new Gherkin step; leave existing methods untouched.

**`mobile`** — write (or merge new methods into) `pages/mobile/<CLASS>Screen.ts`:

```typescript
import { get<CLASS>Locators } from '../../locators/mobile/<MODULE>.locators';

export class <CLASS>Screen {
  private readonly locators = get<CLASS>Locators();

  async <actionMethodName>(/* params */): Promise<void> {
    // implementation using $(this.locators.<elementName>)
  }

  async expect<AssertionName>(/* params */): Promise<void> {
    // assertion using expect($(this.locators.<elementName>))
  }
}
```

Same grouping rule as frontend — one method per semantic action/assertion,
not per literal step line. No `page` fixture; element access is
WebdriverIO's `$('~...')` built from the locator factory above. If the
screen object already exists for this module, add new methods for any new
step; leave existing methods untouched.

**`backend`** — write (or merge new methods into) `api-clients/<CLASS>Client.ts`:

```typescript
import { APIRequestContext, APIResponse } from '@playwright/test';

export class <CLASS>Client {
  constructor(private readonly request: APIRequestContext) {}

  async <endpointMethodName>(/* params from the request shape */): Promise<APIResponse> {
    return this.request.<get|post|put|delete>('<real-path-from-api-contracts.md>', {
      data: { /* real request shape, if any */ },
    });
  }
}
```

Unlike UI actions, one endpoint call is already a natural 1:1 unit with a
Gherkin step — one method per endpoint referenced by the feature's steps.
Method name/HTTP verb/path/request shape come from the grounded source
(`.claude/docs/backend/api-contracts.md` or `spec.md`); when no concrete
endpoint shape is available for a referenced call, write the method with
`// TODO: endpoint contract not found — verify against real backend code`
instead of inventing a plausible-looking path. If the client already
exists for this module, add new methods for any new endpoint; leave
existing methods untouched.

## Report
```

- [ ] **Step 3: Verify the section landed correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^## Generate the page object / screen object / API client\|^## Report" commands/do-cucumber-task.md
```
Expected: 2 lines, in that order — and "## Report" must be the very next
`##` heading (nothing new-project-content should follow this section).

- [ ] **Step 4: Smoke test — frontend page object, fresh + merge**

```bash
SCRATCH=/private/tmp/do-cucumber-pom-page-fe
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/pages" "$SCRATCH/locators"
cd "$SCRATCH"
cat > pages/BasePage.ts <<'EOF'
import { Page } from '@playwright/test';
export class BasePage {
  constructor(protected readonly page: Page) {}
  async goto(path: string): Promise<void> { await this.page.goto(path); }
}
EOF
```

Using the `checkout-payment` locators file from Task 3 Step 4 (`payNowButton`
grounded, `errorBanner` stubbed), write a real `pages/CheckoutPaymentPage.ts`
via the Write tool: a `submitPayment()` method covering the "click Pay now"
step, and an `expectPaymentDeclined(message)` method using the stubbed
`errorBanner` locator.

```bash
cat pages/CheckoutPaymentPage.ts
```
Expected: a real file, `class CheckoutPaymentPage extends BasePage`,
importing `getCheckoutPaymentLocators` from `../locators/checkout-payment.locators`,
with both methods present and typed `Promise<void>`.

Now simulate a **merge** case: re-run generation as if a new AC "refund
payment" were added to the same module. Edit `pages/CheckoutPaymentPage.ts`
to add a new `refundPayment()` method while leaving `submitPayment` and
`expectPaymentDeclined` byte-for-byte unchanged — confirm this matches "add
new methods, leave existing ones untouched."

```bash
grep -c "async submitPayment\|async expectPaymentDeclined\|async refundPayment" pages/CheckoutPaymentPage.ts
rm -rf "$SCRATCH"
```
Expected: `3` (all three methods present after the merge).

- [ ] **Step 5: Smoke test — mobile screen object**

```bash
SCRATCH=/private/tmp/do-cucumber-pom-screen-mobile
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/pages/mobile" "$SCRATCH/locators/mobile"
cd "$SCRATCH"
```

Using the `app-login` locators file from Task 3 Step 5, write a real
`pages/mobile/AppLoginScreen.ts` with a `login(username, password)` method.

```bash
cat pages/mobile/AppLoginScreen.ts
rm -rf "$SCRATCH"
```
Expected: `class AppLoginScreen` (no `extends`, no `page` fixture, no
constructor param), importing `getAppLoginLocators` from
`'../../locators/mobile/app-login.locators'`, using `$('~username-input')`-style
access inside `login()`.

- [ ] **Step 6: Smoke test — backend API client, including a TODO stub**

```bash
SCRATCH=/private/tmp/do-cucumber-pom-client-backend
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/api-clients"
cd "$SCRATCH"
```

Using the `order-minimum` scenario (grounded fact: `MIN_ORDER_AMOUNT = 10`
from `.claude/docs/backend/business-logic.md`, but no concrete endpoint
path found in `api-contracts.md`), write a real
`api-clients/OrderMinimumClient.ts` with one method,
`createOrder(amount: number)`, containing the
`// TODO: endpoint contract not found — verify against real backend code`
comment (since no real path was grounded).

```bash
cat api-clients/OrderMinimumClient.ts
grep -c "TODO: endpoint contract not found" api-clients/OrderMinimumClient.ts
rm -rf "$SCRATCH"
```
Expected: `class OrderMinimumClient` constructed with `request:
APIRequestContext`; the TODO grep finds exactly `1`.

- [ ] **Step 7: Suggested commit (display-only — do not run)**

```bash
git add commands/do-cucumber-task.md
git commit -m "Add /do-cucumber-task page object / screen object / API client generation"
```
Do not execute — display for the user.

---

## Task 5: Update Report + Rules, full-file review

**Files:**
- Modify: `commands/do-cucumber-task.md` (in-place edits to the existing "Report" and "Rules" sections — these sections already existed from Sub-project 1 and currently contradict the new behavior)

**Interfaces:**
- Consumes: the complete file produced by Tasks 1-4.
- Produces: the finished command file for this round.

- [ ] **Step 1: Update the Report section**

Use the Edit tool on `commands/do-cucumber-task.md`:

old_string:
```
## Report

```
Spec: specs/<NNN>-<MODULE>/spec.md
Feature: features/<MODULE>.feature
Platform: <PLATFORM>
Selector source: <scanned docs | live Playwright | live Appium | unverified | not applicable (backend)>
Wording discrepancies fixed: <list, or "none">

Not generated yet (future phases): page objects/locators, step definitions,
test execution.
```
```

new_string:
```
## Report

```
Spec: specs/<NNN>-<MODULE>/spec.md
Feature: features/<MODULE>.feature
Platform: <PLATFORM>
Selector source: <scanned docs | live Playwright | live Appium | unverified | not applicable (backend)>
Wording discrepancies fixed: <list, or "none">
Page object / Screen / API client: <path>
Locators: <path, or "not applicable (backend)">
Selectors/endpoints grounded: <n>/<total>
TODO stubs remaining: <n> (method/entry names listed, or "none")

Not generated yet (future phases): step definitions, test execution.
```
```

- [ ] **Step 2: Update the Rules section**

Use the Edit tool on `commands/do-cucumber-task.md`:

old_string:
```
## Rules

- Do NOT generate page objects, locators, or step definitions — those are
  future phases of this plugin.
- Do NOT run any test.
- Do NOT run `git` commands — this command only reads/writes files and
  calls MCP tools.
- Never guess a module name, platform, or selector wording — ask when
  ambiguous, mark "unverified" when no source is available.
- Never invent scenario steps not present in the fetched CucumberStudio
  content.
```

new_string:
```
## Rules

- Do NOT generate step definitions or run any test — those are future
  phases of this plugin.
- Do NOT run `git` commands — this command only reads/writes files and
  calls MCP tools.
- Never guess a module name, platform, selector wording, real selector, or
  real endpoint — ask when ambiguous, mark "unverified"/TODO-stub when no
  grounded source is available.
- Never invent scenario steps not present in the fetched CucumberStudio
  content.
- Never overwrite an existing page object / screen object / API client /
  locators file wholesale — merge in new methods/entries, leave existing
  ones untouched.
```

- [ ] **Step 3: Verify no forbidden content leaked in**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -niE "step definition|Planner\b|Analyzer\b|FeatureGenerator|StepsGenerator|TestRunner\b|SelectorHealer|QualityGatekeeper|git add|git commit|git push|QA_ROOT" commands/do-cucumber-task.md
```
Expected: **zero matches**. Any match is a defect (step-definition generation,
named pipeline agents, an automated git command, or `QA_ROOT` workspace
resolution all remain explicitly out of scope this round).

- [ ] **Step 4: Verify the contradiction is fully resolved**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "Do NOT generate page objects" commands/do-cucumber-task.md || echo "correct — old prohibition removed"
grep -n "Not generated yet (future phases): step definitions, test execution\." commands/do-cucumber-task.md
```
Expected: the first grep finds nothing (prints "correct — old prohibition
removed"); the second finds exactly the updated Report line.

- [ ] **Step 5: Full-file heading review**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^## " commands/do-cucumber-task.md
wc -l commands/do-cucumber-task.md
```
Expected heading order: `## Parse the CucumberStudio URL`, `## Resolve the
CucumberStudio MCP tool`, `## Fetch the scenario`, `## Determine the
module name`, `## Determine the platform`, `## Resolve the grounding/
selector source`, `## Verify step wording`, `## Write/update spec.md`,
`## Validate the spec`, `## Generate the feature file`, `## Determine the
class name`, `## Re-read the grounding source (no re-fetch, no new live
session)`, `## Scan existing project style`, `## Generate the locator/
endpoint file`, `## Generate the page object / screen object / API
client`, `## Report`, `## Rules` (17 headings). Read through the full file
once end-to-end to confirm it reads as one coherent document — the new
sections should feel like a natural continuation of Sub-project 1's
existing prose, not a bolted-on appendix.

- [ ] **Step 6: End-to-end walkthrough — one platform, start to finish**

Pick the `checkout-payment` (`frontend`) scenario used across Tasks 3-4.
Read the full modified `commands/do-cucumber-task.md` top to bottom and
manually trace every step for this scenario, from URL parsing through to
the final Report output. Confirm the Report you'd produce at the end
reads coherently, e.g.:

```
Spec: specs/001-checkout-payment/spec.md
Feature: features/checkout-payment.feature
Platform: frontend
Selector source: scanned docs
Wording discrepancies fixed: none
Page object / Screen / API client: pages/CheckoutPaymentPage.ts
Locators: locators/checkout-payment.locators.ts
Selectors/endpoints grounded: 1/2
TODO stubs remaining: 1 (errorBanner)

Not generated yet (future phases): step definitions, test execution.
```

- [ ] **Step 7: Suggested commit (display-only — do not run)**

```bash
git add commands/do-cucumber-task.md
git commit -m "Update /do-cucumber-task Report and Rules for page object/locator/API client generation — Sub-project 2 complete"
```
Per this project's governance, do not execute this. Show the diff
(`git diff commands/do-cucumber-task.md`) and this commit message to the
user and let them review and commit on their own terms.
