package tracker;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

class Until {

    /**
     * Wait until the observable condition becomes true to execute the callback once (and only once). Creates an `Autorun` instance and returns it.
     * Usage:
     * ```haxe
     * // Resulting autorun attached to "this" if available and a valid entity
     * until(something == true, callback);
     * // Add "null" if you don't want it to be attached to anything
     * until(null, something == true, callback);
     * // Attach to another entity
     * until(entity, something == true, callback);
     * // Add a timeout + a timeout callback
     * until(
     *     something == true, callback,
     *     5.0, timeoutCallback
     * );
     * ```
     */
    macro public static function until(exprs:Array<Expr>):ExprOf<tracker.Autorun> {

        var condition;
        var callback;
        var instance;
        var timeout;
        var timeoutCallback;

        if (exprs.length == 3 || exprs.length == 5) {
            condition = exprs[1];
            callback = exprs[2];
            instance = exprs[0];

            if (exprs.length == 5) {
                timeout = exprs[3];
                timeoutCallback = exprs[4];
            }
            else {
                timeout = macro -1;
                timeoutCallback = macro null;
            }
        }
        else {
            condition = exprs[0];
            callback = exprs[1];
            try {
                // We try to resolve `this` type.
                // If it succeeds, we can attach the autorun to it
                Context.typeExpr(macro this);
                instance = macro this;
            }
            catch (e) {
                // If `this` typing failed, it's likely because
                // it is not available and we are calling from
                // a static, class method, let's not use it then
                instance = macro null;
            }

            if (exprs.length == 4) {
                timeout = exprs[2];
                timeoutCallback = exprs[3];
            }
            else {
                timeout = macro -1;
                timeoutCallback = macro null;
            }
        }

        return macro @:privateAccess tracker.Until._until($instance, function() {
            return $condition;
        }, $callback, $timeout, $timeoutCallback);

    }

    #if !macro

    static function _until(instance:Any, condition:()->Bool, callback:()->Void, timeout:Float = -1, ?timeoutCallback:()->Void):tracker.Autorun {

        var run = function() {

            final result = condition();
            Autorun.unobserve();

            if (result) {
                Autorun.cease();
                callback();
            }

            Autorun.reobserve();

        };

        var untilAutorun = null;

        if (instance != null) {

            #if tracker_ceramic
            if (instance is ceramic.Entity) {
                final ceramicEntity:ceramic.Entity = cast instance;
                untilAutorun = ceramicEntity.autorun(run);
            }
            #else
            if (instance is Entity) {
                final trackerEntity:Entity = cast instance;
                untilAutorun = trackerEntity.autorun(run);
            }
            #end

        }

        if (untilAutorun == null) {
            untilAutorun = new Autorun(run);
        }

        if (timeout > 0) {
            Tracker.backend.delay(untilAutorun, timeout, () -> {
                if (!untilAutorun.destroyed) {
                    untilAutorun.destroy();
                    if (timeoutCallback != null) {
                        timeoutCallback();
                    }
                }
            });
        }

        return untilAutorun;

    }

    #end

}
