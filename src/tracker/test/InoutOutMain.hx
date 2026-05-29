package tracker.test;

class InoutOutMain {

    static function main() {
        new InoutOutContext();
    }

}

class InoutOutContext extends tracker.Entity {

    public function new() {
        super();

        var m = new TestOutModel();

        // After construction, the @autorun has already fired once.
        // sum returns a + b = 0, so _out_sum should be 0.
        trace('initial: a=${m.a} b=${m.b} sum=${m.sum} _out_sum=${m._out_sum}');

        m.a = 5;
        m.b = 7;

        // Mutations to @observe a and b should trigger the autorun
        // which recomputes sum and updates _out_sum to 12.
        trace('after set: a=${m.a} b=${m.b} sum=${m.sum} _out_sum=${m._out_sum}');

        if (m._out_sum != 12) {
            trace('FAIL: expected _out_sum == 12, got ${m._out_sum}');
            Sys.exit(1);
        }
        trace('OK: @inout @compute propagation works in @computeOut mode');
    }

}

@computeOut
class TestOutModel extends tracker.Model {

    @observe public var a:Int = 0;

    @observe public var b:Int = 0;

    @inout @compute public function sum():Int return a + b;

}
