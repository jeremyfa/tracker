package tracker;

import tracker.Tracker.backend;

using tracker.Extensions;

class Autorun extends #if tracker_ceramic ceramic.Entity #else Entity #end {

/// Current autorun

    static var prevCurrent:Array<Autorun> = [];

    public static var current:Autorun = null;

/// Events

    @event function reset();

/// Properties

    @:noCompletion public var onRun:Void->Void = null;

    @:noCompletion public var afterRun:Void->Void = null;

    @:noCompletion public var owner:#if tracker_ceramic ceramic.Entity #else Entity #end = null;

    var boundAutorunArrays:Array<Array<Autorun>> = null;

    /**
     * Number of autorun arrays this autorun was bound to when it last
     * unbound. Used as a size hint when requesting a recycled array from the
     * pool: an autorun tends to bind a similar number of observables on every
     * run, so the pool can hand back an array that already has the right
     * capacity instead of an arbitrary one.
     */
    var lastBoundArraysCount:Int = 0;

    /**
     * Rolling lower bound of this autorun's array capacity bucket, used on
     * BOTH sides of the pool round-trip. On get, it makes the autorun request
     * at least the bucket it historically needed (a binder whose binding count
     * oscillates between scenes would otherwise request a small array on its
     * big phase - the size hint lags one run behind - and grow a brand new
     * large buffer every cycle). On recycle, it makes the array go back to
     * the bucket of its actual capacity (which never shrinks), not the bucket
     * of the last run's usage.
     */
    var boundArraysCapacityBucket:Int = 0;

    public var invalidated(default,null):Bool = false;

/// Lifecycle

    /**
     * Initialize a new autorun.
     * @param onRun The callback that will be executed and used to compute implicit bindings
     * @param afterRun
     *     (optional) A callback run right after `onRun`, not affecting implicit bindings.
     *     Useful when generating side effects without messing up binding dependencies.
     */
    public function new(onRun:Void->Void, ?afterRun:Void->Void #if tracker_debug_entity_allocs , ?pos:haxe.PosInfos #end) {

        super(#if tracker_debug_entity_allocs pos #end);

        this.onRun = onRun;
        this.afterRun = afterRun;

        // Run once to create initial binding and execute callback
        if (onRun != null) {
            run();
        }

    }

    override function destroy() {

        // Ensure everything gets unbound
        emitReset();

        // Remove any callback as we won't use it anymore
        onRun = null;
        afterRun = null;

        // Drop the owner reference so a destroyed autorun kept around by user
        // code (e.g. in an array awaiting cleanup) never retains its entity.
        owner = null;

        // Destroy
        super.destroy();

    }

    inline function willEmitReset():Void {

        unbindFromAllAutorunArrays();

    }

    public function run():Void {

        // Nothing to do if destroyed
        if (destroyed || (owner != null && owner.destroyed)) return;

        // We are not invalidated anymore as we are resetting state
        invalidated = false;

        // Unbind everything
        emitReset();

        // Set current autorun to self
        var _prevCurrent = current;
        current = this;
        var numPrevCurrent = prevCurrent.length;

        // Run (and bind) again
        onRun();
        if (afterRun != null) {
            unobserve();
            afterRun();
            reobserve();
        }

        // Restore previous current autorun
        while (numPrevCurrent < prevCurrent.length) prevCurrent.pop();
        current = _prevCurrent;

    }

    inline public function invalidate():Void {

        if (invalidated || destroyed) return;
        invalidated = true;

        unbindFromAllAutorunArrays();

        backend.onceImmediate(run);

    }

/// Static helpers

    /** Ensures current `autorun` won't be affected by the code after this call.
        `reobserve()` should be called to restore previous state. */
    #if tracker_inline_unobserve inline #end public static function unobserve():Void {

        // Set current autorun to null
        prevCurrent.push(current);
        current = null;

    }

    /** Resume observing values and resume affecting current `autorun` scope.
        This should be called after an `unobserve()` call. */
    #if tracker_inline_unobserve inline #end public static function reobserve():Void {

        Assert.assert(prevCurrent.length > 0, 'Cannot call reobserve() without calling unobserve() before.');

        // Restore previous current autorun
        current = prevCurrent.pop();

    }

    /** Unbinds and destroys current `autorun`. The name `cease()` has been chosed there
        so that it is unlikely to collide with other more common names suchs as `stop`, `unbind` etc...
        and should make it more recognizable, along with `observe()` and `unobserve()`.*/
    public static function cease():Void {

        if (current != null) {
            current.destroy();
            current = null;
        }
        else if (prevCurrent.length > 0) {
            final lastCurrent = prevCurrent[prevCurrent.length - 1];
            if (lastCurrent != null) {
                lastCurrent.destroy();
                prevCurrent[prevCurrent.length - 1] = null;
            }
        }

    }

    /** Executes the given function synchronously and ensures the
        current `autorun` scope won't be affected */
    public static function unobserved(func:Void->Void):Void {

        unobserve();
        func();
        reobserve();

    }

