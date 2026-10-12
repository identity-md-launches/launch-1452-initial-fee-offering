# Initial Fee Offering (IFO)

A fixed supply ERC-20 for the requested custom token launch. The sole production
contract is [`IFOToken`](src/IFOToken.sol), built on the vendored OpenZeppelin
Contracts v5.1.0 ERC-20 implementation.

| Property | Value |
| --- | --- |
| Solidity contract identifier | `IFOToken` |
| Token name | `Initial Fee Offering` |
| Symbol | `IFO` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor recipient | Immediate deployer, `msg.sender` |
| Constructor value | `0` ETH; constructor is nonpayable |
| Additional production contracts | None |

## Behavior and assumptions

The constructor mints the entire supply once, emitting one
`Transfer(address(0), deployer, 10^27)` event. When a factory deploys the token,
the factory receives all of it. The originating wallet receives no allocation
from the constructor. A direct wallet deployment credits that wallet instead.

The name does not define any extra fee mechanism. With no additional transfer
rules requested, IFO uses ordinary ERC-20 transfers: every successful transfer
delivers its full amount, with no taxes, burns, rebases, wallet limits or trading
switches. The launch pool's 1.25% fee is external to the token. No launch addresses
or exemptions are needed in this contract.

There is no owner, minter role, pause, blacklist, seizure, upgrade, external mint
or external burn function. The deployer has the same token rights as any holder
after construction. The supply remains `10^27` for the life of this deployment.
The constructor and token operations make no external calls or recipient
callbacks, require no chain services, and can deploy on an otherwise empty chain.

`transfer`, `approve` and `transferFrom` return `true` on success and revert with
OpenZeppelin ERC-20 custom errors on failure. Zero-value transfers between valid
addresses are supported and emit `Transfer`. Transfers to the zero address and
approvals to the zero spender are rejected. Self-transfers preserve balances.
Approvals replace the existing allowance; zero revokes it. Finite allowances
decrease on `transferFrom`, including self-transfers. A maximum `uint256`
allowance is treated as unlimited and does not decrease. As in OpenZeppelin v5,
`approve` emits `Approval`; spending an allowance does not emit another
`Approval` event. Integrations should query `allowance` for the current value.

## Build and test

From the repository root, with Foundry and Solidity 0.8.26 installed:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity `0.8.26`, Cancun EVM output, optimizer runs `200`,
and `bytecode_hash = "none"`. No FFI or filesystem permissions are enabled.
All imported Solidity dependencies and licenses are ordinary files under `lib/`;
no package manager, submodule, RPC, API key or network fetch is needed to build
or test once the pinned compiler and Foundry are available. Dependency versions,
immutable source commits and SHA-256 checksums are in
[`DEPENDENCIES.json`](DEPENDENCIES.json).

The tests cover metadata, constructor minting and its event, wallet and CREATE2
factory deployment, exact launch allocation/claim/pool token movements,
transfers, approvals, events, zero and maximum amounts, self-transfers, failure
atomicity, unauthorized spending, rejected privileged selectors, and runtime
deployment constraints. Fuzz tests cover transfer conservation and allowance
limits. A stateful invariant compares balances and allowances with an independent
ledger over sequences of transfers, approvals, delegated transfers and rejected
overspends. Default settings run each fuzz test 512 times and the invariant for
256 sequences of 64 operations. Tests use isolated local state and no environment
variables, network forks or filesystem access.

The local launch test models only ERC-20 movements. The supplied protected
harness separately tests actual Uniswap v4 initialization, liquidity seeding and
swaps using the launch system's contracts and resolved manifest. Those external
contracts and deployment inputs are not part of this token repository, so that
harness is not included in the local test suite.

## Deployment and launch responsibilities

Deploy the creation bytecode for `src/IFOToken.sol:IFOToken` directly, with no
constructor arguments, no value, no linked libraries and no initializer or
proxy. The artifact is `out/IFOToken.sol/IFOToken.json`. The launch system's
`ProjectFactory.launchCustom` creates the token and receives the entire supply.
No separate deployment script or configuration address is necessary. Contracts
under `test/` are test helpers and must not be included as launch applications.

The manifest step owns `launch.json`; this repository deliberately does not
provide one. Its token entry should identify `IFOToken`, the metadata and supply
above, and an empty constructor argument list. The following launch parameters
come from the assignment and are handled by that external step, not by IFO:

| Launch setting | Assignment value |
| --- | --- |
| Chain | Ethereum, chain ID `1` |
| Paired token | IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, 18 decimals |
| Pool fee | `12500` (1.25%) |
| Tick spacing | `60` |
| Initial price provenance | `79228162514264337593543950336` |
| Pool allocation | `8000` basis points of the whole supply (800,000,000 IFO) |
| Initial market cap | `2500000000000000000000` IMD smallest units (2,500 IMD) |
| Swarm allocation | Factory distributes 10% (100,000,000 IFO) |
| Remainder recipient | `0x6bf192ebef135e0f645e99d59d9bf44e7711606c` |
| Remainder allocation | 10% (100,000,000 IFO) |

The factory distributes the swarm share, seeds the pool and forwards the
remainder. IFO itself allocates none of those shares during construction. The
actual opening price is derived by the launch system from market cap, supply
and currency address ordering; the listed price provenance is not a token-side
initialization action.

## After launch

IFO needs no setters, activation transaction, privileged operator, keeper or
ongoing configuration. The launch operator is responsible for verifying the
deployed bytecode/source and metadata, confirming the initial mint and exact
factory distributions, and running the independent launch admission checks.
Separate adversarial review remains a release responsibility; the local tests
and source review do not constitute an independent security audit.

Holders control their transfers and allowances. Approve only trusted spenders
for needed amounts and revoke unused approvals. When replacing an existing
nonzero allowance, first revoke it and confirm that transaction, then approve
the new amount; ordinary ERC-20 approval ordering risks still apply. Revocation
cannot undo spending already executed.

There is no recovery function for mistakenly sent IFO, other ERC-20 tokens or
forced ETH. Ordinary direct ETH payments revert. A token transfer does not check
whether the recipient can return tokens, so holders and integrations must verify
recipient addresses. No transactions are broadcast by the supplied project.

## Dependency provenance

- OpenZeppelin Contracts v5.1.0, commit
  `69c8def5f222ff96f2b5beff05dfba996368aa79`: the unmodified ERC-20 import closure
  and MIT license in `lib/openzeppelin-contracts/`.
- forge-std v1.9.7, commit `77041d2ce690e692d6e03cc812b57d1ddaa4d505`:
  unmodified Solidity sources and MIT/Apache licenses in `lib/forge-std/`, used
  only by tests.

Dependencies were fetched from their official GitHub repositories at those
commits. The source and archive digests in `DEPENDENCIES.json` allow the vendored
contents to be checked without installing dependencies again.
