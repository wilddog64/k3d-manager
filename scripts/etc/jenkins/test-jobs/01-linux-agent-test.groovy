// Test job for Linux agent - validates basic agent functionality
pipeline {
    agent {
        label 'linux'
    }

    stages {
        stage('System Information') {
            steps {
                echo '=== System Information ==='
                sh 'uname -a'
                sh 'cat /etc/os-release || cat /etc/issue'
                sh 'df -h'
                sh 'free -h || true'
            }
        }

        stage('Environment') {
            steps {
                echo '=== Environment Variables ==='
                sh 'env | sort'
                sh 'pwd'
                sh 'whoami'
                sh 'id'
            }
        }

        stage('Tools Check') {
            steps {
                echo '=== Checking Available Tools ==='
                script {
                    def tools = ['git', 'curl', 'wget', 'tar', 'gzip', 'unzip']
                    tools.each { tool ->
                        sh "command -v ${tool} && ${tool} --version || echo '${tool} not found'"
                    }
                }
            }
        }

        stage('kubectl Test') {
            steps {
                echo '=== kubectl Tests ==='
                sh 'command -v kubectl && kubectl version --client || echo "kubectl not available - install if needed"'
                sh 'kubectl get nodes || echo "No cluster access (expected in some configs)"'
            }
        }

        stage('Workspace Test') {
            steps {
                echo '=== Workspace Tests ==='
                sh 'echo "Test file content" > test-file.txt'
                sh 'cat test-file.txt'
                sh 'ls -la'
            }
        }
    }

    post {
        always {
            echo '=== Cleanup ==='
            sh 'rm -f test-file.txt'
        }
        success {
            echo '✅ Linux agent test PASSED'
        }
        failure {
            echo '❌ Linux agent test FAILED'
        }
    }
}
