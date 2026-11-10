package tracker.test;

import tracker.Autorun;
import tracker.AutorunArray;

/**
 * Checks that an autorun binds once to each field it reads, whatever the
 * order of the reads, nested autoruns and the number of autoruns sharing a
 * field (`Autorun.bindToAutorunArray` deduplication), and that it reruns
 * exactly once per change.
 */
class AutorunBindMain {

    static var failures = 0;

    static function main() {
        new AutorunBindContext();
        if (failures > 0) {
            trace('FAIL: $failures check(s) failed');
            Sys.exit(1);
        }
        trace('OK: autorun bindings are deduplicated');
    }

    public static function check(ok:Bool, message:String):Void {
        if (!ok) {
            failures++;
            trace('FAIL $message');
        }
    }

    /** How many times `autorun` is in the autorun array of `field` of `model` */
    public static function bindings(model:Fields, field:String, autorun:Autorun):Int {
        final array:AutorunArray = Reflect.field(model, field + 'Autoruns');
        if (array == null) return 0;
        var count = 0;
        for (i in 0...array.length) {
            if (array.get(i) == autorun) count++;
        }
        return count;
    }

}

class AutorunBindContext extends tracker.Entity {

    public function new() {
        super();

        final model = new Fields();
        final names = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];

        // One autorun reading every field several times, interleaved
        var runs = 0;
        final reader = new Autorun(() -> {
            runs++;
            for (round in 0...3) {
                for (name in names) {
                    Reflect.getProperty(model, name);
                }
            }
            model.a;
            model.h;
        });
        for (name in names) {
            AutorunBindMain.check(AutorunBindMain.bindings(model, name, reader) == 1, 'interleaved reads bind once to $name');
        }
        model.c = 1;
        AutorunBindMain.check(runs == 2, 'one rerun per change (runs $runs)');
        for (name in names) {
            AutorunBindMain.check(AutorunBindMain.bindings(model, name, reader) == 1, 'rerun binds once to $name');
        }

        // Many autoruns sharing one field, each also reading many fields:
        // the field array gets longer than the bound list and the reverse
        final sharing:Array<Autorun> = [];
        final sharedRuns:Array<Int> = [];
        for (i in 0...20) {
            sharedRuns.push(0);
            sharing.push(new Autorun(() -> {
                sharedRuns[i]++;
                model.a;
                if (i % 2 == 0) {
                    for (name in names) Reflect.getProperty(model, name);
                }
                model.a;
                model.b;
                model.a;
            }));
        }
        for (i in 0...20) {
            AutorunBindMain.check(AutorunBindMain.bindings(model, 'a', sharing[i]) == 1, 'shared field bound once by autorun $i');
            AutorunBindMain.check(AutorunBindMain.bindings(model, 'b', sharing[i]) == 1, 'second field bound once by autorun $i');
        }
        model.a = 2;
        for (i in 0...20) {
            AutorunBindMain.check(sharedRuns[i] == 2, 'autorun $i reran once (runs ${sharedRuns[i]})');
            AutorunBindMain.check(AutorunBindMain.bindings(model, 'a', sharing[i]) == 1, 'shared field bound once again by autorun $i');
        }

        // Nested autoruns: the outer one reads a field again after an inner
        // one bound to it (the outer autorun is no longer last in the array)
        var outerRuns = 0;
        var innerRuns = 0;
        var inner:Null<Autorun> = null;
        final outer = new Autorun(() -> {
            outerRuns++;
            model.e;
            model.f;
            if (inner != null) inner.destroy();
            inner = new Autorun(() -> {
                innerRuns++;
                model.e;
                model.g;
                model.e;
            });
            model.e;
            model.g;
            model.f;
        });
        AutorunBindMain.check(AutorunBindMain.bindings(model, 'e', outer) == 1, 'outer bound once to e');
        AutorunBindMain.check(AutorunBindMain.bindings(model, 'g', outer) == 1, 'outer bound once to g');
        AutorunBindMain.check(AutorunBindMain.bindings(model, 'e', inner) == 1, 'inner bound once to e');
        model.g = 3;
        AutorunBindMain.check(outerRuns == 2, 'outer reran once (runs $outerRuns)');
        AutorunBindMain.check(AutorunBindMain.bindings(model, 'e', outer) == 1, 'outer bound once to e after rerun');
        AutorunBindMain.check(AutorunBindMain.bindings(model, 'g', inner) == 1, 'new inner bound once to g');

        // A destroyed autorun is unbound and binds nothing more
        reader.destroy();
        for (name in names) {
            AutorunBindMain.check(AutorunBindMain.bindings(model, name, reader) == 0, 'destroyed autorun unbound from $name');
        }
        final runsBefore = runs;
        model.d = 4;
        AutorunBindMain.check(runs == runsBefore, 'destroyed autorun does not rerun');
    }

}

class Fields extends tracker.Model {
    @observe public var a:Int = 0;
    @observe public var b:Int = 0;
    @observe public var c:Int = 0;
    @observe public var d:Int = 0;
    @observe public var e:Int = 0;
    @observe public var f:Int = 0;
    @observe public var g:Int = 0;
    @observe public var h:Int = 0;
}
