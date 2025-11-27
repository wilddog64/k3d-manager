// Master Seed Job DSL Script
// This script creates a "Tests" folder and processes all job DSL scripts in the simple/ directory
// It serves as the bootstrap for all automated job creation

// Create Tests folder for organizing test jobs
folder('Tests') {
    displayName('Test Jobs')
    description('Automated test jobs for validating Jenkins Kubernetes agents and functionality')
}

// Process all DSL scripts in the job-dsl directory
// The ConfigMap is mounted directly at /var/jenkins_dsl
def dslScripts = [
    'simple-01-linux-agent-test.groovy',
    'simple-02-kaniko-agent-test.groovy'
]

dslScripts.each { scriptName ->
    def scriptFile = new File("/var/jenkins_dsl/${scriptName}")
    if (scriptFile.exists()) {
        println "Processing DSL script: ${scriptName}"
        evaluate(scriptFile.text)
    } else {
        println "WARNING: DSL script not found: ${scriptName}"
    }
}

println "Seed job completed successfully"
