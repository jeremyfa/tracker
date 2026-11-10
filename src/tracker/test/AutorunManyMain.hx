package tracker.test;

import tracker.Autorun;
import tracker.AutorunArray;

/**
 * Many autoruns sharing fields, with crossed reruns, destructions, creations,
 * repeated reads and reads in varying orders, checked against a model of the
 * expected bindings:
 *
 * - every autorun is bound exactly once to each field it read in its last run
 *   (never twice, also when it reads a field many times or after another
 *   autorun bound to it), and to no other field;
 * - a change invalidates exactly the autorun bound to the field, each once,
 *   in the order they bound to it (oldest first);
 * - the field arrays keep few empty slots (they are compacted).
 */
class AutorunManyMain {

    static var failures = 0;

    static function main() {
        new AutorunManyContext();
        if (failures > 0) {
            trace('FAIL: $failures check(s) failed');
            Sys.exit(1);
        }
        trace('OK: many autoruns bind once each and are invalidated in bind order');
    }

    public static function check(ok:Bool, message:String):Void {
        if (!ok) {
            failures++;
            if (failures <= 30) trace('FAIL $message');
        }
    }

    /** The slots of the autorun array of `field` of `model` (`null` ones included) */
    public static function entries(model:Any, field:String):Array<Autorun> {
        final array:AutorunArray = Reflect.field(model, field + 'Autoruns');
        final result:Array<Autorun> = [];
        if (array == null) return result;
        for (i in 0...array.length) {
            result.push(array.get(i));
        }
        return result;
    }

    /** The bound autoruns of `field` of `model`, in order */
    public static function bound(model:Any, field:String):Array<Autorun> {
        return entries(model, field).filter(a -> a != null);
    }

    public static function count(model:Any, field:String, autorun:Autorun):Int {
        var n = 0;
        for (a in entries(model, field)) {
            if (a == autorun) n++;
        }
        return n;
    }

}

class AutorunManyContext extends tracker.Entity {

    /** Deterministic pseudo random numbers */
    var seed:Int = 12345;

    function random(max:Int):Int {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        return (seed >> 8) % max;
    }

    public function new() {
        super();

        repeatedReads();
        manyFieldsAnyOrder();
        crossedReruns(300, 40);
    }

    /** One autorun reading one field many times in one run binds once */
    function repeatedReads() {
        final shared = new Shared();
        var runs = 0;
        final autorun = new Autorun(() -> {
            runs++;
            for (_ in 0...1000) shared.theme;
        });
        AutorunManyMain.check(AutorunManyMain.entries(shared, 'theme').length == 1, 'repeated reads: one slot (got ${AutorunManyMain.entries(shared, 'theme').length})');
        AutorunManyMain.check(AutorunManyMain.count(shared, 'theme', autorun) == 1, 'repeated reads: bound once');
        shared.theme++;
        AutorunManyMain.check(runs == 2, 'repeated reads: one rerun (runs $runs)');
        AutorunManyMain.check(AutorunManyMain.entries(shared, 'theme').length == 1, 'repeated reads: one slot after rerun');
        autorun.destroy();
        AutorunManyMain.check(AutorunManyMain.bound(shared, 'theme').length == 0, 'repeated reads: unbound when destroyed');
    }

    /**
     * Autoruns reading many fields (more than the scan limit of the binding
     * set) many times in shuffled orders, with other autoruns binding the
     * same fields between their reads (nested autoruns).
     */
    function manyFieldsAnyOrder() {
        final models = [for (_ in 0...300) new Item()];
        var outerRuns = 0;
        final inners:Array<Autorun> = [];
        final outer = new Autorun(() -> {
            outerRuns++;
            for (round in 0...5) {
                for (i in 0...models.length) {
                    final index = (i * 7 + round * 13) % models.length; // 7 is prime to the count: every field, in another order each round
                    models[index].value;
                    if (i % 9 == 0) {
                        // Another autorun binds a few of the same fields in between
                        inners.push(new Autorun(() -> {
                            models[index].value;
                            models[(index + 1) % models.length].value;
                            models[index].value;
                        }));
                    }
                }
            }
        });
        for (i in 0...models.length) {
            AutorunManyMain.check(AutorunManyMain.count(models[i], 'value', outer) == 1, 'many fields: outer bound once to field $i (got ${AutorunManyMain.count(models[i], 'value', outer)})');
            for (inner in inners) {
                AutorunManyMain.check(AutorunManyMain.count(models[i], 'value', inner) <= 1, 'many fields: inner bound at most once to field $i');
            }
        }
        models[17].value = 5;
        AutorunManyMain.check(outerRuns == 2, 'many fields: one rerun (runs $outerRuns)');
        for (i in 0...models.length) {
            AutorunManyMain.check(AutorunManyMain.count(models[i], 'value', outer) == 1, 'many fields: outer bound once to field $i after rerun');
        }
        outer.destroy();
        for (inner in inners) inner.destroy();
        for (i in 0...models.length) {
            AutorunManyMain.check(AutorunManyMain.bound(models[i], 'value').length == 0, 'many fields: field $i unbound');
        }
    }

