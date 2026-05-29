package tracker.test;

class InoutMixedMain {

    static function main() {
        new InoutMixedContext();
    }

}

class InoutMixedContext extends tracker.Entity {

    public function new() {
        super();

        // OutModel: @computeOut, autorun propagates sum() to _out_sum
        var out = new MixedOutModel();
        out.a = 3;
        out.b = 4;
        if (out._out_sum != 7) {
            trace('FAIL OUT: expected _out_sum == 7, got ${out._out_sum}');
            Sys.exit(1);
        }

        // InModel: @computeIn, sum reads _out_sum, original body discarded
        var inp = new MixedInModel();
        inp._out_sum = 99;
        if (inp.sum != 99) {
            trace('FAIL IN: expected sum == 99, got ${inp.sum}');
            Sys.exit(1);
        }

        // LocalModel: @inout @compute but no class metadata → silent fallback,
        // behaves like a plain @compute (executes original body).
        var loc = new LocalModel();
        loc.a = 10;
        loc.b = 5;
        if (loc.sum != 15) {
            trace('FAIL LOCAL: expected sum == 15, got ${loc.sum}');
            Sys.exit(1);
        }

        trace('OK: mixed @computeOut/@computeIn/silent-fallback all work with -D tracker_compute_inout');
    }

}

@computeOut
class MixedOutModel extends tracker.Model {
    @observe public var a:Int = 0;
    @observe public var b:Int = 0;
    @inout @compute public function sum():Int return a + b;
}

@computeIn
class MixedInModel extends tracker.Model {
    @inout @compute public function sum():Int return 999;
}

// No @computeOut nor @computeIn → silent fallback to plain @compute
class LocalModel extends tracker.Model {
    @observe public var a:Int = 0;
    @observe public var b:Int = 0;
    @inout @compute public function sum():Int return a + b;
}
