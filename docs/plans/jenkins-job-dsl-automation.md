# Jenkins Job DSL Automation Plan

## Overview

Implement automated Jenkins job creation using the Job DSL plugin. This will allow declarative job definitions in version control, eliminating manual job creation through the UI and enabling Infrastructure-as-Code for CI/CD pipelines.

**Current State:**
- Job DSL plugin already installed via `scripts/etc/jenkins/values-*.yaml.tmpl`
- Manual job creation required through UI (blocked by LDAP auth)
- Test jobs defined as standalone Groovy scripts

**Target State:**
- Jobs defined in version control as DSL scripts
- Automated deployment via seed job
- Progressive complexity: simple pipelines → multi-branch → folders → parent-child
- Full lifecycle management (create, update, delete jobs via code)

## Prerequisites

- Jenkins deployed with Job DSL plugin (already satisfied)
- Kubernetes agents configured (already completed)
- Git repository for storing DSL scripts (this repo)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Git Repository (k3d-manager)                                │
│                                                               │
│  scripts/etc/jenkins/job-dsl/                                │
│  ├── seed-job.groovy          (Bootstrap seed job)           │
│  ├── simple/                  (Simple pipeline examples)     │
│  │   ├── 01-linux-agent.groovy                               │
│  │   └── 02-kaniko-agent.groovy                              │
│  ├── multibranch/             (Multi-branch pipelines)       │
│  │   ├── example-repo.groovy                                 │
│  │   └── github-org.groovy                                   │
│  └── folders/                 (Folder organization)          │
│      └── team-structure.groovy                               │
│                                                               │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ JCasC deploys seed job
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Jenkins Controller                                           │
│                                                               │
│  Seed Job (deployed via JCasC)                              │
│  ├── Reads DSL scripts from ConfigMap                       │
│  ├── Executes Job DSL plugin                                │
│  └── Creates/Updates jobs                                    │
│                                                               │
│  Generated Jobs:                                             │
│  ├── Tests/                   (folder)                       │
│  │   ├── 01-linux-agent-test                                │
│  │   └── 02-kaniko-agent-test                               │
│  ├── Projects/                (folder)                       │
│  │   └── example-multibranch                                │
│  └── Teams/                   (folder)                       │
│      ├── TeamA/                                              │
│      └── TeamB/                                              │
└─────────────────────────────────────────────────────────────┘
```

**Deployment Flow:**
1. DSL scripts stored in `scripts/etc/jenkins/job-dsl/`
2. ConfigMap created from DSL directory during deployment
3. Seed job configured in JCasC (`03-job-dsl-seed.yaml`)
4. Seed job runs on Jenkins startup, reads ConfigMap
5. Job DSL plugin processes scripts, creates jobs
6. Jobs appear in Jenkins UI ready to run

## Implementation Phases

### Phase 1: Simple Pipeline Jobs (1 hour)

Convert existing test jobs to Job DSL format.

**Files to Create:**
- `scripts/etc/jenkins/job-dsl/simple/01-linux-agent-test.groovy`
- `scripts/etc/jenkins/job-dsl/simple/02-kaniko-agent-test.groovy`
- `scripts/etc/jenkins/job-dsl/seed-job.groovy` (master script)

**Example DSL Structure:**
```groovy
// 01-linux-agent-test.groovy
pipelineJob('Tests/linux-agent-test') {
    description('Test Kubernetes linux-agent functionality')

    definition {
        cps {
            script('''
                pipeline {
                    agent { label 'linux-agent' }
                    stages {
                        stage('Environment') {
                            steps {
                                sh 'uname -a'
                                sh 'kubectl version --client'
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

**Integration:**
- Create ConfigMap: `scripts/etc/jenkins/job-dsl-configmap.yaml.tmpl`
- Add JCasC seed job config: Update values templates with `03-job-dsl-seed.yaml`
- Deploy via `scripts/plugins/jenkins.sh` integration

### Phase 2: Folder Organization (30 min)

Organize jobs into folders for better structure.

**Files to Create:**
- `scripts/etc/jenkins/job-dsl/folders/test-folder.groovy`

**Example:**
```groovy
folder('Tests') {
    description('Automated test jobs for K8s agents')
    displayName('Test Jobs')
}

folder('Projects') {
    description('Application build pipelines')
}

folder('Teams') {
    description('Team-specific job folders')
}
```

**Benefits:**
- Logical grouping of related jobs
- Permission management at folder level
- Cleaner Jenkins UI

### Phase 3: Multi-Branch Pipelines (1 hour)

Create multi-branch pipeline jobs that auto-discover branches.

**Files to Create:**
- `scripts/etc/jenkins/job-dsl/multibranch/example-repo.groovy`

**Example:**
```groovy
multibranchPipelineJob('Projects/example-app') {
    displayName('Example Application')
    description('Multi-branch pipeline for example-app repository')

    branchSources {
        git {
            id('example-app-git')
            remote('https://github.com/example/app.git')
            credentialsId('github-credentials')  // Optional

            traits {
                gitBranchDiscovery()
                gitTagDiscovery()
            }
        }
    }

    // Look for Jenkinsfile in repo root
    factory {
        workflowBranchProjectFactory {
            scriptPath('Jenkinsfile')
        }
    }

    // Scan every 4 hours
    triggers {
        periodic(240)
    }

    orphanedItemStrategy {
        discardOldItems {
            numToKeep(10)
        }
    }
}
```

**Features:**
- Auto-discovers branches and tags
- Creates job per branch automatically
- Cleans up jobs for deleted branches
- Periodic repository scanning

### Phase 4: GitHub Organization Folders (45 min)

Scan entire GitHub organizations for Jenkinsfiles.

**Files to Create:**
- `scripts/etc/jenkins/job-dsl/multibranch/github-org.groovy`

**Example:**
```groovy
organizationFolder('GitHub/MyOrg') {
    description('GitHub organization MyOrg')
    displayName('MyOrg Repositories')

    organizations {
        github {
            repoOwner('myorg')
            credentialsId('github-token')

            traits {
                gitHubBranchDiscovery {
                    strategyId(1)  // Discover all branches
                }
                gitHubPullRequestDiscovery {
                    strategyId(1)  // Discover PRs from origin
                }
                gitHubTagDiscovery()
            }
        }
    }

    projectFactories {
        workflowMultiBranchProjectFactory {
            scriptPath('Jenkinsfile')
        }
    }

    triggers {
        periodic(360)  // Scan every 6 hours
    }
}
```

**Benefits:**
- Auto-discovers all repos in organization
- Creates multi-branch job per repository
- Handles PR validation automatically

### Phase 5: Parent-Child Job Relationships (1 hour)

Create jobs that trigger other jobs with parameter passing.

**Files to Create:**
- `scripts/etc/jenkins/job-dsl/complex/parent-child.groovy`

**Example:**
```groovy
// Parent job - orchestrator
pipelineJob('Workflows/build-test-deploy') {
    description('Parent job: Build → Test → Deploy workflow')

    parameters {
        stringParam('ENVIRONMENT', 'dev', 'Target environment')
        stringParam('VERSION', '', 'Version to deploy')
    }

    definition {
        cps {
            script('''
                pipeline {
                    agent any
                    stages {
                        stage('Build') {
                            steps {
                                build job: 'Workflows/child-build',
                                      parameters: [
                                          string(name: 'VERSION', value: params.VERSION)
                                      ],
                                      wait: true,
                                      propagate: true
                            }
                        }
                        stage('Test') {
                            parallel {
                                stage('Unit Tests') {
                                    steps {
                                        build job: 'Workflows/child-unit-test',
                                              parameters: [
                                                  string(name: 'VERSION', value: params.VERSION)
                                              ]
                                    }
                                }
                                stage('Integration Tests') {
                                    steps {
                                        build job: 'Workflows/child-integration-test',
                                              parameters: [
                                                  string(name: 'VERSION', value: params.VERSION)
                                              ]
                                    }
                                }
                            }
                        }
                        stage('Deploy') {
                            steps {
                                build job: 'Workflows/child-deploy',
                                      parameters: [
                                          string(name: 'ENVIRONMENT', value: params.ENVIRONMENT),
                                          string(name: 'VERSION', value: params.VERSION)
                                      ]
                            }
                        }
                    }
                }
            '''.stripIndent())
            sandbox(true)
        }
    }
}

// Child job - build
pipelineJob('Workflows/child-build') {
    description('Child job: Build application')

    parameters {
        stringParam('VERSION', '', 'Version to build')
    }

    definition {
        cps {
            script('''
                pipeline {
                    agent { label 'kaniko-agent' }
                    stages {
                        stage('Build') {
                            steps {
                                echo "Building version: ${params.VERSION}"
                                // Build logic here
                            }
                        }
                    }
                }
            '''.stripIndent())
            sandbox(true)
        }
    }
}

// Additional child jobs: child-unit-test, child-integration-test, child-deploy
// Similar structure with different stages
```

**Features:**
- Orchestration of complex workflows
- Parameter passing between jobs
- Parallel execution support
- Wait for completion and propagate status

### Phase 6: Advanced Features (1 hour)

**Parameterized Jobs:**
```groovy
pipelineJob('Advanced/parameterized-job') {
    parameters {
        stringParam('BRANCH', 'main', 'Git branch to build')
        choiceParam('ENVIRONMENT', ['dev', 'staging', 'prod'], 'Deploy target')
        booleanParam('RUN_TESTS', true, 'Execute test suite')
        textParam('NOTES', '', 'Build notes')
    }

    // Pipeline definition...
}
```

**Scheduled Builds:**
```groovy
pipelineJob('Maintenance/nightly-build') {
    triggers {
        cron('H 2 * * *')  // 2 AM daily
    }

    // Pipeline definition...
}
```

**Build Triggers:**
```groovy
pipelineJob('CI/pr-validation') {
    triggers {
        githubPush()  // Trigger on GitHub push
    }

    properties {
        githubProjectProperty {
            projectUrlStr('https://github.com/example/repo')
        }
    }

    // Pipeline definition...
}
```

**Post-Build Actions:**
```groovy
pipelineJob('Projects/app-build') {
    publishers {
        archiveArtifacts {
            pattern('target/*.jar')
            onlyIfSuccessful(true)
        }

        mailer('team@example.com', false, true)  // Email on failure
    }

    // Pipeline definition...
}
```

## Deployment Integration

### ConfigMap Creation

**`scripts/etc/jenkins/job-dsl-configmap.yaml.tmpl`:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: jenkins-job-dsl
  namespace: ${JENKINS_NAMESPACE}
data:
  seed-job.groovy: |
    ${SEED_JOB_CONTENT}
  01-linux-agent-test.groovy: |
    ${LINUX_AGENT_TEST_CONTENT}
  02-kaniko-agent-test.groovy: |
    ${KANIKO_AGENT_TEST_CONTENT}
  # Additional DSL scripts...
```

### JCasC Seed Job Configuration

**Add to `values-*.yaml.tmpl` JCasC section:**
```yaml
03-job-dsl-seed: |
  jobs:
    - script: >
        job('seed-job') {
          description('Master seed job - creates all other jobs from DSL')

          scm {
            // Read from ConfigMap mounted at /var/jenkins_config/job-dsl/
            filesystem {
              path('/var/jenkins_config/job-dsl/')
              clearWorkspace(false)
              copyHidden(false)
            }
          }

          steps {
            dsl {
              external('*.groovy')
              removeAction('DELETE')
              removeViewAction('DELETE')
              lookupStrategy('SEED_JOB')
              additionalClasspath('src')
            }
          }

          triggers {
            scm('H/5 * * * *')  // Check for changes every 5 min
          }
        }
```

### Volume Mount for DSL Scripts

**Update controller volume mounts in values templates:**
```yaml
controller:
  volumes:
    - name: job-dsl-scripts
      configMap:
        name: jenkins-job-dsl

  mounts:
    - name: job-dsl-scripts
      mountPath: /var/jenkins_config/job-dsl
      readOnly: true
```

### Plugin Integration

**Modify `scripts/plugins/jenkins.sh`:**
```bash
# Deploy Job DSL ConfigMap
function _jenkins_deploy_job_dsl() {
  local configmap_template="$JENKINS_CONFIG_DIR/job-dsl-configmap.yaml.tmpl"

  if [[ ! -r "$configmap_template" ]]; then
    _warn "[jenkins] Job DSL ConfigMap template not found, skipping"
    return 0
  fi

  _info "[jenkins] Creating Job DSL ConfigMap from scripts..."

  # Read all DSL scripts and inject into template
  local dsl_dir="$JENKINS_CONFIG_DIR/job-dsl"
  local rendered_configmap
  rendered_configmap=$(mktemp -t jenkins-job-dsl-configmap.XXXXXX.yaml)
  _jenkins_register_rendered_manifest "$rendered_configmap"

  # Build ConfigMap data from DSL directory
  # ... (implementation details)

  _kubectl apply -f "$rendered_configmap"
  _info "[jenkins] ✓ Job DSL ConfigMap deployed"
}

# Call during Jenkins deployment
_jenkins_deploy_job_dsl
```

## Testing Strategy

### Phase 1: Basic Validation
1. Deploy Jenkins with Job DSL integration
2. Verify seed job exists and runs successfully
3. Verify simple test jobs created in Tests folder
4. Execute linux-agent-test job
5. Execute kaniko-agent-test job

### Phase 2: Folder Structure
1. Verify folder hierarchy created correctly
2. Test folder permissions and display names
3. Move jobs between folders via DSL updates

### Phase 3: Multi-Branch Testing
1. Create test repository with Jenkinsfile
2. Deploy multi-branch DSL script
3. Verify branches auto-discovered
4. Create new branch, verify job auto-created
5. Delete branch, verify job auto-removed

### Phase 4: Parent-Child Workflow
1. Deploy parent-child job suite
2. Trigger parent job with parameters
3. Verify child jobs triggered in correct order
4. Verify parameter passing works
5. Test failure propagation

### Phase 5: Update and Delete
1. Modify DSL script (change job description)
2. Re-run seed job, verify job updated
3. Remove job from DSL script
4. Re-run seed job, verify job deleted

## Migration Path

**From Manual Jobs to DSL:**

1. **Export existing job config:**
```bash
# Get job XML via Jenkins API
kubectl exec -n jenkins jenkins-0 -- \
  curl -u admin:password http://localhost:8080/job/my-job/config.xml > job.xml

# Convert XML to DSL (manual or use Jenkins Job DSL API Viewer)
```

2. **Use Jenkins Job DSL API Viewer:**
   - Navigate to: `https://jenkins.example.com/plugin/job-dsl/api-viewer/index.html`
   - Browse available DSL methods and examples
   - Copy relevant DSL syntax

3. **Create DSL script from template**
4. **Test in sandbox environment**
5. **Deploy via seed job**
6. **Verify job parity**
7. **Delete manual job**

## Best Practices

1. **Version Control Everything:**
   - All DSL scripts in Git
   - Track changes via commits
   - Use pull requests for job changes

2. **Folder Organization:**
   - Group by team, project, or job type
   - Use consistent naming conventions
   - Document folder purposes

3. **Seed Job Strategy:**
   - Single master seed job recommended
   - Use `removeAction('DELETE')` carefully (prefer 'DISABLE')
   - Test DSL changes in dev environment first

4. **Security:**
   - Use Job DSL sandbox mode (`sandbox(true)`)
   - Limit seed job permissions appropriately
   - Store credentials in Jenkins Credential Store, reference by ID

5. **Maintenance:**
   - Regular cleanup of orphaned jobs
   - Document complex DSL patterns
   - Use shared libraries for common patterns

6. **Testing:**
   - Validate DSL syntax before deploying
   - Use Jenkins Job DSL Playground for testing
   - Monitor seed job execution logs

## Troubleshooting

### Seed Job Fails with Script Security Error
**Symptom:** `org.jenkinsci.plugins.scriptsecurity.sandbox.RejectedAccessException`

**Solution:**
- Enable sandbox mode: `sandbox(true)` in CPS definition
- Or approve script in: Manage Jenkins → In-process Script Approval

### Jobs Not Created/Updated
**Symptom:** Seed job succeeds but jobs not appearing

**Solution:**
- Check seed job console output for errors
- Verify DSL script syntax (use API Viewer)
- Check `lookupStrategy` is correct (use 'SEED_JOB')
- Verify ConfigMap mounted correctly: `kubectl describe pod jenkins-0`

### Job Parameters Not Working
**Symptom:** Parameters defined but not showing in UI

**Solution:**
- Ensure `parameters {}` block in correct location (outside `definition`)
- Use `properties {}` block for advanced properties
- Rebuild job after DSL update

### Multi-Branch Not Discovering Branches
**Symptom:** Multi-branch job created but no branches found

**Solution:**
- Verify repository URL accessible from Jenkins
- Check credentials if private repository
- Manually trigger "Scan Repository Now"
- Check Jenkinsfile exists in branches
- Review discovery traits configuration

## File Structure Summary

```
scripts/etc/jenkins/
├── job-dsl/
│   ├── seed-job.groovy              # Master seed job
│   ├── simple/
│   │   ├── 01-linux-agent-test.groovy
│   │   └── 02-kaniko-agent-test.groovy
│   ├── folders/
│   │   └── folder-structure.groovy
│   ├── multibranch/
│   │   ├── example-repo.groovy
│   │   └── github-org.groovy
│   └── complex/
│       ├── parent-child.groovy
│       └── parameterized.groovy
├── job-dsl-configmap.yaml.tmpl      # ConfigMap template
└── values-*.yaml.tmpl                # Updated with JCasC seed job config
```

## Effort Estimate

| Phase | Description | Time |
|-------|-------------|------|
| Phase 1 | Simple pipeline jobs + seed job | 1 hour |
| Phase 2 | Folder organization | 30 min |
| Phase 3 | Multi-branch pipelines | 1 hour |
| Phase 4 | GitHub organization folders | 45 min |
| Phase 5 | Parent-child relationships | 1 hour |
| Phase 6 | Advanced features | 1 hour |
| Testing | Validation across all phases | 1 hour |
| Documentation | Update CLAUDE.md, guides | 30 min |
| **Total** | | **6-7 hours** |

## Success Criteria

- ✅ Seed job deploys automatically via JCasC
- ✅ Simple test jobs created without manual intervention
- ✅ Folder structure organized logically
- ✅ Multi-branch pipeline auto-discovers branches
- ✅ Parent job successfully orchestrates child jobs
- ✅ DSL changes reflected after seed job re-run
- ✅ Jobs removed when deleted from DSL scripts
- ✅ Documentation updated with Job DSL usage

## References

- [Job DSL Plugin Documentation](https://plugins.jenkins.io/job-dsl/)
- [Job DSL API Viewer](https://jenkinsci.github.io/job-dsl-plugin/)
- [Jenkins Configuration as Code (JCasC)](https://plugins.jenkins.io/configuration-as-code/)
- [Pipeline Syntax Reference](https://www.jenkins.io/doc/book/pipeline/syntax/)

## Next Steps

1. Review and approve this plan
2. Implement Phase 1 (simple jobs + seed job)
3. Test deployment and validate job creation
4. Progressively implement remaining phases
5. Update CLAUDE.md and README.md with Job DSL information
