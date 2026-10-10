# Audit process

The steps I follow on every contract. It's boring on purpose, so that nothing
gets skipped because a contract "looks simple".

## 0. Before reading any code

- Get the exact commit hash. Review a frozen tree, never a branch that is still
  moving.
- Write down the scope: which files are in, which are out, and why.
  Dependencies pulled in from `lib/` are out of scope unless the client pays
  for them, but what I assume about how they behave goes in the report (see the
  router assumption in `reports/2026-09_MemeTax_audit-report.md`, section 1).
- Read whatever documentation exists, then write down in my own words what the
  contract is supposed to do. Findings usually sit where that description and
  the code disagree.

## 1. Threat model

List the actors, and for each one, what they must not be able to do:

| Actor | Must not be able to |
|---|---|
| Owner / deployer | Take user funds; permanently prevent an exit |
| Arbitrary caller | Change any state that is not theirs |
| Holder | Pay less than the advertised fee; move more than they own |
| LP / pair | Break accounting by being treated as an ordinary holder |
| External contract (router, oracle) | Re-enter and observe a half-updated state |

For a token, two questions find most bugs:

1. Can a holder be stopped from selling? Blacklists, tax ceilings, wallet
   limits, swap-path reverts, paused flags.
2. Can value leave along a path nobody intended? Mint functions, fee
   recipients, rescue functions, dividend pools, allowances.

## 2. Manual pass

Function by function, in this order, cheapest checks first:

1. Access control. List every `external` and `public` function that changes
   state. Write the expected caller next to each one before looking at the
   modifiers, then compare. This catches missing modifiers, which a linter
   can't see because there is nothing in the code to flag.
2. Checks-Effects-Interactions. For any function that makes an external call:
   is every state write above the call? Is there a guard?
3. Arithmetic. Order of operations (multiply before divide), rounding direction
   (in the protocol's favour or the user's?), and consistent units (wei vs
   token vs basis points).
4. External calls. Is the return value checked? Low-level `call` or a safe
   wrapper? What happens if the callee reverts, returns garbage, or uses up all
   the gas?
5. Bounds. For every setter that takes a number: what does 0 do, and what does
   `type(uint256).max` do?
6. Events. Does every privileged state change emit one?

The checklist I work through for each file is [`checklist-erc20.md`](checklist-erc20.md).

## 3. Static analysis

Run the tools, then check every hit by hand. I use them for coverage and don't
take their output as conclusions. When a tool finds nothing, that doesn't
prove anything either.

```bash
forge lint
slither . --exclude-dependencies
myth analyze src/Target.sol --solv 0.8.24
```

Write down what was dismissed and why. If a report only lists confirmed
findings, a reader can't tell whether anyone read the tool output at all.

## 4. Proof of concept

Every accepted finding gets a Foundry test that fails on the vulnerable
contract before it's written up. This step is what separates a real finding
from one that only sounds plausible, and it's where about half of my first
suspicions get dropped.

Naming: one file per finding, `<ID>_<ShortName>.t.sol`, so
`forge test --match-contract H01` shows exactly one finding.

## 5. Severity

`impact x likelihood`, using the matrix in the report. Two rules I stick to:

- Rate centralisation risk by what it costs a holder who can't exit, not by
  whether the team seems trustworthy.
- If the impact is severe but a precondition is unlikely, lower the severity
  and say so in the finding. Don't inflate. An inflated High makes the real
  Highs count for less.

## 6. Report

For each finding: location with line numbers, description, impact, a runnable
PoC with the command to run it, a recommendation, and, once it's fixed, the
remediation status. Explain why the fix works as well as what changed.

## 7. Retest

Run every PoC again against the patched contract and assert that the exploit
no longer works. Check the diff for changes outside the agreed fixes. A patch
that also refactors something unrelated needs its own review pass.

`test/Retest_Fixed.t.sol` is the worked example.
