# Jenkins Job DSL Setup Guide

This guide explains how to configure Jenkins to automatically create jobs from Job DSL scripts stored in a GitHub repository.

## Overview

The k3d-manager Jenkins deployment includes an automatic seed job that:
- Pulls Job DSL scripts from a GitHub repository
- Checks for updates every 15 minutes
- Automatically creates/updates Jenkins jobs based on the DSL scripts
- Works without requiring volume mounts or ConfigMaps

## Prerequisites

- Jenkins deployed with `./scripts/k3d-manager deploy_jenkins --enable-ldap --enable-vault`
- A GitHub repository to store your Job DSL scripts
- Basic understanding of Jenkins Job DSL syntax

## Quick Start

### 1. Create a GitHub Repository

Create a new GitHub repository with the following structure:

```
jenkins-job-dsl/
├── README.md
└── jobs/
    ├── tests/
    │   ├── linux-agent-test.groovy
    │   └── kaniko-agent-test.groovy
    └── pipelines/
        └── example-pipeline.groovy
```

**Important:** All Job DSL scripts must be placed in the `jobs/` directory or its subdirectories.

### 2. Configure the Repository URL

Edit the Jenkins values template to point to your repository:

```bash
vim scripts/etc/jenkins/values-ldap.yaml.tmpl
```

Find the seed job configuration (around line 244) and update the repository URL:

```groovy
scm {
  git {
    remote {
      url('https://github.com/your-org/jenkins-job-dsl.git')  # Change this
      credentials('')  # Add credentials ID if private repo
    }
    branch('*/main')  # Change branch if needed
  }
}
```

### 3. Redeploy Jenkins

After updating the configuration, redeploy Jenkins:

```bash
# Delete the StatefulSet and ConfigMaps
kubectl delete sts jenkins -n jenkins
kubectl delete configmap -n jenkins -l "app.kubernetes.io/instance=jenkins"

# Redeploy
./scripts/k3d-manager deploy_jenkins --enable-ldap --enable-vault
```

### 4. Verify Seed Job Creation

Check that the seed job was created:

```bash
kubectl exec -n jenkins jenkins-0 -c jenkins -- ls -la /var/jenkins_home/jobs/
```

You should see a `seed-job` directory.

### 5. Trigger the Seed Job

The seed job will automatically run every 15 minutes when changes are detected. To run it immediately:

1. Access Jenkins UI at `https://jenkins.dev.local.me/`
2. Navigate to the `seed-job`
3. Click "Build Now"

## Example Job DSL Scripts

### Simple Pipeline Job

Create `jobs/pipelines/hello-world.groovy`:

```groovy
pipelineJob('hello-world') {
    description('Simple hello world pipeline')

    definition {
        cps {
            script('''
                pipeline {
                    agent any
                    stages {
                        stage('Hello') {
                            steps {
                                echo 'Hello, World!'
                            }
                        }
                    }
                }
            '''.stripIndent())
            sandbox(true)
        }
    }

    logRotator {
        numToKeep(10)
        daysToKeep(30)
    }
}
```

### Job in a Folder

Create `jobs/tests/folder-example.groovy`:

```groovy
folder('MyFolder') {
    displayName('My Folder')
    description('Example folder for organizing jobs')
}

pipelineJob('MyFolder/test-job') {
    description('Job inside a folder')

    definition {
        cps {
            script('''
                pipeline {
                    agent any
                    stages {
                        stage('Test') {
                            steps {
                                echo 'Testing from folder'
                            }
                        }
                    }
                }
            '''.stripIndent())
            sandbox(true)
        }
    }
}
```

### Kubernetes Agent Job

Create `jobs/k8s/linux-agent-test.groovy`:

```groovy
pipelineJob('Tests/linux-agent-test') {
    description('Test Kubernetes linux-agent functionality')

    definition {
        cps {
            script('''
                pipeline {
                    agent {
                        label 'linux-agent'
                    }

                    stages {
                        stage('Environment Info') {
                            steps {
                                sh 'uname -a'
                                sh 'kubectl version --client || echo "kubectl not installed"'
                            }
                        }

                        stage('Test') {
                            steps {
                                echo 'Running on Kubernetes agent'
                            }
                        }
                    }
                }
            '''.stripIndent())
            sandbox(true)
        }
    }

    logRotator {
        numToKeep(10)
        daysToKeep(30)
    }
}
```

## Using Private Repositories

If your Job DSL repository is private, you need to add credentials:

### 1. Create GitHub Personal Access Token

1. Go to GitHub Settings → Developer settings → Personal access tokens
2. Generate new token with `repo` scope
3. Copy the token

### 2. Add Credentials to Jenkins