/// Autorun arrays

    public function bindToAutorunArray(autorunArray:Array<Autorun>):Void {

        // There is no reason to bind to an already invalidated autorun.
        // (this should not happen when correctly used by the way)
        if (invalidated || destroyed) return;

        // Check if this autorun array is already bound
        var alreadyBound = false;
        if (boundAutorunArrays == null) {
            boundAutorunArrays = getArrayOfAutorunArrays(lastBoundArraysCount, boundArraysCapacityBucket);
            boundArraysCapacityBucket = _lastServedSizeBucket;
        }
        else {
            for (i in 0...boundAutorunArrays.length) {
                if (boundAutorunArrays.unsafeGet(i) == autorunArray) {
                    alreadyBound = true;
                    break;
                }
            }
        }

        // If not, do it
        if (!alreadyBound) {
            var nullIndex = -1;
            var len = autorunArray.length;

            // Look for a null entry
            var i = len - 1;
            while (i >= 0) {
                var item = autorunArray.unsafeGet(i);
                if (item == null) {
                    nullIndex = i;
                    break;
                }
                i--;
            }

            if (nullIndex == -1) {
                // No null entry, just add a new one
                autorunArray.push(this);
            }
            else {
                // There is a null entry, shift by one items after and put at the end
                var lenMinus1 = len - 1;
                if (nullIndex < lenMinus1) {
                    for (i in nullIndex+1...len) {
                        var item = autorunArray.unsafeGet(i);
                        var iMinus1 = i - 1;
                        autorunArray.unsafeSet(iMinus1, item);
                    }
                }
                autorunArray.unsafeSet(lenMinus1, this);
            }
            boundAutorunArrays.push(autorunArray);
        }

    }

    public function unbindFromAllAutorunArrays():Void {

        if (boundAutorunArrays != null) {

            for (ii in 0...boundAutorunArrays.length) {
                var autorunArray = boundAutorunArrays.unsafeGet(ii);

                var numNulls = 0;
                var len = autorunArray.length;
                for (i in 0...len) {
                    var autorun = autorunArray.unsafeGet(i);
                    if (autorun != null) {
                        if (autorun == this) {
                            autorunArray.unsafeSet(i, null);
                            break;
                        }
                    }
                }
            }

            lastBoundArraysCount = boundAutorunArrays.length;
            var lengthBucket = poolSizeBucket(lastBoundArraysCount);
            if (lengthBucket > boundArraysCapacityBucket) boundArraysCapacityBucket = lengthBucket;
            recycleArrayOfAutorunArrays(boundAutorunArrays, boundArraysCapacityBucket);
            boundAutorunArrays = null;
        }

    }

/// More static helpers

    public static function invalidateAutorunArray(autorunArray:Array<Autorun>):Void {

        for (i in 0...autorunArray.length) {
            var autorun = autorunArray[i];
            if (autorun != null) {
                autorun.invalidate();
            }
        }

        inline recycleAutorunArray(autorunArray);

    }

