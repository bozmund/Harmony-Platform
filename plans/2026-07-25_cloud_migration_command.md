# Cloud migration command fix

1. Configure the `cloud-migrate` Compose service to run the Cloud API's `migrate` command instead of starting the web server.
2. Validate the rendered Compose configuration.
3. Review the working tree, then commit and push only after separate approvals.
