package tracker.test;

class InoutInMain {

    static function main() {
        new InoutInContext();
    }

}

class InoutInContext extends tracker.Entity {

    public function new() {
        super();

        var m = new TestInModel();

        // Default _out_sum is 0. sum should read it via the inline getter body.
        trace('initial: sum=${m.sum} _out_sum=${m._out_sum}');

        // Simulate receiving an update from the wire by setting _out_sum directly.
        // The original "return 999" body should never run — it was discarded by the macro.
        m._out_sum = 42;

        trace('after wire push: sum=${m.sum} _out_sum=${m._out_sum}');

        if (m.sum != 42) {
            trace('FAIL: expected sum == 42, got ${m.sum}');
            Sys.exit(1);
        }
        trace('OK: @inout @compute reads from _out_<name> in @computeIn mode');
    }

}

@computeIn
class TestInModel extends tracker.Model {

    // The body "return 999" should never be executed — the macro replaces it.
    @inout @compute public function sum():Int return 999;

}
