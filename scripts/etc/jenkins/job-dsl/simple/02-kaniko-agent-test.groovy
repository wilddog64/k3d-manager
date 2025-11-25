// Job DSL script for kaniko-agent test job
// This job validates that Kubernetes kaniko-agent pods can build container images without Docker daemon

pipelineJob('Tests/kaniko-agent-test') {
    description('Test Kubernetes kaniko-agent functionality - validates rootless container image building with Kaniko')

    definition {
        cps {
            script('''
pipeline {
    agent {
        label 'kaniko-agent'
    }

    stages {
        stage('Environment Info') {
            steps {
                echo '=== Agent Information ==='
                container('jnlp') {
                    sh 'uname -a'
                    sh 'whoami'
                    sh 'pwd'
                }
                echo ''
            }
        }

        stage('Kaniko Availability') {
            steps {
                echo '=== Kaniko Container Check ==='
                container('kaniko') {
                    sh 'echo "Kaniko container is available"'
                    sh 'ls -la /kaniko/ || true'
                    sh 'cat /etc/os-release || true'
                }
                echo ''
            }
        }

        stage('Create Test Dockerfile') {
            steps {
                echo '=== Creating Test Dockerfile ==='
                container('jnlp') {
                    sh """
cat > Dockerfile << 'DOCKERFILE_EOF'
FROM alpine:3.18
RUN apk add --no-cache curl
RUN echo "Build timestamp: \$(date)" > /build-info.txt
CMD ["cat", "/build-info.txt"]
DOCKERFILE_EOF
"""
                    sh 'cat Dockerfile'
                }
                echo ''
            }
        }

        stage('Build Image with Kaniko') {
            steps {
                echo '=== Building Container Image ==='
                container('kaniko') {
                    sh """
                        /kaniko/executor \\
                            --context=\${WORKSPACE} \\
                            --dockerfile=\${WORKSPACE}/Dockerfile \\
                            --no-push \\
                            --tar-path=\${WORKSPACE}/image.tar \\
                            --destination=test-image:\${BUILD_NUMBER} \\
                            --verbosity=info
                    """
                }
                echo ''
            }
        }

        stage('Verify Build Artifacts') {
            steps {
                echo '=== Verifying Build Output ==='
                container('jnlp') {
                    sh 'ls -lh image.tar'
                    sh 'file image.tar || echo "file command not available"'
                    sh 'du -h image.tar'
                }
                echo ''
            }
        }

        stage('Cleanup') {
            steps {
                echo '=== Cleaning Up ==='
                container('jnlp') {
                    sh 'rm -f Dockerfile image.tar'
                    sh 'ls -la'
                }
                echo ''
            }
        }
    }

    post {
        success {
            echo '✓ Kaniko agent test completed successfully'
            echo '  - Kaniko container accessible'
            echo '  - Image build successful (rootless, no Docker daemon)'
            echo '  - Build artifacts verified'
        }
        failure {
            echo '✗ Kaniko agent test failed'
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
