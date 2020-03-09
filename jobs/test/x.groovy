node {
    checkout scm
    testlib1 = load('pipeline-scripts/testlib.groovy')
    testlib1.init('this is 1')
    //testlib.hi('sayit')

    testlib2 = load('pipeline-scripts/testlib.groovy')
    testlib2.init('this is 2')
    //testlib.hi('sayit')
    o1 = testlib1.get()
    o2 = testlib2.get()

    o1.hi()
    o2.hi()
}