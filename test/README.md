# IFO token tests

Run from the repository root with the vendored dependencies:

```sh
forge build
forge test
```

All tests deploy the real `src/IFOToken.sol` locally. They need no RPC, environment
variables, external services, or additional dependencies.

| Suite | Properties checked |
| --- | --- |
| `IFOToken.t.sol` | Exact metadata and constructor allocation, one mint event, EOA and factory deployment, fee-free token movements, ERC-20 events, transfer and approval boundaries, rejected administrative calls, and deployment constraints. |
| `IFOToken.adversarial.t.sol` | Approval isolation between owners and spenders; replacement and revocation of infinite approvals; exhaustion across repeated spending; returned tokens do not restore spent authorization; self-transfer accounting; and exact errors with unchanged balances and allowances on failure. |
| `IFOToken.invariant.t.sol` | Fixed supply, balance conservation, balances and allowances matching an independent ledger, unchanged metadata, and continued holder transferability after random call sequences. |

The unit cases pin zero, one smallest unit, the full supply, `uint256.max - 1`,
and `uint256.max`. Fuzz tests use 1,000 runs per property, with bounds derived
from balances or allowance limits. Approval inputs also exercise the full
`uint256` range.

The invariant uses four actors and nine targeted handler actions: transfers,
approvals, delegated transfers, balance overspends, allowance overruns, approved
balance overspends, zero recipients, zero spenders, and revocations. Setup funds
all actors and creates several approvals through real token calls. Expected
balances and allowances come from the handler's inputs and successful actions;
they are never refreshed from the token's reported state.

Each of 256 sequences runs 128 random calls. Invalid operations must revert
with the expected custom error, and their effects must leave the independent
ledger intact. Unexpected handler reverts fail the campaign. After each sequence,
every actor transfers its entire balance to another actor and receives it back;
the complete ledger is checked after each round trip. Run counts and depth are
specified inline in the Solidity tests.

The local launch-flow test checks ERC-20 distributions and transfers. Actual
Uniswap v4 seeding and swaps belong to the supplied protected launch harness,
which requires external launch contracts and resolved deployment inputs absent
from this token repository.
