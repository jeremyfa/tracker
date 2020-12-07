package tracker;

#if !tracker_custom_array_pool

class ArrayPool {

    static var ALLOC_STEP = 10;

/// Factory

    static var dynPool10:ArrayPool = new ArrayPool(10);

    static var dynPool100:ArrayPool = new ArrayPool(100);

    static var dynPool1000:ArrayPool = new ArrayPool(1000);

    static var dynPool10000:ArrayPool = new ArrayPool(10000);

    static var dynPool100000:ArrayPool = new ArrayPool(100000);

    static var didNotifyLargePool:Bool = false;

    public static function pool(size:Int):ArrayPool {

        if (size <= 10) {
            return cast dynPool10;
        }
        else if (size <= 100) {
            return cast dynPool100;
        }
        else if (size <= 1000) {
            return cast dynPool1000;
        }
        else if (size <= 10000) {
            return cast dynPool10000;
        }
        else if (size <= 100000) {
            return cast dynPool100000;
        }
        else {
            if (!didNotifyLargePool) {
                didNotifyLargePool = true;
                Tracker.backend.delay(null, 0.5, () -> {
                    didNotifyLargePool = false;
                });

                trace('[warning] You should avoid asking a pool for arrays with more than 100000 elements (asked: $size) because it needs allocating a temporary one-time pool each time for that.');
            }
            return new ArrayPool(size);
        }

    }

/// Properties

    var arrays:ReusableArray<Any> = null;

    var nextFree:Int = 0;

    var arrayLengths:Int;

/// Lifecycle

    public function new(arrayLengths:Int) {

        this.arrayLengths = arrayLengths;

    }

/// Public API

    public function get(#if tracker_debug_array_pool ?pos:haxe.PosInfos #end):ReusableArray<Any> {

        #if tracker_debug_array_pool
        haxe.Log.trace('pool.get', pos);
        #end

        if (arrays == null) arrays = new ReusableArray(ALLOC_STEP);
        else if (nextFree >= arrays.length) arrays.length += ALLOC_STEP;

        var result:ReusableArray<Any> = arrays.get(nextFree);
        if (result == null) {
            result = new ReusableArray(arrayLengths);
            arrays.set(nextFree, result);
        }
        @:privateAccess result._poolIndex = nextFree;

        // Compute next free item
        while (true) {
            nextFree++;
            if (nextFree == arrays.length) break;
            var item = arrays.get(nextFree);
            if (item == null) break;
            if (@:privateAccess item._poolIndex == -1) break;
        }
        
        return cast result;

    }

    public function release(array:ReusableArray<Any>):Void {
        
        #if tracker_debug_array_pool
        haxe.Log.trace('pool.release', pos);
        #end

        var poolIndex = @:privateAccess array._poolIndex;
        @:privateAccess array._poolIndex = -1;
        if (nextFree > poolIndex) nextFree = poolIndex;
        for (i in 0...array.length) {
            array.set(i, null);
        }

    }

}

#end
