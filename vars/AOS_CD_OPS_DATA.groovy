
class AOS_CD_OPS_DATA implements Serializable {
    def getClusterList() {
        return [ "int:test-key",
                "int:free-int",
                "stg:free-stg",
                "prod:starter-us-east-1",
                "prod:starter-us-east-2",
                "prod:starter-us-west-1",
                "prod:starter-us-west-2",
        ]
    }
}
