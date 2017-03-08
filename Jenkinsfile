
properties(
    [
        [
            $class: 'BuildDiscarderProperty',
            strategy: [$class: 'LogRotator', numToKeepStr: '60']
        ],
        pipelineTriggers([cron('0 6 * * *')]), /* daily at 6am */
    ]
)

build job: '../aos-cd-builds/build%2Fose',
    parameters: [   [$class: 'StringParameterValue', name: 'OSE_MAJOR', value: '3'],
                    [$class: 'StringParameterValue', name: 'OSE_MINOR', value: '5'],
                ]
