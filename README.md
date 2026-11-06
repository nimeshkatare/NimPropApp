# NimPropApp — Salesforce Property Management

This repository contains the retrieved Salesforce metadata for the NimProp property-management application.

## Repository structure

- `Nimprop/` — retrieved Metadata API package, including its `package.xml`. Treat this as the canonical retrieved metadata input.
- `force-app/main/default/` — Salesforce DX source format generated from `Nimprop/` by GitHub Actions.
- `sfdx-project.json` — Salesforce DX project configuration.

## Automated source conversion

The workflow **Convert Metadata API to Salesforce DX** runs when metadata under `Nimprop/` changes on `main`, and can also be started manually from the Actions tab.

It installs Salesforce CLI, converts the components listed in `Nimprop/package.xml`, checks that the expected source folders were generated, and commits the generated `force-app/` files to `main`.

Make changes to the retrieved metadata in `Nimprop/`. The workflow regenerates `force-app/`; avoid making independent edits only in the generated folder.

The workflow checks conversion and folder output. It does **not** authenticate to a Salesforce org, run Apex tests, or confirm that the package deploys successfully.

## Deploy to a Salesforce org

1. Install Salesforce CLI.
2. Authenticate to the intended org:

   ```bash
   sf org login web --alias NimPropTarget --instance-url https://login.salesforce.com
   ```

   For a sandbox, use `https://test.salesforce.com`.

3. After the GitHub Actions conversion has completed and `force-app/main/default/` exists, deploy:

   ```bash
   sf project deploy start --source-dir force-app/main/default --target-org NimPropTarget --test-level RunLocalTests
   ```

Use an appropriate test level for the target org and release process. Review the deployment preview and target-org dependencies before deploying.

## Known target-org dependencies to verify

The retrieved package references configuration or components that are not declared in the current `Nimprop/package.xml`, including the `Geocoding_API` Named Credential and the `Property_Record_Page` / `PropertyCreateOverride` references in `Property__c.object`. Confirm that these dependencies exist in the destination org or retrieve and add them before expecting a complete deployment.

## Current delivery status

- Metadata API files are committed in `Nimprop/`.
- Salesforce DX conversion is automated by GitHub Actions.
- A successful conversion is not the same as a successful org deployment; deployment must still be validated against the intended Salesforce org.
