class aos_cd_ops_data implements Serializable {

    def getClusterList(branch) {
        if ( branch.startsWith("cluster") || branch.contains("starter") || branch.contains("online") ) {
            return [ "online:int:free-key",
                    "online:int:free-int",
                    "online:stg:free-stg",
                    "online:prod:starter-us-east-1",
                    "online:prod:starter-us-east-2",
                    "online:prod:starter-us-west-1",
                    "online:prod:starter-us-west-2",
            ]
        }

        if ( branch.contains("dedicated") ) {
            return [ "dedicated:stg:yocum-test-5",
            ]
        }
        
        
        return [ "int:!UnknkownClusterGroup!-" + branch ]
    }

}
