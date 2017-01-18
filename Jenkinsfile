node('buildvm-devops') {

    // Expose properties for a parameterized build
    properties(
            [[$class              : 'ParametersDefinitionProperty',
              parameterDefinitions:
                      [
                              [$class: 'hudson.model.StringParameterDefinition', defaultValue: '', description: 'OSE Major Version', name: 'OSE_MAJOR'],
                              [$class: 'hudson.model.StringParameterDefinition', defaultValue: '', description: 'OSE Minor Version', name: 'OSE_MINOR']
                      ]
             ]]
    )

    stage('Merge and build') {
        // sh "./merge-and-build.sh --major=${OSE_MAJOR} --minor=${OSE_MINOR}"

        mail(to: 'jupierce@redhat.com',
                subject: "Job '${env.JOB_NAME}' (${env.BUILD_NUMBER}) ran",
                body: "Please go to ${env.BUILD_URL}.");

    }
}
