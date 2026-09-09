# Agent guidance

Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing this module and
[docs/parity.md](docs/parity.md) before changing runner infrastructure.

## Deployment compatibility

This module implements the supported Fargate enterprise private-ECR runner
deployment. Use the public release manifest and CloudFormation template for the
configured `runner_template_build_version` as versioned references; the links
and intentional differences are documented in [docs/parity.md](docs/parity.md).

- For changes to AWS permissions, task definitions, bootstrap commands, network
  rules, storage, configuration, or release defaults, review the corresponding
  CloudFormation behavior and runtime requirement. Record the reference release
  and compatibility evidence in the PR.
- A runner image/version bump does not update IAM or other infrastructure.
  Check permissions on the role actually used by the operation, including
  resource scopes, conditions, trust, boundaries, and explicit denies.
- Add positive and negative regression coverage for each changed contract.
  IAM tests must inspect real policy statements, not mocked empty JSON. Test
  rendered shell commands, not only matching source strings.
- Preserve intentional differences documented in `docs/parity.md`. Do not copy
  an older template's broader grants or weaken tests merely to obtain parity.
  Explain any new exception and request maintainer review.
- If validating a change requires non-public implementation context, ask a
  maintainer to verify the counterpart. Report it as unverified until then;
  public contributors and CI must not require access to a private repository.
- Keep resource addresses stable unless a migration is explicitly required.
  Review a deployment plan before applying an upgrade; tests are not permission
  to modify a live AWS account or publish a release.

## Public repository boundary

Treat every commit, PR description, comment, test fixture, artifact, and CI log
as public. Use synthetic account IDs, domains, and credentials in tests.

- Do not copy private source, private PR/issue links, customer logs, identifiers,
  credentials, incident reports, or unreleased security findings into this repo.
  Keep cross-references to private companion work on the private side.
- Do not automatically publish generated private templates or audit reports.
  Public fixtures must come from approved public artifacts or synthetic cases.
- Run public PR checks without AWS credentials or private-repo tokens. Never
  execute untrusted PR code in a privileged workflow to obtain cross-repo access.

## Validation

Run the checks in `CONTRIBUTING.md`, including root/submodule tests and example
validation. After `terraform init -backend=false`, also run:

```bash
bash scripts/check-parity-contract.sh
bash scripts/test-metrics-audit-sync.sh
```

Record the exact module commit and runner release used for live validation.
Do not claim a mutable `main` reference proves a release candidate was tested.
