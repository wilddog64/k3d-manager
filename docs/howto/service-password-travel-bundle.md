# Service passwords while travelling

Install `age` on the hub and laptop. On the laptop, run `make password-bundle-enroll` and copy its public key. On the hub, run `make password-bundle-add-laptop NAME=<laptop> KEY=<public-key>` after the install dependency in the plan is fixed. Alternatively, run the three steps manually: `make password-bundle-add-recipient NAME=<laptop> KEY=<public-key>`, `make password-bundle-publish FORCE=1`, and `make password-bundle-install`. The schedule publishes every 15 minutes when passwords change.

The default delivery folder is iCloud Drive's `k3dm/password-bundle` folder. Set `K3DM_PASSWORD_BUNDLE_DIR` on both machines to use another shared folder outside a git work tree. On the laptop, run `make password-bundle-show`; it reports when the bundle was generated and warns when it is older than 24 hours.

If a laptop is lost, run `make password-bundle-remove-recipient NAME=<laptop>` on the hub. This immediately republishes for the remaining recipients. The removed laptop can still read bundles it already downloaded, so rotate the passwords after losing it. Re-enrolling with `FORCE=1` replaces the identity and makes older bundles unreadable by that laptop; add its new public key on the hub and publish with `FORCE=1`.
