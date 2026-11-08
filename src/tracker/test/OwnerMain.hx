package tracker.test;

import tracker.Owner;

/**
 * Checks that an object which is not an entity can own event handlers and
 * autoruns when it implements `tracker.Owner`: the handlers run while the
 * owner is alive, are removed when its host entity is destroyed, and the
 * destroy handler receives the owner itself.
 */
class OwnerMain {

    static var failures = 0;

    static function main() {

        final model = new OwnerModel();
        final host = new tracker.Entity();
        final light = new LightOwner(host);

        var changes = 0;
        model.onValueChange(light, (value, prev) -> changes++);

        var autorunRuns = 0;
        final autorun = new tracker.Autorun(() -> {
            model.value;
            autorunRuns++;
        });
        autorun.owner = light;

        model.value = 1;
        check(changes == 1, 'handler bound with a light owner runs (changes=$changes)');
        check(autorunRuns == 2, 'autorun owned by a light owner runs (runs=$autorunRuns)');

        var destroyedOwner:Owner = null;
        light.onceDestroy(null, owner -> destroyedOwner = owner);

        host.destroy();
        check(light.destroyed, 'light owner is destroyed with its host');
        check(destroyedOwner == light, 'destroy handler receives the light owner');

        model.value = 2;
        check(changes == 1, 'handler is unbound once the owner is destroyed (changes=$changes)');
        autorun.run();
        check(autorunRuns == 2, 'autorun does not run once its owner is destroyed (runs=$autorunRuns)');

        var threw = false;
        try {
            model.onValueChange(light, (value, prev) -> {});
        }
        catch (e:Dynamic) {
            threw = true;
        }
        check(threw, 'binding with a destroyed light owner throws');

        if (failures > 0) {
            trace('FAIL: $failures check(s) failed');
            Sys.exit(1);
        }
        trace('OK: a non-entity object can own handlers through tracker.Owner');
    }

    static function check(ok:Bool, message:String):Void {
        if (!ok) {
            failures++;
            trace('FAIL $message');
        }
    }

}

class OwnerModel extends tracker.Model {

    @observe public var value:Int = 0;

    public function new() {
        super();
    }

}

/**
 * An owner whose lifecycle is carried by a host entity
 * (the same shape as a persistent glaze component).
 */
class LightOwner implements Owner {

    final host:tracker.Entity;

    public var destroyed(get, never):Bool;
    function get_destroyed():Bool {
        return host.destroyed;
    }

    public function new(host:tracker.Entity) {
        this.host = host;
    }

    var handlers:Array<(Owner) -> Void> = null;
    var wrappers:Array<(Owner) -> Void> = null;

    public function onceDestroy(#if tracker_optional_owner ?owner:Owner #else owner:Null<Owner> #end, handler:(Owner) -> Void #if tracker_debug_events , ?pos:haxe.PosInfos #end):Void {
        if (handlers == null) {
            handlers = [];
            wrappers = [];
        }
        final wrapped = (_:Owner) -> {
            offDestroy(handler);
            handler(this);
        };
        handlers.push(handler);
        wrappers.push(wrapped);
        host.onceDestroy(owner, wrapped);
    }

    public function offDestroy(?handler:(Owner) -> Void):Void {
        if (handlers == null) return;
        if (handler == null) {
            for (wrapped in wrappers) host.offDestroy(wrapped);
            handlers = null;
            wrappers = null;
            return;
        }
        final index = handlers.indexOf(handler);
        if (index != -1) {
            host.offDestroy(wrappers[index]);
            handlers.splice(index, 1);
            wrappers.splice(index, 1);
        }
    }

}
