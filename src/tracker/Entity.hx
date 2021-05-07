package tracker;

#if !tracker_custom_entity

#if (!macro && !display && !completion)
@:autoBuild(tracker.macros.EntityMacro.build())
#end
class Entity implements Events {

/// Properties

    public var id:String = null;

    /** Internal flag to keep track of current entity state:
     - 0: Entity is not destroyed, can be used normally
     - -1: Entity is marked destroyed still allowing calls to super.destroy()
     - -2: Entity is marked destroyed and additional calls to destroy() are ignored
     - -3: Entity root is destroyed (Entity.destroy() was called). Additional calls to destroy() are ignored
     */
    var _lifecycleState:Int = 0;

    public var destroyed(get,never):Bool;
    #if !haxe_server inline #end function get_destroyed():Bool {
        return _lifecycleState < 0;
    }

    #if tracker_debug_entity_allocs
    var posInfos:haxe.PosInfos;

    static var debugEntityAllocsInitialized = false;
    static var numEntityAliveInMemoryByClass = new Map<String,Int>();
    #if cpp
    static var numEntityDestroyedButInMemoryByClass = new Map<String,Int>();
    static var destroyedWeakRefs = new Map<String,Array<cpp.vm.WeakRef<Entity>>>();
    #end
    #end

/// Events

    @event function destroy(entity:tracker.Entity);

/// Lifecycle

    /** Create a new entity */
    public function new(#if tracker_debug_entity_allocs ?pos:haxe.PosInfos #end) {

        // Default implementation

        #if tracker_debug_entity_allocs
        this.posInfos = pos;

        if (!debugEntityAllocsInitialized) {
            debugEntityAllocsInitialized = true;
            Timer.interval(null, 5.0, function() {
                #if cpp
                cpp.vm.Gc.run(true);
                #end

                var allClasses:Array<String> = [];
                var usedKeys = new Map<String, Int>();
                if (numEntityAliveInMemoryByClass != null) {
                    for (key in numEntityAliveInMemoryByClass.keys()) {
                        if (!usedKeys.exists(key)) {
                            allClasses.push(key);
                            usedKeys.set(key, numEntityAliveInMemoryByClass.get(key));
                        }
                        else {
                            usedKeys.set(key, usedKeys.get(key) + numEntityAliveInMemoryByClass.get(key));
                        }
                    }
                }
                if (numEntityDestroyedButInMemoryByClass != null) {
                    for (key in numEntityDestroyedButInMemoryByClass.keys()) {
                        if (!usedKeys.exists(key)) {
                            allClasses.push(key);
                            usedKeys.set(key, numEntityDestroyedButInMemoryByClass.get(key));
                        }
                        else {
                            usedKeys.set(key, usedKeys.get(key) + numEntityDestroyedButInMemoryByClass.get(key));
                        }
                    }
                }
                allClasses.sort(function(a:String, b:String) {
                    var numA = 0;
                    if (numEntityDestroyedButInMemoryByClass.exists(a)) {
                        numA = numEntityDestroyedButInMemoryByClass.get(a);
                    }
                    var numB = 0;
                    if (numEntityDestroyedButInMemoryByClass.exists(b)) {
                        numB = numEntityDestroyedButInMemoryByClass.get(b);
                    }
                    return numA - numB;
                });
                tracker.Shortcuts.log(' - entities in memory -');
                for (clazz in allClasses) {
                    tracker.Shortcuts.log('    $clazz / ${usedKeys.get(clazz)} / alive=${numEntityAliveInMemoryByClass.get(clazz)} destroyed=${numEntityDestroyedButInMemoryByClass.get(clazz)}');

                    var weakRefs = destroyedWeakRefs.get(clazz);
                    if (weakRefs != null) {
                        var hasRefs = false;
                        var pathStats = new Map<String,Int>();
                        var newRefs = [];
                        var allPaths:Array<String> = [];
                        for (weakRef in weakRefs) {
                            var entity:Entity = weakRef.get();
                            if (entity != null) {
                                if (Std.isOfType(entity, tracker.Autorun)) {
                                    var autor:tracker.Autorun = cast entity;
                                    if (@:privateAccess autor.onRun != null) {
                                        throw "Autorun onRun is not null!";
                                    }
                                }
                                newRefs.push(weakRef);
                                var posInfos = entity.posInfos;
                                if (posInfos != null) {
                                    var path = posInfos.fileName + ':' + posInfos.lineNumber;
                                    if (pathStats.exists(path)) {
                                        pathStats.set(path, pathStats.get(path) + 1);
                                    }
                                    else {
                                        pathStats.set(path, 1);
                                        allPaths.push(path);
                                    }
                                }
                            }
                            else {
                                numEntityDestroyedButInMemoryByClass.set(clazz, numEntityDestroyedButInMemoryByClass.get(clazz) - 1);
                            }
                        }
                        weakRefs.splice(0, weakRefs.length);
                        for (weakRef in newRefs) {
                            weakRefs.push(weakRef);
                        }
                        allPaths.sort(function(a, b) {
                            return pathStats.get(a) - pathStats.get(b);
                        });
                        if (allPaths.length > 0) {
                            var limit = 8;
                            var i = allPaths.length - 1;
                            var numLogged = 0;
                            while (limit > 0 && i >= 0) {
                                var path = allPaths[i];
                                var num = pathStats.get(path);
                                numLogged += num;
                                tracker.Shortcuts.log('        leak ${num} x $path');
                                i--;
                                limit--;
                            }
                            if (i > 0) {
                                var total = 0;
                                for (path in allPaths) {
                                    total += pathStats.get(path);
                                }
                                tracker.Shortcuts.log('        leak ${total - numLogged} x ...');
                            }
                        }
                    }
                }
            });
        }

        var clazz = '' + Type.getClass(this);

        #if cpp
        if (numEntityAliveInMemoryByClass.exists(clazz)) {
            numEntityAliveInMemoryByClass.set(clazz, numEntityAliveInMemoryByClass.get(clazz) + 1);
        }
        else {
            numEntityAliveInMemoryByClass.set(clazz, 1);
        }

        //cpp.vm.Gc.setFinalizer(this, cpp.Function.fromStaticFunction(__finalizeEntity));
        #end

        #end

    }

    #if (cpp && tracker_debug_entity_allocs)
    @:void public static function __finalizeEntity(o:Entity):Void {

        var clazz = '' + Type.getClass(o);
        if (o._lifecycleState == -3) {
            numEntityDestroyedButInMemoryByClass.set(clazz, numEntityDestroyedButInMemoryByClass.get(clazz) - 1);
        }
        else {
            numEntityAliveInMemoryByClass.set(clazz, numEntityAliveInMemoryByClass.get(clazz) - 1);
        }

    }
    #end

    /** Destroy this entity. This method is automatically protected from duplicate calls. That means
        calling multiple times an entity's `destroy()` method will run the destroy code only one time.
        As soon as `destroy()` is called, the entity is marked `destroyed=true`, even when calling `destroy()`
        method on a subclass (a macro is inserting a code to marke the object
        as destroyed at the beginning of every `destroy()` override function. */
    public function destroy():Void {

        if (_lifecycleState <= -2) return;
        _lifecycleState = -3; // `Entity.destroy() called` = true

        #if tracker_debug_entity_allocs
        var clazz = '' + Type.getClass(this);
        numEntityAliveInMemoryByClass.set(clazz, numEntityAliveInMemoryByClass.get(clazz) - 1);
        if (numEntityDestroyedButInMemoryByClass.exists(clazz)) {
            numEntityDestroyedButInMemoryByClass.set(clazz, numEntityDestroyedButInMemoryByClass.get(clazz) + 1);
        }
        else {
            numEntityDestroyedButInMemoryByClass.set(clazz, 1);
        }

        #if cpp
        var weakRef = new cpp.vm.WeakRef(this);
        if (destroyedWeakRefs.exists(clazz)) {
            destroyedWeakRefs.get(clazz).push(weakRef);
        }
        else {
            destroyedWeakRefs.set(clazz, [weakRef]);
        }
        #end
        #end

        if (autoruns != null) {
            for (i in 0...autoruns.length) {
                var _autorun = autoruns[i];
                if (_autorun != null) {
                    autoruns[i] = null;
                    _autorun.destroy();
                }
            }
        }

        emitDestroy(this);

        unbindEvents();

    }

    /** Remove all events handlers from this entity. */
    public function unbindEvents():Void {

        // Events macro will automatically fill this method
        // and create overrides in subclasses to unbind any event

    }

