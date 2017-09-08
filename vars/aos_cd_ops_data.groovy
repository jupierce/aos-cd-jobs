class aos_cd_ops_data implements Serializable {

    def getClusterList(branch) {
        if ( branch.startsWith("cluster") || branch.contains("starter") ) {
            return [ "starter:int:free-key",
                    "starter:int:free-int",
                    "starter:stg:free-stg",
                    "starter:prod:starter-us-east-1",
                    "starter:prod:starter-us-east-2",
                    "starter:prod:starter-us-west-1",
                    "starter:prod:starter-us-west-2",
            ]
        }

        if ( branch.contains("dedicated") ) {
            return [ "dedicated:stg:yocum-test-5",
            ]
        }
        
        
        return [ "int:!UnknkownClusterGroup!-" + branch ]
    }

}
