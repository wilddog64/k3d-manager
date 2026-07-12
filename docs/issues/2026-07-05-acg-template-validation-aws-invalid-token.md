# 2026-07-05 — ACG template validation AWS token invalid; used cfn-lint fallback

## What was tested / attempted

Required gate for `docs/bugs/v1.14.0-bugfix-acg-tunnel-mode-autoselect.md`:

```bash
aws cloudformation validate-template --template-body file://scripts/etc/acg-cluster.yaml
```

Follow-up checks:

```bash
aws sts get-caller-identity
PYTHONPATH=/private/tmp/cfnlint /private/tmp/cfnlint/bin/cfn-lint scripts/etc/acg-cluster.yaml
PYTHONPATH=/private/tmp/cfnlint /private/tmp/cfnlint/bin/cfn-lint /private/tmp/acg-cluster-head.yaml
PYTHONPATH=/private/tmp/cfnlint /private/tmp/cfnlint/bin/cfn-lint --non-zero-exit-code error scripts/etc/acg-cluster.yaml
```

## Actual output

`aws cloudformation validate-template --template-body file://scripts/etc/acg-cluster.yaml`

```text
aws: [ERROR]: Could not connect to the endpoint URL: "https://cloudformation.us-west-2.amazonaws.com/"
```

Re-run outside sandbox:

```text
aws: [ERROR]: An error occurred (InvalidClientTokenId) when calling the ValidateTemplate operation: The security token included in the request is invalid.
```

`aws sts get-caller-identity`

```text
aws: [ERROR]: An error occurred (InvalidClientTokenId) when calling the GetCallerIdentity operation: The security token included in the request is invalid.
```

`PYTHONPATH=/private/tmp/cfnlint /private/tmp/cfnlint/bin/cfn-lint scripts/etc/acg-cluster.yaml`

```text
W2506 'String' is not one of ['AWS::EC2::Image::Id', 'AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>']
scripts/etc/acg-cluster.yaml:13:5

W3687 ['FromPort', 'ToPort'] are ignored when using 'IpProtocol' value '-1'
scripts/etc/acg-cluster.yaml:117:11
```

Baseline on unmodified `HEAD` template:

```text
W2506 'String' is not one of ['AWS::EC2::Image::Id', 'AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>']
/private/tmp/acg-cluster-head.yaml:13:5

W3687 ['FromPort', 'ToPort'] are ignored when using 'IpProtocol' value '-1'
/private/tmp/acg-cluster-head.yaml:101:11
```

Error-only confirmation:

```text
W2506 'String' is not one of ['AWS::EC2::Image::Id', 'AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>']
scripts/etc/acg-cluster.yaml:13:5

W3687 ['FromPort', 'ToPort'] are ignored when using 'IpProtocol' value '-1'
scripts/etc/acg-cluster.yaml:117:11
```

## Root cause

The local AWS session was invalid at validation time (`InvalidClientTokenId`), so
the direct CloudFormation API gate could not be executed successfully even with
network access. The template itself was still locally lintable with `cfn-lint`.

## Recommended follow-up

1. Refresh or replace the local AWS credentials before relying on direct `aws cloudformation validate-template` gates.
2. Keep using `cfn-lint` as the fallback validator when AWS auth is unavailable; it confirmed this change introduced no new template errors.
