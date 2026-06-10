# DIS Quantum API Integration — Status & Handoff

> **Purpose of this doc:** let any Claude Code session (esp. John's work PC) pick
> up the DIS live-lookup integration without re-discovering anything. Last
> updated **2026-06-10** by the home-PC session. Supersedes the original
> `Downloads/DIS_API_HANDOFF.md` (which had two wrong assumptions — noted below).
>
> **2026-06-10 BREAKTHROUGH:** DIS sent the official GET-entity list — **phone &
> email DO exist** in the API (`contact` + `communicationDetail` entities, singular
> paths). The §6 "phone/email blocked" question is ANSWERED; full prefill parity is
> achievable. See §2a. The Worker whitelist must be extended before wiring (§4).

---

## TL;DR — where we are

**Goal:** replace the static ~38k-row "Contact List" XLSX feeding the customer
typeahead with a **live** lookup against the DIS *Quantum* API, via a Cloudflare
Worker proxy (so the API key never touches the browser).

| Piece | Status |
|---|---|
| DIS API reverse-engineered (auth, format, entities, query lang) | ✅ done |
| Cloudflare Worker proxy built, deployed, secured, verified | ✅ **done & live** |
| Phone/email source found & verified (`contact`/`communicationDetail`, §2a) | ✅ **done 2026-06-10** |
| Worker whitelist extended with `contact` + `communicationDetail` + redeploy | ✅ **done 2026-06-10** (version `fa874317`) |
| `index.html` typeahead wired to the Worker (full prefill parity) | ✅ **done 2026-06-10** — branch `dis-live-lookup`, v3.14.0 |
| In-app positive-path test (login → live search → pick → prefill) | ✅ **PASSED 2026-06-10** — John quoted a Used unit picking a live DIS customer |
| DIS lookup modal (Used/SL quotes) wired live too | ✅ **done 2026-06-10** — v3.14.1, merged to `main` |

| Shortline "My Customers" modal: 🔍 DIS button added (had no lookup at all) | ✅ **done 2026-06-10** — v3.14.2 |

**The integration is LIVE in production (v3.14.2).** All three customer-lookup
surfaces (Hub inline typeahead, the Used/SL quote-builder lookup modal, and the
SL My Customers add/edit modal) search DIS live with automatic offline-XLSX
fallback. Only remaining open item: §6 question 3 (key write scope / sandbox —
John to ask DIS). Keep dropping a fresh Contact List export into
`HPE Link/All Customers/` occasionally so the offline fallback doesn't go stale.

**NEXT PHASE — live INVENTORY feed (v3.15.0, soak-testing since 2026-06-10):**
the admin-only **Shortline → DIS Feed (beta)** page diffs the live equipment
pull against the daily xlsx, in-app through the Worker (whitelist v2,
`cba254b7`). First production run: **4.4s for the full pull**, used matched
89/89 with 0 ghosts, every new-side diff explained (sold-since-upload, new
arrivals, blank-New/Used placeholder rows, dead-stock locations). John soaks
it across real business days before any rep-facing cutover. Remaining gaps
(reserved, Location codes) ride the xlsx as an overlay — DIS support email
sent 2026-06-10 (q5–q9 condensed; see §6).

---

## 1. The Worker (server side) — DONE, do not rebuild

- **Live URL:** `https://dis-proxy.johnwilliams.workers.dev`
- **Cloudflare account:** `421b266ca743101979e4d08af668b8cd` (johnwilliams@hydeparkequipment.ca), subdomain `johnwilliams.workers.dev`
- **Deployed version:** `cba254b7` (2026-06-10 — whitelist v2: + product, manufacturer, branch, equipmentFinancials, ledgerEntry, inventory, stockArea for the inventory feed; previous: `fa874317`). Deployed via **wrangler from the work PC** (now authed — see §5); verified unauth → 401, OPTIONS → 204 post-deploy.
- **Secret:** `DIS_API_KEY` is set in the Worker (Settings → Variables & Secrets). Never in code/repo.
- **Canonical source:** on the home PC at `C:\Users\johnr\dis-proxy-worker\` AND embedded in §7 below. **Not yet its own git repo** (a good follow-up; for now this doc is the backup).
- **Endpoint shape:** `GET /dis/{entity}?query=…&page=&size=&sort=`
- **Verified:** unauthenticated → 401, bogus token → 401, `OPTIONS` → 204, forwards to DIS with the key. The **only** untested path is a real logged-in token returning data — John tests that in-app after wiring.

**Existing unrelated Worker:** `hpe-site-proxy` (a generic `?url=` proxy to
`www.hydeparkequipment.ca`) — **leave it alone**, it's a different feature.

### How the Worker authenticates callers (IMPORTANT — corrects the old handoff)
The old handoff assumed the app sends a Google **ID token (JWT)**. It does **not** —
the app uses `google.accounts.oauth2.initTokenClient` with **drive scope only**, so
it holds an **access token**. The Worker therefore validates the access token with
two checks:
1. **tokeninfo** → `aud`/`azp` === the HPE OAuth client ID (proves the token was
   minted for this app; works regardless of scope).
2. **userinfo** (`https://www.googleapis.com/oauth2/v3/userinfo`) → `email` ends
   with `@hydeparkequipment.ca` and `email_verified` (the same endpoint the app's
   own login uses; reliably returns email even for drive-scoped tokens, where
   `tokeninfo.email` may be absent).

So the **client must send the app's existing access token**:
`Authorization: Bearer <access_token>`.

### Redeploying the Worker (only if you change it)
**Work PC (preferred, set up 2026-06-10):** `cd C:\Users\johnw\dis-proxy-worker;
npx wrangler deploy` — wrangler is OAuth-authed on this machine and
`wrangler.toml` exists; the secret persists across deploys. (Gotcha: the
first `wrangler login` timed out because the OAuth "Allow" click came after
the local listener gave up — re-run and approve promptly.)
Fallback: Dashboard → Workers & Pages → `dis-proxy` → Edit code → paste
`src/worker.js` → Deploy. **Note:** the dashboard editor is a cross-origin
iframe — the Claude-in-Chrome extension cannot click/type inside it, so
dashboard deploys are manual-only.

---

## 2. DIS API reference (confirmed empirically, 2026-06-09)

- **Base:** `https://hy2303.disprism.com/api`
- **Auth header:** `X-API-Key: <key>` (raw key — **NOT** `Authorization: Bearer`; Bearer returns 403)
- **Response:** HAL / Spring-Data-REST — records under `_embedded.{entity}[]`, paging under `.page` (`size`, `totalElements`, `totalPages`, `number`)
- **⚠️ Path naming gotcha:** DIS's query doc says endpoints are "the pluralized
  form" of the model, and `customers`/`addresses` do work pluralized — but the
  official entity list (sent by DIS 2026-06-10, full list in §2b) uses the model
  names **as-is**, and `contact`/`communicationDetail` only respond on the
  **singular** path (`/contacts` → 404, `/contact` → 200). When probing a new
  entity, try the list's exact name first, then the plural.
- **Entities confirmed live:** `equipment`, `customers` (38,568 rows), `addresses`
  (68,031 rows), `contact` (38,154 rows), `communicationDetail` (~49k rows).
- **`customers` fields:** `webId, customerNumber, customerName (single combined name — NO first/last), active, businessEntity, mainAddressId, contactId, branchId, …` (`contact`/`contactId` were empty on the records sampled).
- **`addresses` fields:** `webId, name, name2, city, state, street, postalCode, customerId, addressType, useForShipTo/BillTo/Main, …` (linked to a customer via `customerId`; no phone/email on the address itself — they're in `communicationDetail`, §2a).

### Query language
`?query={field}{op}{value}`, comma-separated = AND, prefix `|` (URL-encode `%7C`) = OR. Paging: `page`, `size`, `sort`.
Strings (case-insensitive): `:` eq · `!` ne · `:foo*` startsWith · `:*foo` endsWith · `*foo*` contains. Nested via dot notation (don't prefix the top entity's own name).

### Confirmed working customer search (use this for the typeahead)
```
GET /dis/customers?query=customerName:*{input}*&size=10&sort=customerName
```
(e.g. `customerName:*construction*` → 193 matches, returns customerNumber + customerName + active). **NOTE:** the old handoff's `lastName:{input}*` is WRONG — there is no `lastName` field; use `customerName`.

---

## 2a. Phone & email — FOUND (verified live 2026-06-10)

The earlier "no phone/email anywhere" conclusion was wrong — the probe only tried
pluralized paths. Two singular-path entities hold everything the Contact List
XLSX had:

- **`/contact`** (38,154 rows ≈ the XLSX row count): `webId, firstName, lastName,
  middleName, nickname, organizationName, title, notes, addressId, customerId,
  usedForWorkOrderRecipient, deleted, …` + `_links` to `customer`, `address`,
  `communicationDetails`.
- **`/communicationDetail`** (~49k rows): `webId, communicationMethod
  (enum: PHONE | EMAIL | CELL | FAX — case-sensitive), information (the actual
  number/email string), extension, main (bool), addressId, contactId, deleted`.
  A detail links to an address OR a contact (either id can be null).

### Verified lookup chain for the typeahead (per selected customer)
1. Typeahead search (unchanged): `/customers?query=customerName:*{q}*&size=10&sort=customerName`
   → take `webId`, `customerNumber`, `customerName`, **`mainAddressId`**.
2. Phone/email on pick: **`/communicationDetail?query=addressId:{mainAddressId}&size=10`**
   → filter `deleted`, prefer `main:true`; `communicationMethod` tells you which
   field each `information` value fills. Verified on 5 random customers — every
   one returned its PHONE (and EMAIL where present).
3. City/province on pick (optional): `/addresses?query=webId:{mainAddressId}&size=1`
   → `city`, `state`.

So a pick costs 2 small extra GETs and achieves **full prefill parity** (name,
customer#, phone, email, city, province). Note the reverse direction does NOT
work: `communicationDetail?query=address.customerId:{custId}` returns 0 because
customer-main addresses carry `customerId: null` — always go customer →
`mainAddressId` → `addressId`.

### Worker prerequisite
~~`ALLOWED_ENTITIES` must gain `"contact"` and `"communicationDetail"`~~
**DONE 2026-06-10** — deployed as version `fa874317`; verified unauth → 401,
OPTIONS → 204 after deploy.

---

## 2b. Official GET-entity list (from DIS, 2026-06-10)

Full catalog DIS sent (use exact names; singular unless confirmed otherwise):
`accountReceivablePayment, address, agreementGroup, agreement, branch, checklist,
checklistAcceptedResult, checklistCategory, checklistDisclaimer, checklistItem,
checklistItemDisclaimer, communicationDetail, consolidatedInvoice, company,
configurationDescription, configurationKey, configurationOption, contact,
customer, customerPoRules, customerPurchaseOrder, department, equipment,
equipmentGroup, updateEquipmentHourMeter, equipmentHistory, equipmentMeter,
equipmentWarranty, equipmentFinancials, file, folder, generalLedgerAccount,
generalLedgerAccountGroup, generalLedgerAccountRelationship,
generalLedgerSummary, inventory, invoice, invoiceLine, invoiceSegment, laborCode,
laborTimeType, ledgerEntry, ledgerEntryAging, ledgerEntryDocument,
ledgerEntryMatch, manufacturer, metadata, notificationRecord, operation,
partsOrder, partsOrderLine, periodicMaintenance, periodicMaintenanceSchedule,
product, productBranch, requestedPartsOrderLine, scheduleEvent, serviceType,
signature, solvencyCode, standardJobCode, standardJobCodeManufacturer,
standardJobCodeManufacturerStructure,
standardJobCodeManufacturerStructureFieldName, standardJobCodeName, statement,
stockArea, stockAreaAssignment, submittedPartsOrderLine, task, taskBoard,
taskComment, team, technicianClock, timeCard, timeCardLine, truck, vendor,
webHook, webUser, workOrderFreeField, workOrderHeader, workOrderLine,
workInProcess, workOrderSegment, workOrderTechnician`
plus special routes: `public/v1/file/{list,urls,resolve}`,
`workOrderHeader/convert`, `workOrderSegment/{webId}/workOrderTechnicians`,
`configurationOption/{webId}`.

Interesting for future features: `invoice`/`invoiceLine`, `workOrderHeader`
(service status for customers), `inventory`, `partsOrder`, `equipmentHistory`.

DIS also sent the query-language doc (operators, wildcards, `,` = AND,
`|`-prefix = OR, dot-notation nesting) — it matches what §2 already documents.
**The full OpenAPI spec WAS found (2026-06-10):**
`https://hy2303.disprism.com/api/swagger-ui/yaml/api-docs.yaml` (~872 KB; the
swagger-ui HTML references `./yaml/api-docs.yaml`). Local copy:
`C:\Users\johnw\dis-feed-test\api-docs.yaml` + a schema-digger script
`spec_dig.py` (`list` / `fields <Schema>` / `find <substring>`). Spec-settled
facts: `Equipment` has exactly 39 props — **no unit-level list price / MSRP /
replacement value / flooring fields exist anywhere in the API** (`listPrice`
only on transaction lines: InvoiceLine, PartsOrderLine); `equipment.location`
exists in the schema but HPE's sync leaves it null; the full `equipmentStatus`
enum includes `RESERVED_SALE` / `RESERVED_RENT` / `ON_ORDER_INVENTORY` /
`ON_ORDER_RESERVE` / `DOWN` / `LOST` / `TRADE_IN` / `INTERNAL_ASSET` etc., but
HPE's data uses almost none of them (RESERVED_SALE = 0 rows, ON_ORDER = 0;
only INTERNAL_ASSET = 7) — reservations evidently don't sync to status.

---

## 2c. Equipment & parts-inventory probe (2026-06-10, work PC, direct API)

Goal: can the live API replace the two manual uploads — the daily **All
Inventory xlsx** (feeds Shortline new-equipment AND the whole Used module) and
the **Parts Inventory xlsx** (Stihl/Kubota 660 on-hand)? Probed with the key as
a local env var (§5 pattern). Headline: **structure/status/identity = yes;
prices & reserved flags = not exposed (blockers, ask DIS — §6 q5–7).**

### Entities probed (all live; embedded keys in parentheses where non-obvious)
- **`equipment`** (93,115 rows): `dealerEquipmentId` = stock number/tag ·
  `equipmentStatus` enum observed: `AVAILABLE_SALE` (1,511) / `SOLD` (69,421) /
  `AVAILABLE_RENT` (3) / `ON_SERVICE` / `RETURNED_SUPPLIER` / `UNDEFINED` —
  invalid enum values in a query → 400 error, valid-but-empty → 0 ·
  **⚠️ `deleted:false` IS MANDATORY in every equipment query** — DIS
  soft-deletes long-gone units but leaves `equipmentStatus` frozen at
  `AVAILABLE_SALE`: of the 1,511, **627 were `deleted:true` ghosts** (caught by
  John: tag 66206, sold ~2020, still "available"). Real available pool =
  **884 (760 NEW / 124 used)** ·
  `glEquipmentStatus`: **`NEW` = new, `UNDEFINED` = used** (`USED` is a valid
  enum but 0 rows!) ·
  `ownerType`: `DEALER` vs `CUSTOMER` (**79,853 customer-owned units** — the
  customer-fleet feature dataset) · `modelYear`, `serialNumber`, `hourMeter`
  (often 0 with real hours buried in `notes` text), `dateInventory` (= xlsx
  In Date), `description` (short), `notes` (long desc), `branchId`,
  `productId`, `location` (always null — use branchId) ·
  **`branchId` = the desktop DIVISION column, NOT Location** — verified
  119/119 against John's manual desktop pull (USED MANUAL PULL.xlsx,
  2026-06-10). **❌ the desktop Location codes (`S M SC YD HP BM LA R` —
  dead-stock/yard/etc codes the app's xlsx filters rely on) are NOT exposed
  anywhere:** `location`/`addressId` always null, `departmentId` merely
  mirrors `branchId`, `equipmentGroup` is empty (0 rows). The API feed
  therefore INCLUDES dead-stock units, indistinguishable from real M/S stock
  (§6 q8). Desktop status list (per John's screenshot): A=Available, F=Fixed
  Asset, R=Rental, S=Sold, T=Transfer, O=On Order — desktop A ≈ API
  `AVAILABLE_SALE,deleted:false`, **but not exactly:** ground-truth comparison
  of the used pool found **0 missing and 5 extras** — orphan records created
  2014–15 and frozen since (never deleted, desktop no longer lists them as A;
  tag re-use observed, e.g. 48135 exists as both a 2014 AVAILABLE_SALE and a
  2015 SOLD record). ~4% junk; filterable by ancient `dateUpdated` heuristic
  or ask DIS (§6 q9).
- **`branch`** (embedded key `branches`, 2 rows): `374` = `M` (Mallard),
  `3215379434` = `S` (Scotland) — `branchNumber` is the xlsx location code.
- **`product`** (102,074): `productCode` = model, `description`,
  `manufacturerId`. **`manufacturer`** (1,046): `internalId`/`description` =
  make (e.g. GENERAC). So make/model = 2-hop join `equipment.productId →
  product → manufacturer`. Products/manufacturers have `dateUpdated` →
  incremental client-side cache is viable.
- **`equipmentFinancials`** (17,188; embedded key `equipmentFinancials`):
  fields `priceCost, salePrice, priceRetail, priceSuggestedList,
  priceDealerCost`, keyed by `equipmentId`. **Coverage against the REAL
  (deleted:false) available pool:** Shortline-new 290/373 cost>0 (78%), used
  115/124 cost>0 (93%) — but **0 retail / 0 suggestedList on new; LIST PRICE
  IS EFFECTIVELY ABSENT** even though the xlsx report has it for everything.
  `salePrice` (9,924>0 API-wide) appears to be set at/after sale.
- **`invoice`** (265,891; embedded key `invoices`): `invoiceNumber, status,
  dateCreated/Closed, total, customerId, equipmentId, salesMan, soldBy,
  branchId, poNumber`. **All 500 most-recent are `status:closed`** (even
  same-day) — open/working deals are not visible, so **"Reserved
  Employee/Customer/Invoice" (xlsx) could NOT be located in the API.**
  `workInProcess` is just 8 WIP category codes, not reserved tracking.
- **`invoiceLine`** (1,448,023; embedded key `invoiceLines`): `invoiceId,
  equipmentId, productId, type, description, quantity, unitPrice, listPrice,
  cost, extendedAmount, hourMeterIn/Out, warranty*` — purchase-history gold.
- **`inventory`** (150,870 — PARTS stock): `quantityInStock,
  quantityAllocatedToCustomer, quantity*Backorder, binName, lastDateIn,
  lastDateOut, productId, stockAreaId, mainBin`. **`stockArea`** (4):
  `areaName` e.g. `Warehouse-M`, `areaType MAIN_WAREHOUSE`, `branchId` → the
  xlsx Division. Parts parity looks strong (part# / desc via `product`,
  on-hand/allocated/bins/dates live); quick-code + vendor-code(486/660)
  mapping still to confirm via `manufacturer.internalId`.
- **`productBranch`** (151,106): product↔branch activation only, no pricing.

### Parity verdict — All Inventory xlsx → `equipment`
✅ stock#, new/used, status (`AVAILABLE_SALE,deleted:false` ≈ desktop A),
branch, year, serial, in-date, short+long desc, make/model (join, 100% success
on all 884), sold-detection (status flip beats drop-off-the-file inference).
⚠️ cost partial (78% new / 93% used), hours mostly 0 (likely same in xlsx;
reps already override hours/prices in-app). ❌ **list price, suggested list,
replacement value, flooring, reserved-columns, and the desktop Location codes
(dead-stock filtering)** — not exposed anywhere found. **Full replacement is
blocked on §6 q5–8; a hybrid (live status/arrivals + xlsx-or-in-app prices) or
DIS answers are needed.** Parts xlsx replacement looks MORE viable today since
parts pricing already comes from price files, not this xlsx.

**Product decisions from John (2026-06-10):** the Used list should contain
**ALL available used inventory regardless of location** (no S/M gate — the
current app's xlsx filter excluding dead-stock locations is intentional today,
but with the API that distinction isn't available anyway, see q8). Eventually
he wants an **admin-only table of all non-M/S "available" inventory** (dead
stock surfacing) — blocked on q8.

**Ground-truth validation (2026-06-10):** John exported the desktop "Unit
List" report filtered to all Status-A used units (119 rows, `USED MANUAL
PULL.xlsx`) and we diffed it against the simulated API feed (124 rows):
**all 119 present; 5 extras = the 2014–15 orphans (q9); branchId↔Division
match 119/119.** The desktop report header also confirms which fields the
report has that the API lacks: Suggested List Price, List Price, Cost (full),
Replacement Value, Flooring Amount/Due Date, Meter, Sold By / Sale Date /
Sale Amount, Location, Rental Status, Class, Attachment, Trade In.

**Ground-truth validation ROUND 2 (2026-06-10, the big one):** John exported
the FULL desktop report — every Status-A unit, new+used, all brands, all
locations (`UnitsDefineSearchExpanded (15).xlsx`, 849 rows, 100 columns).
Diff vs the complete API feed (884):
- **Coverage 849/849 — zero missing.** Division matches **849/849**. The only
  new/used mismatches are 13 desktop rows with BLANK New/Used (placeholders:
  CREDIT, FLOOR, PKG00x, V-11, …).
- **All 3x extras are pre-2020 orphans → ORPHAN RULE, validated 0 FP / 0 FN:
  exclude units with `dateUpdated` < 2020-01-01.** Orphans' last-touch range
  is 2013→2019-12; every real unit has been touched since 2022-09. (q9
  answered ourselves — no DIS needed.)
- **Cost: 712 exact-to-the-penny matches;** only 18 desktop-only costs (all
  2020–22 in-dates, financials never backfilled). ~97% parity.
- **The list-price "blocker" mostly evaporated:** even in the DESKTOP report,
  NEW units have essentially no list price (1/717!) — Shortline new pricing
  never came from this file (SKU catalog prices quotes). Used: desktop
  suggested-list 48/119 vs API `priceSuggestedList` ~50 — **API is at parity
  on used pricing**. Desktop List Price on used is only 20/119 (reps override
  in-app anyway, `unitPriceOverrides`). Replacement Value is 0 on ALL 849
  desktop rows — field unused, drop it from q7.
- **FLOORING: SOLVED via `ledgerEntry` (John pushed back on "not exposed" —
  he was right).** A unit's Flooring Amount = the NET of its ledgerEntry rows
  with `equipmentFinancialCategory:NOTE_BALANCE` (desc "FLOOR PLAN"); the due
  date is on those entries. **Validated 849/849 EXACT amount matches (zero
  mismatches, all 443 floored units + all zeros)**; due-date 392/443 (the
  rest = picking which entry's dueDate when several — refine: prefer the
  positive-amount entry with latest datePosted). ⚠️ The bulk query
  `equipmentFinancialCategory:NOTE_BALANCE` 500s server-side — OR-batch by
  equipmentId instead (40/call, ~22 calls for the fleet; see
  `flooring_check.js` in dis-feed-test).
- **Reserved: the one remaining wall — now EXHAUSTIVELY confirmed:**
  EM/ES Unit-Sale invoices DO sync to `invoice` — 24,744 EM* + 7,355 ES*
  rows — but **only once finalized/closed**. Queried all 16 reserved-invoice
  numbers from the 18 currently-reserved units: 15 absent (drafts), 1 found
  but only as a closed $565 deposit invoice (ES08780). The equipment record
  shows nothing (status stays AVAILABLE_SALE; only `dateUpdated` bumps on
  reserve day — the reservation transaction even bumps the unit's OLD closed
  work-order segments' dateUpdated, so the host touches the object graph but
  writes the reserve data somewhere unreplicated). Full REST sweep done:
  open work orders DO sync (`workOrderHeader` w/ dateClosed:null, 40,347
  rows) but EM31374 is not there (`orderDocumentId:EM31374` → 0, segments =
  only the unit's 3 old shop jobs); `customerPurchaseOrder`,
  `consolidatedInvoice`, `agreement`, `operation`, `signature` are ALL EMPTY
  (0 rows) for HPE; notificationRecord/scheduleEvent/task = webhook-log/
  calendar/boards. **John's Quantum host UI (AS/400 session, QPADEV device)
  displays both "On Reserve" + the open EM doc (Unit Sale Warning) AND the
  unit Location code — so both exist host-side and simply are not replicated
  to the Prism REST database.** The precise DIS ask, if/when John wants it:
  (a) can the sync populate `equipment.location` (schema field exists, always
  null), and (b) can unposted Unit-Sale documents be replicated (or the
  reserve flow set RESERVED_SALE, which the schema supports)? Until then:
  occasional xlsx overlay for reserved+location, or in-app marking.
  (`webHook` entity exists — real-time push subscriptions are a future
  possibility.)

**Local test harness:** `C:\Users\johnw\dis-feed-test\build_feed.js` (work PC,
outside the repo so Pages never serves it) simulates the full feed with the
app's exact filters and writes `new_inventory.csv` / `used_inventory.csv` /
`kubota_new.csv` for side-by-side comparison. Run:
`$env:DIS_API_KEY=[Environment]::GetEnvironmentVariable('DIS_API_KEY','User'); node build_feed.js`

### Practical notes for the wiring (when unblocked)
- HAL embedded keys are sometimes pluralized (`branches`, `invoices`,
  `invoiceLines`, `workInProcesses`) and sometimes not (`equipment`,
  `equipmentFinancials`) — never hardcode without checking.
- Numeric query ops work: `priceCost>0`, `field!0`; enum fields 400 on
  unknown values.
- **⚠️ `sort=webId` is MANDATORY on every paginated query.** Without an
  explicit sort the backend's page order is unstable — multi-page pulls
  double-count some rows and silently drop others (caught 2026-06-10 when
  parts quantities literally doubled between runs; fixed in-app v3.15.2).
  Dedupe by webId as belt-and-suspenders.
- **Don't mix `|`-OR terms with AND terms in one query** (`|a,|b,c` semantics
  are murky and changed which rows came back) — keep queries pure-OR or
  pure-AND and filter the rest client-side.
- Bulk pulls: 500/page works fine; `equipmentFinancials` full table = 35
  pages; equipment AVAILABLE_SALE = 4 pages. Very large joined queries can
  504 (e.g. inventory across 7 manufacturerIds with sort) — keep them scoped.
  A nightly Worker-cron snapshot into KV (app downloads one JSON) is the
  likely architecture vs. doing the product/manufacturer joins in the
  browser per boot.

---

## 2d. PARTS inventory probe (2026-06-10 — replaces the Stihl/Kubota On Hand xlsx)

Validated against `Stihl and Kubota On Hand_20260608-063308.xlsx` (3,245
part+division rows; vendor 486 = 815, vendor 660 = 2,430). The file was 2
days old at test time — quantity "drift" rows all showed API lastDateIn/Out
AFTER the file date, i.e. the live feed is simply fresher.

- **Vendor mapping:** xlsx Vendor Code = `manufacturer.internalId`. 486 =
  webId `54436263002` (STIHL WHOLEGOODS). 660 = webId `43518216992`
  (KUB - NON SERIAL) — **but Kubota parts are duplicated across a 7-record
  manufacturer family** (`660`, `650/KUBOTA`, `KUBOTA` 265275971, `KUKBOTA`
  typo 4982188547, `KUBOTA1`, `NEW KUBOTA`, `KUBOTA Z78`).
- **Duplicate-product gotcha:** the same part number exists as several
  product records (one per manufacturer duplicate), and EACH can carry its
  own inventory rows for the same physical stock — most are frozen snapshots,
  one is actively maintained. **Rule (validated): per division, sum bins
  within each product, then keep only the product whose inventory rows have
  the latest dateUpdated. Never sum across duplicate products.**
- **Stihl (486) = bulk pull works:** `inventory?query=product.manufacturerId:
  54436263002` + products by manufacturerId → 827 rows, ~94% exact onHand vs
  the stale file (drift = real activity), reserved 99.4% exact.
- **Kubota (660 checker) = per-part live lookup, NOT bulk:** the desktop's
  vendor scoping isn't reproducible (no vendor field on product; the
  manufacturer-family union pulls the entire 41k-product catalog and 504s).
  Per part: `product?query=productCode:{part}` (all duplicates) →
  `inventory` by `|productId:` ORs → latest-product-wins per division.
  **Validated on 144 sampled parts: 100% found (incl. tires that bulk
  missed), 138/144 onHand exact, 6 drift = post-file sales.**
- **Division:** `stockAreaId` → stockArea.branchId → branch letter.
  Areas: 31011442560+31011442563 = M, 31011442561+31011442562 = S.
- **Quantity mapping:** On Hand = `quantityInStock`, Sales Reservations =
  `quantityAllocatedToCustomer`, Available = inStock − allocated.
- **Gap: Quick Code** (e.g. FS56RC) is not in the API (`product.internalId`
  just repeats productCode). Stihl quick codes also live in the Stihl
  Pricing xlsx the app already loads; assess impact when wiring the 660
  checker (it displays/searches quickCode).
- Test harnesses in `dis-feed-test`: `parts_feed.js` (bulk) +
  `kubota_lookup_check.js` (per-part design validation).

---

## 3. How the app's typeahead worked PRE-v3.14 (historical reference — the
## static flow below is now the FALLBACK path only)

- **`dis` module** (`index.html` ~line 5045, inside `HPE.shared`): loads the static
  "Contact List" XLSX from Drive into in-memory `_contacts`, exposes **synchronous**
  `searchContacts(query, limit)` and `findByCustomerNumber(num)`. Contact record
  shape: `{ name, customerNumber, phone, phoneDisplay, email, city, province, isCompany }`.
- **Loader:** `loadDISContacts()` in the Hub IIFE (~line 9239), called at bootstrap (~6933).
- **Consumer A — quote-builder "New Customer" typeahead:** `onDISSearchInput(rawQ)`
  (~9357) → renders dropdown → `pickDISSearchResult(custNum)` (~9419) →
  `applyDISContactToModal(contact)` (~9329) prefills the form.
- **Consumer B — standalone DIS lookup modal:** `HPE.disLookup` (~9736) + render at
  ~9786, also calls `dis.searchContacts`.
- The token to send to the Worker: the app's access token is `state.token` (auth
  IIFE) / `accessToken` (shell); `drive.gfetch` (~5248) shows the refresh pattern.

---

## 4. Wiring plan — ✅ COMPLETED 2026-06-10 (v3.14.0–v3.14.2, merged to main)

**As built (where the code lives in `index.html`):**
- `HPE.config.disProxyUrl` next to `googleClientId` (~line 4660).
- Live helpers in the **Hub IIFE** next to `onDISSearchInput`:
  `disProxyFetch` (Worker GET via `drive.gfetch` → free silent token-refresh on
  401), `searchDISCustomersLive` (digits → `customerNumber:{q}*`, else
  `customerName:*{q}*`; applies the dis module's `isNoiseRow`),
  `fetchLiveDISDetails` (on-pick: communicationDetail by `addressId` +
  addresses by `webId`), `staticDISSearch` (fallback), debounce 250ms +
  stale-`seq` guard. Exposed cross-module via `HPE.sectionImpl.hub.searchDISLive`
  / `.fetchDISDetails`.
- `HPE.disLookup` (the Used/SL 🔍 modal) is live-first via those hub exports,
  falling back to the old static flow (v3.14.1). Subtitle shows "Live DIS
  Quantum lookup" vs the xlsx filename; footer names the source.
- SL "My Customers" add/edit modal: 🔍 DIS button →
  `S.openDISLookupForCustomerModal()` (v3.14.2).
- Dropdown/footer always indicate source ("Live DIS lookup" / "Offline contact
  list") — that's how you tell which path served results.
- Prefill rules everywhere: **name always overwritten; email/phone/address only
  filled when empty** (never clobber user-typed values).

**The original step-by-step plan (kept for context):**

**Plan:** *(all code steps below DONE 2026-06-10 on branch `dis-live-lookup`)*
0. ~~Worker whitelist + redeploy~~ ✅ deployed `fa874317`.
1. Add a config constant, e.g. `disProxyUrl: 'https://dis-proxy.johnwilliams.workers.dev'` near `googleClientId` (~line 4658).
2. Add an **async** live-search helper (in the `dis` module or alongside the consumers) that calls:
   `GET {disProxyUrl}/dis/customers?query=customerName:*{q}*&size=10&sort=customerName`
   with header `Authorization: 'Bearer ' + state.token`. Map `_embedded.customers` →
   `{ name: r.customerName, customerNumber: r.customerNumber, isCompany: true, active: r.active }`.
   On non-200 return null so the UI can show a graceful message (don't hard-crash the quote builder — handoff rule).
3. Rework **`onDISSearchInput`** to be **debounced (~250ms) + async**, calling the live
   helper instead of `dis.searchContacts`. Render name + `#customerNumber` (show
   phone/email/city only if fetched — see step 4).
4. Rework **`pickDISSearchResult`** to use the live result set (keep the last results
   array keyed by customerNumber) → on pick, fetch phone/email (+city) via the §2a
   chain (`communicationDetail?query=addressId:{mainAddressId}` +
   `addresses?query=webId:{mainAddressId}`) → `applyDISContactToModal`; ensure any
   still-missing fields degrade gracefully (verify `applyDISContactToModal`
   ~9329 doesn't choke on undefined).
5. Decide whether to also switch **Consumer B** (`disLookup` modal) now or leave it on
   the static source for v1 — the handoff wants both eventually; smallest safe step is
   the quote-builder typeahead first.
6. **Auth-expiry handling:** if the Worker returns 401, try one silent token refresh
   (see `auth._silentRefresh` ~4901 / the gfetch refresh ~5254) then retry; else show
   "session expired, refresh".

**Ship checklist (from CLAUDE.md):**
- Work on branch **`dis-live-lookup`** (already created locally on the home PC; recreate on work PC: `git checkout -b dis-live-lookup`).
- **Version bump v3.13.50 → v3.14.0** (minor = feature) across the 3 touchpoints (`<title>`+build comment, topbar pill, `HPE.config.version`/`.build`) + add ONE `CHANGELOG` entry at the top (rep-facing note, e.g. "Customer search now pulls live from DIS").
- `./smoke.sh` must be green (JS syntax, dup-IDs = 6, version consistent).
- Show John the diff; **do not merge to `main` until he's tested** the live lookup in the deployed/preview app (needs login + the Worker).

---

## 5. Environment notes (work PC)

- The work PC already runs `smoke.sh`, so Node + python3 are presumably installed there.
- **No API key needed locally to wire the app** — the app just calls the Worker URL; the key lives only in the Worker secret.
- If you want to **probe DIS directly** from the work PC (optional), set the key as a user env var and read it without printing:
  `[Environment]::SetEnvironmentVariable('DIS_API_KEY','<key>','User')` then in curl use `-H "X-API-Key: $k"` where `$k=[Environment]::GetEnvironmentVariable('DIS_API_KEY','User')`.
- Repo sync is plain git (`git pull` at start, `git push` when done). The home PC has auto-sync hooks; the work PC can too (ask John).

---

## 6. Open questions for DIS / Lauren

1. ~~**Phone & email** — where do they live?~~ **ANSWERED 2026-06-10:** in
   `contact` + `communicationDetail` (singular paths) — see §2a. DIS's entity
   list + query-doc link confirmed it; verified live.
2. ~~Location of the full entity catalog~~ **Mostly answered:** DIS sent the GET-entity
   list (§2b) + the query-language doc. Still nice-to-have: the raw OpenAPI spec
   URL behind their swagger-ui (for per-entity field schemas).
3. **Write scope** of the issued key + is there a **sandbox/test environment**? (Until confirmed: **reads only, never write against production.**)
4. ~~Confirm canonical customer lookup entity/fields~~ **Confirmed** — `customer(s).customerName` is it (list has no other customer-name-bearing entity).
> **Note (2026-06-10):** John prefers figuring things out ourselves over
> asking DIS — only escalate at a true brick wall. q5/q7/q9 were since
> answered by our own testing (see §2c round-2 validation); q6/q8 are
> confirmed walls with workarounds:

5. ~~Unit List Price / Suggested List~~ **ANSWERED OURSELVES:** the desktop
   barely has list prices either (1/717 new!); used suggested-list syncs to
   the API at parity (~50). Not a blocker.
6. **Reserved units — THE one remaining wall (live experiment §2c):**
   EM/ES sale invoices sync only once finalized; the 15 unfinalized reserved
   docs are absent and the equipment record carries no marker. Workaround
   required: occasional xlsx overlay or in-app reservation marking. (If we
   ever DO talk to DIS: ask whether the desktop reserve flow can set
   RESERVED_SALE, which the API supports but their sync never sets — or
   whether draft Unit Sale docs can be exposed.)
7. ~~Replacement value & flooring~~ **BOTH CLOSED:** replacement value unused
   even in the desktop (0/849); **flooring SOLVED via ledgerEntry
   NOTE_BALANCE netting — validated 849/849 exact** (§2c).
8. **Unit Location codes — CONFIRMED WALL:** desktop Location (`S M SC YD HP
   BM LA R`) is separate from Division (= API `branchId`, verified 849/849)
   and is not exposed anywhere. Dead stock is therefore indistinguishable in
   the API. Workaround candidates: in-app admin "hide unit" list, or the
   occasional-xlsx overlay carrying Location. (If asking DIS: can their sync
   populate `equipment.location`, which exists in the schema but is null?)
9. ~~Orphaned "available" records~~ **ANSWERED OURSELVES:** exclude
   `dateUpdated < 2020-01-01` — validated 0 false positives / 0 false
   negatives against the 849-unit ground truth.

---

## 7. Worker source (canonical copy — `dis-proxy-worker/src/worker.js`)

> Deployed as version `cba254b7` (2026-06-10, whitelist v2). Local copies:
> home PC `C:\Users\johnr\dis-proxy-worker\src\worker.js`, work PC
> `C:\Users\johnw\dis-proxy-worker\src\worker.js` (+ `wrangler.toml`). No
> secrets here (the key is a Worker secret; secrets persist across deploys).
> If you edit, update both this block and the deployment.

```js
/**
 * DIS Quantum API proxy — Cloudflare Worker (dependency-free).
 *
 * Purpose: let the HPE Sales Platform (static GitHub Pages app) do live
 * customer/equipment lookups against the DIS Quantum API WITHOUT exposing the
 * API key to the browser and without CORS problems.
 *
 * Auth model (matches the app's existing pattern):
 *   The HPE app authenticates users with Google's OAuth token client (scope:
 *   drive only) and holds a Google *access token*. It already trusts that token
 *   for login by reading Google's USERINFO and checking the email domain. This
 *   Worker does the server-side equivalent, with two checks:
 *     1. tokeninfo  -> aud (or azp) === the HPE OAuth client ID (token minted
 *        for THIS app; tokeninfo always returns aud/azp regardless of scope).
 *     2. userinfo   -> email ends with @hydeparkequipment.ca and email_verified
 *        (the SAME endpoint the app's own login uses — proven to return email
 *        for these drive-scoped tokens, where tokeninfo's email field may not).
 *   The client sends: Authorization: Bearer <access_token>.
 *
 * Confirmed by Task-0 probe (2026-06-09):
 *   - DIS auth header is `X-API-Key` (raw key), NOT `Authorization: Bearer`.
 *   - Response is HAL JSON: records under `_embedded.{entity}[]`.
 *
 * The DIS key lives ONLY as the Worker secret `DIS_API_KEY`. Read-only: only
 * whitelisted GET entities are forwarded. No write methods, ever.
 *
 * Endpoint shape:
 *   GET https://<worker>.workers.dev/dis/{entity}?query=...&page=&size=&sort=
 */

// ─── Config ──────────────────────────────────────────────────────────────────
const DIS_BASE = "https://hy2303.disprism.com/api";
// 2026-06-10 v2: + product, manufacturer, branch, equipmentFinancials,
// ledgerEntry (flooring via NOTE_BALANCE netting), inventory, stockArea —
// for the live inventory feed (units + parts). See DIS_INTEGRATION.md §2c.
const ALLOWED_ENTITIES = new Set([
  "equipment", "customers", "addresses", "contact", "communicationDetail",
  "product", "manufacturer", "branch", "equipmentFinancials", "ledgerEntry",
  "inventory", "stockArea",
]);
const ALLOWED_ORIGIN = "https://hyde-park-equipment.github.io";            // GitHub Pages origin (no CNAME)
const GOOGLE_CLIENT_ID =
  "659141396162-8iilhoicrtpnnpie0m88m8f69lulgg4l.apps.googleusercontent.com"; // HPE app's OAuth client
const ALLOWED_DOMAIN = "hydeparkequipment.ca";
const TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo?access_token=";
const USERINFO_URL = "https://www.googleapis.com/oauth2/v3/userinfo";
// Only these query params are passed through to DIS.
const PASSTHROUGH_PARAMS = ["query", "page", "size", "sort"];

// ─── CORS ────────────────────────────────────────────────────────────────────
function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
    "Access-Control-Allow-Methods": "GET,OPTIONS",
    "Access-Control-Allow-Headers": "Authorization,Content-Type",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}
function json(status, obj) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders(), "Content-Type": "application/json" },
  });
}

// ─── Access-token validation (cached in module scope) ─────────────────────────
const _tokCache = new Map();

async function validateAccessToken(authHeader) {
  if (!authHeader || !authHeader.startsWith("Bearer ")) return false;
  const token = authHeader.slice(7).trim();
  if (!token) return false;

  const now = Date.now();
  const cached = _tokCache.get(token);
  if (cached && now < cached.exp) return cached.ok;

  // Check 1 — tokeninfo: confirm the token was minted for THIS app (aud/azp).
  let ti;
  try {
    const res = await fetch(TOKENINFO_URL + encodeURIComponent(token));
    if (!res.ok) {
      _tokCache.set(token, { ok: false, exp: now + 60000 });
      return false;
    }
    ti = await res.json();
  } catch {
    return false;
  }
  const audOk = ti.aud === GOOGLE_CLIENT_ID || ti.azp === GOOGLE_CLIENT_ID;
  if (!audOk) {
    _tokCache.set(token, { ok: false, exp: now + 60000 });
    return false;
  }

  // Check 2 — userinfo: confirm the user's email domain.
  let ui;
  try {
    const res = await fetch(USERINFO_URL, {
      headers: { Authorization: "Bearer " + token },
    });
    if (!res.ok) {
      _tokCache.set(token, { ok: false, exp: now + 60000 });
      return false;
    }
    ui = await res.json();
  } catch {
    return false;
  }
  const emailOk =
    typeof ui.email === "string" &&
    ui.email.toLowerCase().endsWith("@" + ALLOWED_DOMAIN);
  const verified = ui.email_verified === true || ui.email_verified === "true";
  const ok = emailOk && verified;

  let ttl = 300000;
  if (ti.exp) {
    const ms = parseInt(ti.exp, 10) * 1000 - now;
    if (ms > 0) ttl = Math.min(ttl, ms);
  }
  _tokCache.set(token, { ok, exp: now + (ok ? ttl : 60000) });
  if (_tokCache.size > 2000) {
    const k = _tokCache.keys().next().value;
    if (k !== undefined) _tokCache.delete(k);
  }
  return ok;
}

// ─── Worker ──────────────────────────────────────────────────────────────────
export default {
  async fetch(req, env) {
    if (req.method === "OPTIONS")
      return new Response(null, { status: 204, headers: corsHeaders() });
    if (req.method !== "GET")
      return json(405, { error: "method_not_allowed" });

    const ok = await validateAccessToken(req.headers.get("Authorization"));
    if (!ok) return json(401, { error: "unauthorized" });

    const url = new URL(req.url);
    const entity = url.pathname.replace(/^\/dis\//, "").replace(/\/+$/, "");
    if (!ALLOWED_ENTITIES.has(entity))
      return json(403, { error: "forbidden_entity", entity });

    const out = new URLSearchParams();
    for (const p of PASSTHROUGH_PARAMS) {
      const v = url.searchParams.get(p);
      if (v != null) out.set(p, v);
    }
    const qs = out.toString();
    const target = `${DIS_BASE}/${entity}${qs ? "?" + qs : ""}`;

    let upstream;
    try {
      upstream = await fetch(target, {
        method: "GET",
        headers: { "X-API-Key": env.DIS_API_KEY, Accept: "application/json" },
      });
    } catch {
      return json(502, { error: "upstream_unreachable" });
    }

    const body = await upstream.text();
    return new Response(body, {
      status: upstream.status,
      headers: {
        ...corsHeaders(),
        "Content-Type":
          upstream.headers.get("Content-Type") || "application/json",
      },
    });
  },
};
```

---

## 8. Hard security rules (unchanged)
1. DIS key only as the Worker secret — never in client code, repo, URLs, or logs.
2. **Reads only.** No POST/PUT/PATCH/DELETE against production until DIS confirms write scope + provides a sandbox.
3. Worker is not an open relay — entity whitelist + Google-token gate on every request.
4. If the key is ever exposed anywhere shared, rotate it before go-live.
