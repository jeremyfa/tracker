package tracker;

import tracker.Tracker.backend;

using tracker.Extensions;

class Autorun extends #if tracker_ceramic ceramic.Entity #else Entity #end {

/// Current autorun

    static final prevCurrent:Array<Autorun> = [];

    public static var current:Autorun = null;

/// Events

    @event function reset();

/// Properties

    @:noCompletion public var onRun:Void->Void = null;

    @:noCompletion public var afterRun:Void->Void = null;

    @:noCompletion public var owner:Owner = null;

    /**
     * The field arrays this autorun is bound to and its slot in each of them
     * (`null` until the first binding, kept from run to run, recycled when
     * the autorun is destroyed).
     */
    var bindings:AutorunBindings = null;

    public var invalidated(default,null):Bool = false;

    /** `run` as a function value, made on the first invalidation */
    var runCallback:() -> Void = null;

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

        // Give the (now empty) bindings back
        var bindings = this.bindings;
        if (bindings != null && bindings.count == 0) {
            this.bindings = null;
            AutorunBindings.recycle(bindings);
        }

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

        // `run` as a function value, made once (a bound method allocates each time it is taken)
        var runCallback = this.runCallback;
        if (runCallback == null) {
            runCallback = run;
            this.runCallback = runCallback;
        }
        backend.onceImmediate(runCallback);

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

    public function bindToAutorunArray(autorunArray:AutorunArray):Void {

        // There is no reason to bind to an already invalidated autorun.
        // (this should not happen when correctly used by the way)
        if (invalidated || destroyed) return;

        // Read again right after binding (the common case): already bound
        if (autorunArray.lastBinder == this) return;

        var bindings = this.bindings;
        if (bindings == null) {
            bindings = AutorunBindings.get();
            this.bindings = bindings;
        }
        else if (bindings.count > 0 && bindings.contains(autorunArray)) {
            // Already bound (another autorun bound to it since): O(1), see `AutorunBindings`
            autorunArray.lastBinder = this;
            return;
        }

        // Bind: append to the field array, remember the slot
        var slot = autorunArray.add(this, bindings.count);
        bindings.add(autorunArray, slot);
        autorunArray.lastBinder = this;

    }

    public function unbindFromAllAutorunArrays():Void {

        var bindings = this.bindings;
        if (bindings != null && bindings.count > 0) {

            // Clear each slot directly: O(1) per binding
            var arrays = bindings.arrays;
            var slots = bindings.slots;
            for (i in 0...bindings.count) {
                arrays.unsafeGet(i).remove(this, slots.unsafeGet(i));
            }

            bindings.clear();
        }

    }

/// More static helpers

    public static function invalidateAutorunArray(autorunArray:AutorunArray):Void {

        // Oldest binding first. Invalidated autoruns unbind (their slot
        // becomes null) while this runs; nothing binds to this array any more
        // (the field dropped it), so it is never compacted meanwhile.
        var autoruns = autorunArray.autoruns;
        var i = 0;
        while (i < autoruns.length) {
            var autorun = autoruns.unsafeGet(i);
            if (autorun != null) {
                autorun.invalidate();
            }
            i++;
        }

        inline recycleAutorunArray(autorunArray);

    }

/// Recycling autorun arrays

    // Single stack pool: the observable side arrays are homogeneous (an
    // observable's watcher count is small and similar across observables)
    // and their callers have no size hint to provide.
    static var _autorunArrays:Array<AutorunArray> = [];
    static var _autorunArraysLen:Int = 0;

    public static function getAutorunArray():AutorunArray {

        if (_autorunArraysLen > 0) {
            _autorunArraysLen--;
            var array = _autorunArrays[_autorunArraysLen];
            _autorunArrays[_autorunArraysLen] = null;
            return array;
        }
        else {
            return new AutorunArray();
        }

    }

    public static function recycleAutorunArray(array:AutorunArray):Void {

        array.clear();

        _autorunArrays[_autorunArraysLen] = array;
        _autorunArraysLen++;

    }

}
