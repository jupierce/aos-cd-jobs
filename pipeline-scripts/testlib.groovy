import groovy.transform.Field
@Field private First = '1'

def init(msg) {
    this.First = msg
}

class Other {
    private t;
    private e
    public Other(e, m) {
        this.e = e
        this.t = m
    }
    public hi() {
        e.sayit(this.t)
    }
}

def get(msg=null) {
    if (!msg) {
        msg = First
    }
    return new Other(this, msg)
}

def sayit(text) {
    echo(text)
}



return this