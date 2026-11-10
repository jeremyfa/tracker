package tracker;

using tracker.Extensions;

/**
 * The bindings of an autorun (internal to tracker): for each `AutorunArray`
 * it is bound to, the array and the slot it holds there, in bind order.
 *
 * Kept by the autorun from run to run (cleared, not freed, when it unbinds)
 * and recycled when the autorun is destroyed, so that binding allocates
 * nothing in the steady state.
 *
 * Finding whether an array is already bound costs O(1): a scan of the
 * bindings while there are at most `SCAN_MAX` of them, then an open
 * addressing set of the array ids (`set`, built at the first binding past
 * `SCAN_MAX`, emptied with the bindings).
 */
@:allow(tracker.Autorun)
@:allow(tracker.AutorunArray)
class AutorunBindings {

    /** Up to this number of bindings, `contains()` scans the list */
    static inline final SCAN_MAX:Int = 8;

    /** Bound arrays, in bind order (valid up to `count`) */
    final arrays:Array<AutorunArray> = [];

    /** Slot of each binding in its array (valid up to `count`) */
    final slots:Array<Int> = [];

    /** Number of bindings */
    var count:Int = 0;

    /**
     * Set of the bound arrays when there are more than `SCAN_MAX`: open
     * addressing with linear probing on `AutorunArray.id`, each entry is a
     * binding index plus one (0 is empty). Its length is a power of two at
     * least twice `count`.
     */
    var set:Array<Int> = null;

    /** Whether `set` holds the bindings (`count > SCAN_MAX`) */
    var hashed:Bool = false;

    function new() {}

    /**
     * Mixes the high bits of `id` into the low ones (the set is indexed by
     * the low bits). The factor is small enough for the product to stay
     * exact on JS (ids below 2^31 times a factor below 2^21).
     */
    inline static function hash(id:Int):Int {
        var h = id * 0x9e3b5;
        return h ^ (h >>> 16);
    }

    /** Whether `array` is bound */
    function contains(array:AutorunArray):Bool {

        var count = this.count;
        if (!hashed) {
            for (i in 0...count) {
                if (arrays.unsafeGet(i) == array) return true;
            }
            return false;
        }

        var set = this.set;
        var mask = set.length - 1;
        var i = hash(array.id) & mask;
        while (true) {
            var entry = set.unsafeGet(i);
            if (entry == 0) return false;
            if (arrays.unsafeGet(entry - 1) == array) return true;
            i = (i + 1) & mask;
        }

    }

    /** Records a new binding to `array` at `slot` */
    function add(array:AutorunArray, slot:Int):Void {

        var index = count;
        if (index < arrays.length) {
            arrays.unsafeSet(index, array);
            slots.unsafeSet(index, slot);
        }
        else {
            arrays.push(array);
            slots.push(slot);
        }
        count = index + 1;

        if (hashed) {
            if (count * 2 > set.length) {
                rehash();
            }
            else {
                insert(index);
            }
        }
        else if (count > SCAN_MAX) {
            rehash();
            hashed = true;
        }

    }

    /** Puts binding `index` in the set (which has room for it) */
    inline function insert(index:Int):Void {

        var set = this.set;
        var mask = set.length - 1;
        var i = hash(arrays.unsafeGet(index).id) & mask;
        while (set.unsafeGet(i) != 0) {
            i = (i + 1) & mask;
        }
        set.unsafeSet(i, index + 1);

    }

    /** Makes the set large enough for `count` bindings and puts all of them in it */
    function rehash():Void {

        var size = 32;
        while (size < count * 2) size *= 2;

        var set = this.set;
        if (set == null || set.length < size) {
            set = [];
            for (_ in 0...size) set.push(0);
            this.set = set;
        }
        else {
            // Already large enough (kept from a previous run) and empty
        }

        for (index in 0...count) {
            insert(index);
        }

    }

    /** Removes every binding (each array was told by the autorun) */
    function clear():Void {

        if (hashed) {
            // Every entry is known to be there: no need to stop at an empty one
            var set = this.set;
            var mask = set.length - 1;
            for (index in 0...count) {
                var entry = index + 1;
                var i = hash(arrays.unsafeGet(index).id) & mask;
                while (set.unsafeGet(i) != entry) {
                    i = (i + 1) & mask;
                }
                set.unsafeSet(i, 0);
            }
            hashed = false;
        }

        for (index in 0...count) {
            arrays.unsafeSet(index, null);
        }
        count = 0;

    }

/// Pool

    static var pool:Array<AutorunBindings> = [];
    static var poolLength:Int = 0;

    /** Bindings with more room than this are left to the garbage collector when their autorun is destroyed */
    static inline final POOL_MAX_CAPACITY:Int = 256;

    static function get():AutorunBindings {

        if (poolLength > 0) {
            poolLength--;
            var bindings = pool.unsafeGet(poolLength);
            pool.unsafeSet(poolLength, null);
            return bindings;
        }
        return new AutorunBindings();

    }

    /** Takes back the (cleared) bindings of a destroyed autorun */
    static function recycle(bindings:AutorunBindings):Void {

        if (bindings.arrays.length > POOL_MAX_CAPACITY) return;
        if (bindings.set != null && bindings.set.length > POOL_MAX_CAPACITY * 4) {
            bindings.set = null;
        }

        if (poolLength < pool.length) {
            pool.unsafeSet(poolLength, bindings);
        }
        else {
            pool.push(bindings);
        }
        poolLength++;

    }

}
