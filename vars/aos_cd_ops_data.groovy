class aos_cd_ops_data implements Serializable {

    def getClusterList(group) {
        if ( group == "starter" ) {
            return [ "int:free-key",
                    "int:free-int",
                    "stg:free-stg",
                    "prod:starter-us-east-1",
                    "prod:starter-us-east-2",
                    "prod:starter-us-west-1",
                    "prod:starter-us-west-2",
            ]
        }
        return [ "int:!UnknkownClusterGroup-" + group ]
    }

}