    /**
     * `n` autoruns read a shared field (some twice, some in another order
     * with a second shared field) and their own field; over `rounds` rounds
     * some rerun (their own field changes), some are destroyed, some are
     * created, then the shared field changes: the expected invalidation
     * order is the order of their last binding.
     */
    function crossedReruns(n:Int, rounds:Int) {
        final shared = new Shared();
        final own:Array<Item> = [];
        final autoruns:Array<Autorun> = [];
        final alive:Array<Bool> = [];
        final runs:Array<Int> = [];
        final log:Array<Int> = [];
        // Expected bound autoruns of `theme` and `accent`, oldest binding first
        final themeOrder:Array<Int> = [];
        final accentOrder:Array<Int> = [];

        function rebound(order:Array<Int>, index:Int) {
            order.remove(index);
            order.push(index);
        }

        function create() {
            final index = autoruns.length;
            own.push(new Item());
            alive.push(true);
            runs.push(0);
            autoruns.push(null);
            final autorun = new Autorun(() -> {
                runs[index]++;
                log.push(index);
                final item = own[index];
                switch index % 4 {
                    case 0:
                        shared.theme;
                        item.value;
                    case 1:
                        // Shared field read twice, around the own field
                        shared.theme;
                        item.value;
                        shared.theme;
                    case 2:
                        // Another order, a second shared field
                        item.value;
                        shared.accent;
                        shared.theme;
                        shared.accent;
                    case _:
                        // Reads again after the own field changed in this run
                        item.value;
                        shared.theme;
                        shared.theme;
                }
            });
            autoruns[index] = autorun;
        }

        // Expected rebinding of autorun `index` after one of its runs
        function expectRun(index:Int) {
            rebound(themeOrder, index);
            if (index % 4 == 2) rebound(accentOrder, index);
        }

        for (_ in 0...n) {
            create();
            expectRun(autoruns.length - 1);
        }

        for (round in 0...rounds) {
            // Crossed actions
            var destroyedInRound = 0;
            for (_ in 0...(n >> 1)) {
                final index = random(autoruns.length);
                if (!alive[index]) continue;
                switch random(5) {
                    case 0:
                        autoruns[index].destroy();
                        alive[index] = false;
                        destroyedInRound++;
                        themeOrder.remove(index);
                        accentOrder.remove(index);
                    case 1:
                        create();
                        expectRun(autoruns.length - 1);
                    case _:
                        own[index].value++;
                        expectRun(index);
                }
            }

            // Bindings: exactly the expected autoruns, once each, in order
            checkOrder(shared, 'theme', themeOrder, autoruns, 'round $round');
            checkOrder(shared, 'accent', accentOrder, autoruns, 'round $round');
            for (index in 0...autoruns.length) {
                final expected = alive[index] ? 1 : 0;
                AutorunManyMain.check(AutorunManyMain.count(own[index], 'value', autoruns[index]) == expected, 'round $round: autorun $index bound $expected time(s) to its own field');
            }

            // Compaction: at most as many empty slots as bound ones, plus
            // the autoruns destroyed in this round (destroying does not compact)
            final themeEntries = AutorunManyMain.entries(shared, 'theme');
            final themeBound = AutorunManyMain.bound(shared, 'theme').length;
            AutorunManyMain.check(themeEntries.length <= 2 * (themeBound + destroyedInRound) + 2, 'round $round: theme array compacted (${themeEntries.length} slots for $themeBound bound)');

            // A change of a shared field: invalidated in bind order, once each
            final changeAccent = round % 3 == 2;
            final order = changeAccent ? accentOrder : themeOrder;
            final expectedLog = order.copy();
            final runsBefore = runs.copy();
            log.splice(0, log.length);
            if (changeAccent) shared.accent++; else shared.theme++;
            AutorunManyMain.check(log.join(',') == expectedLog.join(','), 'round $round: ${changeAccent ? 'accent' : 'theme'} invalidates in bind order (expected ${expectedLog.length}, got ${log.length})');
            for (index in 0...autoruns.length) {
                final expected = runsBefore[index] + (expectedLog.indexOf(index) != -1 ? 1 : 0);
                AutorunManyMain.check(runs[index] == expected, 'round $round: autorun $index ran ${runs[index] - runsBefore[index]} time(s)');
            }
            // They reran in that order and bound again in that order
            for (index in expectedLog) expectRun(index);
            checkOrder(shared, 'theme', themeOrder, autoruns, 'round $round after change');
            checkOrder(shared, 'accent', accentOrder, autoruns, 'round $round after change');
        }

        for (index in 0...autoruns.length) {
            if (alive[index]) autoruns[index].destroy();
        }
        AutorunManyMain.check(AutorunManyMain.bound(shared, 'theme').length == 0, 'all destroyed: theme unbound');
        AutorunManyMain.check(AutorunManyMain.bound(shared, 'accent').length == 0, 'all destroyed: accent unbound');
    }

    function checkOrder(shared:Shared, field:String, order:Array<Int>, autoruns:Array<Autorun>, label:String) {
        final actual = AutorunManyMain.bound(shared, field).map(a -> autoruns.indexOf(a));
        AutorunManyMain.check(actual.join(',') == order.join(','), '$label: $field bound in order (expected ${order.length}, got ${actual.length})');
    }

}

class Shared extends tracker.Model {
    @observe public var theme:Int = 0;
    @observe public var accent:Int = 0;
}

class Item extends tracker.Model {
    @observe public var value:Int = 0;
}
