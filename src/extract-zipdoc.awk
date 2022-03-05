BEGIN                   { LDEL = "//" }

nr == 1   && $1 != LDEL  { tocode(); printline(); next; }
nr == 1   && $1 == LDEL  { fcomment(); printline(); next; }

code == 1 && $1 == LDEL  { tocomment(); printline(); next; }
code == 1 && $1 != LDEL  { printline(); next; }

code == 0 && $1 == LDEL  { printline(); next; }
code == 0 && $1 != LDEL  { tocode(); printline(); next; }

END                      { if(code == 1) print "\n```"; }

function tocode()    { print "\n```zig\n"; code = 1; }
function tocomment() { print "\n```\n"; code = 0; }
function fcomment()  { code = 0; }
function printline() {
    if($1 == LDEL) {
        $1 = "";
        print;
    } else {
        print;
    }
}