1. Access Jenkins UI
2. Navigate to "Manage Jenkins" → "Manage Credentials"
3. Add new credentials:
   - Kind: "Username with password"
   - Username: Your GitHub username
   - Password: Your personal access token
   - ID: `github-job-dsl` (or any ID you prefer)

### 3. Update Seed Job Configuration

Edit `scripts/etc/jenkins/values-ldap.yaml.tmpl`:

```groovy
scm {
  git {
    remote {
      url('https://github.com/your-org/jenkins-job-dsl.git')
      credentials('github-job-dsl')  # Add your credentials ID here
    }
    branch('*/main')
  }
}
```

Then redeploy Jenkins.

## Seed Job Configuration Options

### Change Polling Interval

The default polling interval is every 15 minutes (`H/15 * * * *`). To change this, edit the `triggers` section in `scripts/etc/jenkins/values-ldap.yaml.tmpl`:

```groovy
triggers {
  scm('H/5 * * * *')   # Every 5 minutes
  scm('H * * * *')     # Every hour
  scm('@daily')        # Once per day
}
```

### Change Branch

To pull from a different branch:

```groovy
scm {
  git {
    remote {
      url('https://github.com/your-org/jenkins-job-dsl.git')
      credentials('')
    }
    branch('*/develop')  # Change to your branch
  }
}
```

### Change Script Path Pattern

By default, the seed job processes all `.groovy` files in the `jobs/` directory. To change this:

```groovy
steps {
  dsl {
    external('dsl/**/*.groovy')  # Different directory
    external('*.groovy')         # Root level only
    external('jobs/prod/**/*.groovy')  # Specific subdirectory
    removeAction('DELETE')
    removeViewAction('DELETE')
    lookupStrategy('SEED_JOB')
  }
}
```

## Troubleshooting

### Seed Job Not Created

Check Jenkins logs:

```bash
kubectl logs -n jenkins jenkins-0 -c jenkins | grep -i "seed-job"
```

Look for the message: `createOrUpdateConfig for seed-job`

### Seed Job Fails to Clone Repository

1. Check if the repository URL is correct
2. Verify credentials if using a private repository
3. Check Jenkins logs for git errors:

```bash
kubectl logs -n jenkins jenkins-0 -c jenkins | grep -i "git"
```

### Jobs Not Being Created

1. Check seed job console output in Jenkins UI
2. Verify DSL scripts are in the `jobs/` directory
3. Check for syntax errors in your DSL scripts
4. Ensure the script pattern matches your file structure

### Script Security Errors

If you see script security errors, you may need to approve scripts:

1. Go to "Manage Jenkins" → "In-process Script Approval"
2. Approve the pending script signatures

## Advanced Topics

### Multi-Branch Seed Jobs

To create seed jobs for multiple branches:

```groovy
multibranchPipelineJob('seed-job-multibranch') {
    branchSources {
        git {
            remote('https://github.com/your-org/jenkins-job-dsl.git')
            credentialsId('')
        }
    }

    orphanedItemStrategy {
        discardOldItems {
            numToKeep(10)
        }
    }
}
```

### Parameterized DSL Scripts

You can use environment variables or build parameters in your DSL scripts:

```groovy
def env = System.getenv()
def cluster = env['CLUSTER_NAME'] ?: 'dev'

pipelineJob("deploy-to-${cluster}") {
    description("Deploy to ${cluster} cluster")
    // ... rest of configuration
}
```

### Script Includes

You can include shared DSL scripts:

Create `jobs/common/shared.groovy`:

```groovy
def createPipeline(name, script) {
    pipelineJob(name) {
        definition {
            cps {
                script(script)
                sandbox(true)
            }
        }
        logRotator {
            numToKeep(10)
            daysToKeep(30)
        }
    }
}

return this
```

Use in `jobs/pipelines/example.groovy`:

```groovy
def shared = evaluate(new File(
'/var/jenkins_home/workspace/seed-job/jobs/common/shared.groovy'))

shared.createPipeline('my-pipeline', '''
    pipeline {
        agent any
        stages {
            stage('Build') {
                steps {
                    echo 'Building...'
                }
            }
        }
    }
''')
```

## Template Repository

For a complete example repository structure with sample Job DSL scripts, see:

- [Jenkins Job DSL API Reference](https://jenkinsci.github.io/job-dsl-plugin/)
- [Job DSL Plugin Examples](https://github.com/jenkinsci/job-dsl-plugin/tree/master/job-dsl-plugin/src/test/resources)

## Related Documentation

- [Jenkins Deployment Guide](../README.md#jenkins-deployment)
- [LDAP Configuration](../scripts/etc/ldap/vars.sh)
- [Vault PKI Integration](../scripts/etc/vault/vars.sh)
