# Configuring SSL Trust for jenkins-cli

This guide explains how to configure Java's truststore to properly validate SSL certificates when using jenkins-cli to connect to a Jenkins instance secured with Vault-issued certificates.

## Background

When Jenkins is deployed with Vault PKI, it uses self-signed certificates issued by Vault's internal Certificate Authority (CA). By default, Java does not trust this CA, resulting in SSL handshake failures when using jenkins-cli:

```
javax.net.ssl.SSLHandshakeException: unable to find valid certification path to requested target
```

## Solution Overview

The solution involves importing Vault's CA certificate into Java's truststore so that Java recognizes and trusts certificates signed by Vault.

## Prerequisites

- Jenkins deployed with Vault PKI enabled
- `kubectl` access to the Vault pod
- Java/JDK installed on your workstation
- `keytool` command available (included with JDK)

## Step-by-Step Instructions

### 1. Extract the Vault CA Certificate

Extract the CA certificate from Vault and save it to a local file:

```bash
kubectl -n vault exec vault-0 -- vault read -field=certificate pki/cert/ca > vault-ca.crt
```

Verify the certificate was extracted successfully:

```bash
openssl x509 -in vault-ca.crt -text -noout | head -20
```

### 2. Locate Your Java Truststore

Find your Java installation directory:

```bash
java -XshowSettings:properties -version 2>&1 | grep "java.home"
```

This will output something like:
```
java.home = /home/linuxbrew/.linuxbrew/Cellar/openjdk/25.0.1/libexec
```

The cacerts truststore is typically located at:
```
${java.home}/lib/security/cacerts
```

For the example above:
```
/home/linuxbrew/.linuxbrew/Cellar/openjdk/25.0.1/libexec/lib/security/cacerts
```

### 3. Import the CA Certificate into Java Truststore

Import the Vault CA certificate using `keytool`:

```bash
keytool -importcert \
  -cacerts \
  -storepass changeit \
  -alias vault-k3d-ca \
  -file vault-ca.crt \
  -noprompt
```

**Parameters explained:**
- `-cacerts`: Use the system-wide CA certificates truststore
- `-storepass changeit`: Default password for Java cacerts (can be changed)
- `-alias vault-k3d-ca`: Unique alias for this certificate
- `-file vault-ca.crt`: Path to the CA certificate file
- `-noprompt`: Skip interactive confirmation

You should see:
```
Certificate was added to keystore
```

### 4. Verify the Certificate Import

List certificates in the truststore to confirm the import:

```bash
keytool -list -cacerts -storepass changeit -alias vault-k3d-ca
```

This should display the certificate details without errors.

### 5. Test jenkins-cli Without Certificate Bypass

Now you can use jenkins-cli without the `-noCertificateCheck` flag:

```bash
java -jar ~/.local/bin/jenkins-cli.jar \
  -s https://jenkins.dev.local.me \
  -auth username:password \
  version
```

Test authentication:

```bash
java -jar ~/.local/bin/jenkins-cli.jar \
  -s https://jenkins.dev.local.me \
  -auth chengkai.liang:test1234 \
  who-am-i
```

Expected output:
```
Authenticated as: chengkai.liang
Authorities:
  jenkins-admins
  authenticated
  it-devops
  ROLE_IT-DEVOPS
  ROLE_JENKINS-ADMINS
```

## Troubleshooting

### Certificate Already Exists Error

If you see:
```
keytool error: java.lang.Exception: Certificate not imported, alias <vault-k3d-ca> already exists
```

The certificate is already imported. To replace it, first delete the old certificate:

```bash
keytool -delete -cacerts -storepass changeit -alias vault-k3d-ca
```

Then re-import using the import command from step 3.

### Permission Denied

If you get permission errors when importing the certificate, you may need to run the `keytool` command with elevated privileges:

```bash
sudo keytool -importcert \
  -keystore /path/to/cacerts \
  -storepass changeit \
  -alias vault-k3d-ca \
  -file vault-ca.crt \
  -noprompt
```

Replace `/path/to/cacerts` with the actual path from step 2.

### Certificate Rotation

When Vault rotates the root CA certificate (uncommon for development), you'll need to:

1. Extract the new CA certificate
2. Delete the old certificate from the truststore
3. Import the new certificate

The jenkins-cert-rotator CronJob automatically handles leaf certificate rotation, but root CA changes require manual truststore updates.

### Multiple Java Installations

If you have multiple Java installations, ensure you're importing the certificate into the truststore used by the `java` command that runs jenkins-cli.

Check which Java is in use:

```bash
which java
java -version
```

Import the certificate into the corresponding truststore.

## Platform-Specific Notes

### macOS with Homebrew Java

If using Homebrew-installed Java:

```bash
# Find Java home
/usr/libexec/java_home

# Truststore location
/usr/libexec/java_home/lib/security/cacerts
```

### Linux with System Java

On Debian/Ubuntu systems with default Java:

```bash
# Common locations
/usr/lib/jvm/default-java/lib/security/cacerts
/etc/ssl/certs/java/cacerts
```

### Using JAVA_HOME Environment Variable

If `JAVA_HOME` is set:

```bash
echo $JAVA_HOME
# Truststore at: $JAVA_HOME/lib/security/cacerts
```

## Security Considerations

- The default cacerts password is `changeit`. In production environments, consider changing this password.
- Only import CA certificates from trusted sources.
- For production Jenkins instances, use certificates from a trusted public CA or your organization's internal CA.
- The Vault CA certificate grants trust to all certificates signed by that CA. Ensure Vault's PKI role is properly constrained.

## Alternative Approaches

### System-Wide Certificate Trust

Instead of modifying Java's truststore, you can add the CA certificate to your system's trusted certificate store:

**Linux:**
```bash
sudo cp vault-ca.crt /usr/local/share/ca-certificates/vault-k3d-ca.crt
sudo update-ca-certificates
```

**macOS:**
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain vault-ca.crt
```

### Per-Command Trust

For temporary testing, specify the truststore explicitly:

```bash
java -Djavax.net.ssl.trustStore=/path/to/custom-truststore \
  -Djavax.net.ssl.trustStorePassword=changeit \
  -jar jenkins-cli.jar -s https://jenkins.dev.local.me version
```

## Related Documentation

- [Jenkins Deployment](../../README.md#jenkins-authentication-modes)
- [Vault PKI Setup](../../README.md#vault-pki-setup)
- [Java keytool Documentation](https://docs.oracle.com/en/java/javase/17/docs/specs/man/keytool.html)

## Automation Script

For automated setups, here's a complete script:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Extract Vault CA certificate
kubectl -n vault exec vault-0 -- vault read -field=certificate pki/cert/ca > vault-ca.crt

# Find Java home
JAVA_HOME=$(java -XshowSettings:properties -version 2>&1 | grep "java.home" | awk '{print $3}')
CACERTS="${JAVA_HOME}/lib/security/cacerts"

# Delete existing certificate if present (ignore errors)
keytool -delete -cacerts -storepass changeit -alias vault-k3d-ca 2>/dev/null || true

# Import new certificate
keytool -importcert \
  -cacerts \
  -storepass changeit \
  -alias vault-k3d-ca \
  -file vault-ca.crt \
  -noprompt

echo "Vault CA certificate imported successfully to ${CACERTS}"

# Verify
keytool -list -cacerts -storepass changeit -alias vault-k3d-ca -v

# Clean up
rm -f vault-ca.crt

echo "Setup complete. jenkins-cli can now be used without -noCertificateCheck"
```

Save this as `scripts/setup-jenkins-cli-ssl.sh` and run it after deploying Jenkins with Vault PKI.
