// Job DSL script for linux-agent test job
// This job validates that Kubernetes linux-agent pods can be provisioned and execute basic commands

pipelineJob('Tests/linux-agent-test') {
    description('Test Kubernetes linux-agent functionality - validates agent provisioning, kubectl, and basic tools')

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
                echo '=== System Information ==='
                sh 'uname -a'
                sh 'cat /etc/os-release || true'
                echo ''

                echo '=== User and Permissions ==='
                sh 'whoami'
                sh 'id'
                echo ''
            }
        }

        stage('Tool Versions') {
            steps {
                echo '=== Installed Tools ==='
                sh 'kubectl version --client || echo "kubectl not installed"'
                sh 'git --version || echo "git not installed"'
                sh 'java -version || echo "java not installed"'
                sh 'curl --version || echo "curl not installed"'
                echo ''
            }
        }

        stage('Network Connectivity') {
            steps {
                echo '=== Network Tests ==='
                sh 'hostname'
                sh 'hostname -i || true'
                sh 'curl -s https://api.github.com/zen || echo "External connectivity test failed"'
                echo ''
            }
        }

        stage('Workspace Access') {
            steps {
                echo '=== Workspace Tests ==='
                sh 'pwd'
                sh 'ls -la'
                sh 'echo "Test file content" > test-file.txt'
                sh 'cat test-file.txt'
                sh 'rm test-file.txt'
                echo ''
            }
        }

        stage('Kubernetes Access') {
            steps {
                echo '=== Kubernetes API Access ==='
                sh 'kubectl get nodes || echo "Cannot access Kubernetes API (expected if RBAC not configured)"'
                sh 'kubectl get pods -n jenkins || echo "Cannot list Jenkins pods"'
                echo ''
            }
        }
    }

    post {
        success {
            echo '✓ Linux agent test completed successfully'
        }
        failure {
            echo '✗ Linux agent test failed'
        }
        always {
            echo "Build completed at ${new Date()}"
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
