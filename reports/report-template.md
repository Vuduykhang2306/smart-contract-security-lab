# Security Assessment: <PROJECT>

**Target** `<repo>@<commit hash>`
**Auditor** <name>
**Review period** <dates>
**Report version** <n>

## 1. Scope

| File | nSLOC | In scope |
|---|---:|:--:|
| | | |

Out of scope: <list, with the behaviour assumed of each>.
Compiler: <version, optimizer settings>.

## 2. Methodology

Threat model, manual review against a checklist, static analysis, a proof of
concept for each finding, remediation and retest. See `docs/audit-process.md`.

## 3. Severity classification

Severity is `impact x likelihood`.

| | Low likelihood | Medium likelihood | High likelihood |
|---|---|---|---|
| **High impact** | Medium | High | High |
| **Medium impact** | Low | Medium | Medium |
| **Low impact** | Low | Low | Low |

## 4. Findings

| ID | Severity | Title | Status |
|---|---|---|---|
| | | | |

### <ID>: <title>

**Severity** <level> (<impact>, <likelihood>) · **Status** <Open / Fixed / Acknowledged>
**Location** `<file>:<lines>`

#### Description
<What the code does, with the relevant snippet. Explain how the bug works, not only which class it belongs to.>

#### Impact
<Who loses what, and under what conditions. State the upper bound on the loss.>

#### Proof of concept
`test/<file>`
```
forge test --match-contract <ID> -vv
```
<What the test shows.>

#### Recommendation
<The fix, and why this fix over the alternatives.>

#### Remediation
<What the client changed, and the retest that proves it.>

## 5. Static analysis

| Lint | Location | Outcome |
|---|---|---|

## 6. Notes on what this report does not cover

## 7. Reproducing this report