/// Autorun

    public var autoruns(default, null):Array<Autorun> = null;

    /** Creates a new `Autorun` instance with the given callback associated with the current entity.
        @param run The run callback
        @return The autorun instance */
    public function autorun(run:Void->Void, ?afterRun:Void->Void #if (tracker_debug_autorun || tracker_debug_entity_allocs) , ?pos:haxe.PosInfos #end):Autorun {

        if (destroyed) return null;

#if tracker_debug_autorun
        if (pos != null) {
            var _run = run;
            run = function() {
                haxe.Log.trace('autorun', pos);
                _run();
            };
        }
#end

        var _autorun = new Autorun(run, afterRun #if tracker_debug_entity_allocs , pos #end);
        run = null;

        if (autoruns == null) {
            autoruns = [_autorun];
        }
        else {
            var didAdd = false;
            for (i in 0...autoruns.length) {
                var existing = autoruns[i];
                if (existing == null) {
                    autoruns[i] = _autorun;
                    didAdd = true;
                    break;
                }
            }
            if (!didAdd) {
                autoruns.push(_autorun);
            }
        }
        _autorun.onDestroy(this, checkAutoruns);

        return _autorun;

    }

    function checkAutoruns(_):Void {

        for (i in 0...autoruns.length) {
            var _autorun = autoruns[i];
            if (_autorun != null && _autorun.destroyed) {
                autoruns[i] = null;
            }
        }

    }

/// Print

    public function className():String {

        var className = Type.getClassName(Type.getClass(this));
        var dotIndex = className.lastIndexOf('.');
        if (dotIndex != -1) className = className.substr(dotIndex + 1);
        return className;

    }

    function toString():String {

        var className = className();

        if (id != null) {
            return '$className($id)';
        } else {
            return '$className';
        }

    }

}

#end