/// Recycling autorun arrays

    // Recycled arrays are grouped in size buckets, based on their length at
    // recycle time (a lower bound of their actual capacity, since an array's
    // capacity never shrinks). Requests provide a size hint so the pool can
    // return an array whose capacity already matches the expected usage: a
    // large binder gets back a large array (no repeated regrowth), and small
    // users never end up holding large-capacity buffers - without this,
    // recycled arrays get shuffled arbitrarily between users and more and
    // more of them ratchet up to large capacities over time.
    static inline final POOL_SIZE_BUCKETS:Int = 5;

    inline static function poolSizeBucket(size:Int):Int {
        return size <= 8 ? 0 : size <= 32 ? 1 : size <= 128 ? 2 : size <= 512 ? 3 : 4;
    }

    // Single-stack pool: unlike the per-autorun binding arrays below, the
    // observable-side AutorunArrays are homogeneous (an observable's watcher
    // count is small and similar across observables) and their callers have
    // no size hint to provide, so size buckets would starve the pool (every
    // recycled array would land in a bucket that hintless get() calls never
    // look into). The original single stack recirculates everything.
    static var _autorunArrays:Array<Array<Autorun>> = [];
    static var _autorunArraysLen:Int = 0;

    public static function getAutorunArray():Array<Autorun> {

        if (_autorunArraysLen > 0) {
            _autorunArraysLen--;
            var array = _autorunArrays[_autorunArraysLen];
            _autorunArrays[_autorunArraysLen] = null;
            return array;
        }
        else {
            return [];
        }

    }

    public static function recycleAutorunArray(array:Array<Autorun>):Void {

        #if cpp
        untyped array.__SetSize(0);
        #else
        array.splice(0, array.length);
        #end

        _autorunArrays[_autorunArraysLen] = array;
        _autorunArraysLen++;

    }

/// Recycling array of autorun arrays

    static var _arrayOfAutorunArrays:Array<Array<Array<Array<Autorun>>>> = [[], [], [], [], []];
    static var _arrayOfAutorunArraysLen:Array<Int> = [0, 0, 0, 0, 0];

    /**
     * Size bucket the last `getArrayOfAutorunArrays()` call actually served
     * from (it can be lower than the requested hint, or 0 for a fresh array).
     * Read it right after the call: callers keep it and hand it back on
     * recycle as a permanent lower bound of the array's capacity bucket.
     */
    public static var _lastServedSizeBucket(default, null):Int = 0;

    public static function getArrayOfAutorunArrays(sizeHint:Int = 0, capacityBucketHint:Int = 0):Array<Array<Autorun>> {

        var sizeBucket = poolSizeBucket(sizeHint);
        if (capacityBucketHint > sizeBucket) sizeBucket = capacityBucketHint;
        while (sizeBucket >= 0) {
            var len = _arrayOfAutorunArraysLen.unsafeGet(sizeBucket);
            if (len > 0) {
                len--;
                _arrayOfAutorunArraysLen.unsafeSet(sizeBucket, len);
                var stack = _arrayOfAutorunArrays.unsafeGet(sizeBucket);
                var array = stack.unsafeGet(len);
                stack.unsafeSet(len, null);
                _lastServedSizeBucket = sizeBucket;
                return array;
            }
            sizeBucket--;
        }

        _lastServedSizeBucket = 0;
        return [];

    }

    public static function recycleArrayOfAutorunArrays(array:Array<Array<Autorun>>, capacityBucketHint:Int = 0):Void {

        var sizeBucket = poolSizeBucket(array.length);
        if (capacityBucketHint > sizeBucket) sizeBucket = capacityBucketHint;

        #if cpp
        untyped array.__SetSize(0);
        #else
        array.splice(0, array.length);
        #end

        var len = _arrayOfAutorunArraysLen.unsafeGet(sizeBucket);
        _arrayOfAutorunArrays.unsafeGet(sizeBucket)[len] = array;
        _arrayOfAutorunArraysLen.unsafeSet(sizeBucket, len + 1);

    }

}
