# debug/ — NEVER SHIPPED

Nothing in this directory is applied by `scripts/openmanet_setup.sh` / `scripts/build-board.sh` (they only
apply `patches/<board>/`). These patches exist to build **test-only** modules.

| file | what | built by | used by |
|---|---|---|---|
| `990-DEBUG-fi-263.patch` | mm6108 driver fault injection for winson3QQ/Batman#263: one-shot module params that hold a command after its page write / after tx_complete, or drop it after writing, filtered by message_id; plus a command-queue counter check | `scripts/build-debug-mm6108-fi.sh <board> [stock]` → `$OUT_ROOT/<version>/<board>/debug/` | Batman `scripts/daily-validation.sh` suite `halow-fi-263` (`DV_T263_KO`), `scripts/node/halow-fi-263.sh` |

The `stock` variant (without patch 023) panics a node on the first injected command — it is the negative
control that proves the test still reproduces the field Oops. Run it only on a bench node.
