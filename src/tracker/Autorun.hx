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
            boundAutorunArrays = getArrayOfAutorunArrays();
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

            recycleArrayOfAutorunArrays(boundAutorunArrays);
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

        recycleAutorunArray(autorunArray);

    }

/// Recycling autorun arrays

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

    static var _arrayOfAutorunArrays:Array<Array<Array<Autorun>>> = [];
    static var _arrayOfAutorunArraysLen:Int = 0;

    inline public static function getArrayOfAutorunArrays():Array<Array<Autorun>> {

        if (_arrayOfAutorunArraysLen > 0) {
            _arrayOfAutorunArraysLen--;
            var array = _arrayOfAutorunArrays[_arrayOfAutorunArraysLen];
            _arrayOfAutorunArrays[_arrayOfAutorunArraysLen] = null;
            return array;
        }
        else {
            return [];
        }

    }

    inline public static function recycleArrayOfAutorunArrays(array:Array<Array<Autorun>>):Void {

        #if cpp
        untyped array.__SetSize(0);
        #else
        array.splice(0, array.length);
        #end

        _arrayOfAutorunArrays[_arrayOfAutorunArraysLen] = array;
        _arrayOfAutorunArraysLen++;

    }

}
