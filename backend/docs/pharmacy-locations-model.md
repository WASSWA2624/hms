# Pharmacy locations

HOSSPI runs more than one pharmacy inside a facility. The two that matter today
are the **Main Pharmacy**, which buys from suppliers and supplies everyone else,
and the **Hospital Pharmacy**, which fills clinical prescriptions. They are two
rows of `pharmacy_location`, not two modules, so inventory, pricing and
permissions all key on the same `pharmacy_location_id` and a Branch, Theatre or
Ward pharmacy is a new row rather than new code.

```
Shared medicine catalog (drug)
        |
        +-- Main Pharmacy (pharmacy_location, kind = MAIN)
        |       procurement, suppliers, batches/expiry, landed cost
        |       walk-in sales, supplies the hospital pharmacy
        |
        +-- Hospital Pharmacy (pharmacy_location, kind = HOSPITAL)
                hospital prescriptions, dispensing, own stock and prices
                orders stock from Main
```

## Separate stock

`inventory_stock` carries `pharmacy_location_id`. Two pharmacies in the same
facility hold two rows for the same catalog item, so their balances never pool:

| inventory_item | pharmacy_location | quantity |
| -------------- | ----------------- | -------: |
| Paracetamol    | Main Pharmacy     |    1,000 |
| Paracetamol    | Hospital Pharmacy |      120 |

`stock_movement`, `stock_adjustment`, `drug_batch` and `pharmacy_storage_room`
carry the same column, so history, batch records and storage stay with the
pharmacy that owns them.

Stock moves between pharmacies through exactly two writers,
`issueStockToLocation` and `receiveStockAtLocation` in
`src/lib/pharmacy/pharmacy-location-stock.js`. They are the two legs of one
transfer and share a `transfer_group_id`; between them the quantity is in
transit and belongs to neither balance.

## Permissions

`pharmacy_location_user` grants a user `VIEW`, `DISPENSE` or `MANAGE` on one
pharmacy. `src/lib/pharmacy/pharmacy-location-access.js` holds every guard:

* `assertLocationAccess` - may this user act here, at this level?
* `assertProcurementAccess` - additionally requires `handles_procurement`, so a
  Hospital Pharmacy user cannot reach Main Pharmacy suppliers, purchases,
  batches, expiry records, costs or stock adjustments even if they somehow hold
  a grant on it.
* `assertStockVisibility` - a pharmacy may always read the availability of the
  pharmacy that supplies it, without a grant.

Tenant, facility and platform admins act everywhere without an explicit grant.

Cross-pharmacy reads return `SUPPLIER_STOCK_PUBLIC_SELECT` only: quantity,
reorder level, timestamps. Purchase cost, supplier identity and batch economics
are never included.

## Prescription routing

`src/lib/pharmacy/pharmacy-order-routing.js` decides which pharmacy fills a
prescription, from where it was raised rather than from who is looking at it:

```
Hospital consultation -> origin HOSPITAL -> handles_prescriptions -> Hospital Pharmacy
Walk-in / counter sale -> origin WALK_IN  -> handles_walk_in       -> Main Pharmacy
```

`pharmacy_order.origin` and `pharmacy_order.pharmacy_location_id` are set at
creation. `assertOrderDispensableAt` then refuses a dispense attempt from any
other pharmacy, so a hospital prescription cannot be filled out of Main Pharmacy
stock. An order with no pharmacy recorded (pre-migration, or a facility that has
not configured locations) dispenses wherever the user is.

## Stock orders

`pharmacy_stock_order` is the Hospital -> Main request:

```
create -> submit -> review (approve / partially approve / reject)
       -> issue  -> receive
```

**The order never changes stock.** Creating, submitting, approving and rejecting
it only record intent. Inventory changes exactly twice: `issueStockOrder` takes
the quantity out of the supplying pharmacy, and `receiveStockOrder` brings it
into the requesting one. Receiving less than was issued leaves the order
`PARTIALLY_RECEIVED` so the shortfall stays visible rather than being written
off. Once stock has been issued the order can no longer be cancelled - the
transfer must be received, or reversed as its own movement, so the two legs
always balance.

Sides are enforced separately: only the requesting pharmacy may create, submit
and receive; only the supplying pharmacy may review and issue.

## Pricing

`pharmacy_location_price` gives each pharmacy its own row per drug, with two
independent columns:

| pharmacy          | sell_price          | supply_price          |
| ----------------- | ------------------- | --------------------- |
| Main Pharmacy     | 300 (walk-in)       | 200 (to Hospital)     |
| Hospital Pharmacy | 350 (dispensing)    | - (supplies nobody)   |

`src/lib/pharmacy/pharmacy-location-pricing.js` never falls back from one
context to the other. A transfer is priced at the supplier's `supply_price`; if
none is configured, `requireSupplyPrice` fails rather than quietly charging the
walk-in price. Because the two are different columns on different rows, editing
a walk-in price cannot move a supply price or another pharmacy's dispensing
price.

On receipt, the supply price becomes the receiving pharmacy's
`acquisition_cost` - what it actually paid, not what the supplier charges the
public and not its own selling price.

The legacy `drug.unit_price` / `drug.transfer_unit_price` / `drug.buy_unit_price`
columns remain the tenant-wide default for a pharmacy that has not set its own
price, so a facility that never configures per-location pricing keeps working.

## Migrations

* `20260920120000_pharmacy_locations` - tables and columns.
* `20260920130000_pharmacy_locations_backfill` - gives every facility that
  already runs a pharmacy a Main and a Hospital location, attaches existing
  stock, batches, storage and history to the Hospital Pharmacy (that is what the
  balances were being used for), routes existing prescriptions, and seeds
  per-location prices from the drug columns. Re-runnable.

The Main Pharmacy starts empty on purpose: from here on, stock reaches the
Hospital Pharmacy through a stock order and its transfer legs, never by editing
a balance directly.

## API

| Endpoint                                        | Purpose                                    |
| ----------------------------------------------- | ------------------------------------------ |
| `GET /api/v1/pharmacy-locations`                | Pharmacies the caller can see, with access  |
| `GET /api/v1/pharmacy-locations/:id/availability` | Own stock beside supplier availability    |
| `GET|PUT /api/v1/pharmacy-locations/:id/prices` | This pharmacy's own prices                 |
| `GET|PUT|DELETE .../:id/access[/:userId]`       | Who may act in this pharmacy               |
| `GET|POST /api/v1/pharmacy-stock-orders`        | Stock order queues and creation            |
| `POST .../:id/{submit,review,issue,receive,cancel}` | The workflow steps                     |
