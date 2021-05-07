package tracker;

import haxe.macro.Context;
import haxe.macro.Expr;

class Assert {

    /** Assert the expression evaluates to `true`.
        This check is only done in `debug` builds and doesn't affect `release` builds. */
    macro public static function assert(expr:Expr, ?reason:ExprOf<String>) {

#if (debug || tracker_assert)
        var str = haxe.macro.ExprTools.toString(expr);

        reason = switch(reason) {
            case macro null: macro ' (Assertion failure)';
            case _: macro ' (' + $reason + ')';
        }

        return macro @:pos(Context.currentPos()) {
            if (!$expr) {
                tracker.Tracker.backend.error($v{str} + $reason);
                throw $v{str} + $reason;
            }
        }
#else
        return macro null;
#end

    }

}
