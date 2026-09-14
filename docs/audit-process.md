# Audit process

The sequence I follow on every contract. It is deliberately boring: the point is
that nothing gets skipped because a contract "looks simple".

## 0. Before reading any code

- Get the exact commit hash. Review a frozen tree, never a moving branch.
- Write down the scope — files in, files out, and why. Dependencies pulled in
  from `lib/` are out of scope unless the client pays for them, but their
  *assumed behaviour* goes in the report (see the router assumption in
  `reports/2026-09_MemeTax_audit-report.md`, section 1).
- Read whatever documentation exists, then write down what the contract is
  *supposed* to do in my own words. Differences between that sentence and the
  code are where findings live.

## 1. Threat model

List the actors and, for each, the thing they must not be able to do:

| Actor | Must not be able to |
|---|---|
| Owner / deployer | Take user funds; permanently prevent an exit |
| Arbitrary caller | Change any state that is not theirs |
| Holder | Pay less than the advertised fee; move more than they own |
| LP / pair | Break accounting by being treated as an ordinary holder |
| External contract (router, oracle) | Re-enter and observe a half-updated state |

For a token the two questions that find most bugs are:

1. **Can a holder be stopped from selling?** Blacklists, tax ceilings, wallet
   limits, swap-path reverts, paused flags.
2. **Can value leave along a path nobody intended?** Mint functions, fee
   recipients, rescue functions, dividend pools, allowances.

## 2. Manual pass

Function by function, in this order — cheapest checks first:

1. **Access control.** Enumerate every `external` and `public` state-changing
   function. Write the expected caller next to each *before* looking at the
   modifiers, then compare. This catches the missing-modifier class, which a
   linter cannot see because the defect is an absence.
2. **Checks-Effects-Interactions.** Any function that makes an external call:
   is every state write above the call? Is there a guard?
3. **Arithmetic.** Operation order (multiply before divide), rounding direction
   — does it round in the protocol's favour or the user's? — and unit
   consistency (wei vs token vs basis points).
4. **External calls.** Return value checked? Low-level `call` or a safe wrapper?
   What happens if the callee reverts, returns garbage, or consumes all gas?
5. **Bounds.** Every setter that takes a number: what does 0 do, what does
   `type(uint256).max` do?
6. **Events.** Does every privileged state change emit one?

The per-file checklist I work from is [`checklist-erc20.md`](checklist-erc20.md).

## 3. Static analysis

Run the tools, then verify every hit by hand. Tools are for coverage, not for
conclusions — and their silence proves nothing.

```bash
forge lint
slither . --exclude-dependencies
myth analyze src/Target.sol --solv 0.8.24
```

Record what was dismissed and why. A report that lists only confirmed findings
hides the fact that the tool output was read at all.

## 4. Proof of concept

Every accepted finding gets a Foundry test that fails on the vulnerable contract
before it gets written up. This is the step that separates a real finding from a
plausible-sounding one, and it is where roughly half of my initial suspicions
die.

Naming: one file per finding, `<ID>_<ShortName>.t.sol`, so
`forge test --match-contract H01` shows exactly one finding.

## 5. Severity

`impact x likelihood`, using the matrix in the report. Two rules I hold to:

- Rate centralisation risk by what it costs the holder who cannot exit, not by
  whether the team seems trustworthy.
- If the impact is severe but a precondition is unlikely, lower the severity and
  say so explicitly in the finding. Do not inflate; an inflated High makes the
  real Highs cheaper.

## 6. Report

Per finding: location with line numbers, description, impact, runnable PoC with
the command to run it, recommendation, and — after the fix — remediation status.
Explain *why* the fix works, not just what changed.

## 7. Retest

Replay every PoC against the patched contract and assert it now fails. Check the
diff for changes outside the agreed fixes; a patch that also refactors something
unrelated needs its own review pass.

`test/Retest_Fixed.t.sol` is the worked example.
