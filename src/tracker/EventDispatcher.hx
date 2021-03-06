package tracker;

#if tracker_ceramic
import ceramic.Entity;
#end

/** Event dispatcher used by DynamicEvents and Events macro as an alternative implementation
    that doesn't require to add a lot of methods on classes with events.
    This is basically the same code as what is statically generated by Events macro,
    but made dynamic and usable for any type.
    This is not really supposed to be used as is as it is pretty low-level. */
class EventDispatcher {

    var items:Array<EventDispatcherItem> = [];

    public function new() {}

/// Will/Did emit

    public function setWillEmit(index:Int, cb:Dynamic):Void {

        var item = items[index];
        if (item == null) {
            item = new EventDispatcherItem();
            items[index] = item;
        }

        item.willEmit = cb;

    }

    public function setDidEmit(index:Int, cb:Dynamic):Void {

        var item = items[index];
        if (item == null) {
            item = new EventDispatcherItem();
            items[index] = item;
        }

        item.didEmit = cb;

    }

    public function setWillListen(index:Int, cb:Dynamic):Void {

        var item = items[index];
        if (item == null) {
            item = new EventDispatcherItem();
            items[index] = item;
        }

        item.willListen = cb;

    }

/// Emit

    public function wrapEmit(index:Int, numArgs:Int):Dynamic {

        var item = items[index];
        if (item == null) {
            item = new EventDispatcherItem();
            items[index] = item;
        }

        var wrapped:Dynamic = item.wrappedEmit;
        if (wrapped == null || item.wrappedEmitNumArgs != numArgs) {
            if (numArgs == 0) {
                wrapped = function() {
                    emit(index, 0);
                };
            }
            else if (numArgs == 1) {
                wrapped = function(arg1:Dynamic) {
                    emit(index, 1, arg1);
                };
            }
            else if (numArgs == 2) {
                wrapped = function(arg1:Dynamic, arg2:Dynamic) {
                    emit(index, 2, arg1, arg2);
                };
            }
            else if (numArgs == 3) {
                wrapped = function(arg1:Dynamic, arg2:Dynamic, arg3:Dynamic) {
                    emit(index, 3, arg1, arg2, arg3);
                };
            }
            else {
                wrapped = Reflect.makeVarArgs(function(args:Array<Dynamic>) {
                    emit(index, -1, args);
                });
            }
            item.wrappedEmit = wrapped;
            item.wrappedEmitNumArgs = numArgs;
        }

        return wrapped;

    }

    public function emit(index:Int, numArgs:Int, ?arg1:Dynamic, ?arg2:Dynamic, ?arg3:Dynamic):Void {

        var item = items[index];
        if (item == null) {
            item = new EventDispatcherItem();
            items[index] = item;
        }
        
        if (item.willEmit != null) {
            if (numArgs == 0) {
                item.willEmit();
            }
            else if (numArgs == 1) {
                item.willEmit(arg1);
            }
            else if (numArgs == 2) {
                item.willEmit(arg1, arg2);
            }
            else if (numArgs == 3) {
                item.willEmit(arg1, arg2, arg3);
            }
            else {
                var args:Array<Dynamic> = arg1;
                Reflect.callMethod(null, item.willEmit, args);
            }
        }

        var len:Int = 0;
        if (item.cbOnArray != null) len += item.cbOnArray.length;
        if (item.cbOnceArray != null) len += item.cbOnceArray.length;

        if (len > 0) {
            #if tracker_ceramic
            var pool = ceramic.ArrayPool.pool(len);
            #else
            var pool = tracker.ArrayPool.pool(len);
            #end
            var callbacks = pool.get();
            var i = 0;
            if (item.cbOnArray != null) {
                for (ii in 0...item.cbOnArray.length) {
                    callbacks.set(i, item.cbOnArray[ii]);
                    i++;
                }
            }
            if (item.cbOnceArray != null) {
                for (ii in 0...item.cbOnceArray.length) {
                    callbacks.set(i, item.cbOnceArray[ii]);
                    i++;
                }
                item.cbOnceArray = null;
            }
            if (numArgs == 0) {
                for (i in 0...len) {
                    var cb:Void->Void = callbacks.get(i);
                    cb();
                }
            }
            else if (numArgs == 1) {
                for (i in 0...len) {
                    var cb:Dynamic->Void = callbacks.get(i);
                    cb(arg1);
                }
            }
            else if (numArgs == 2) {
                for (i in 0...len) {
                    var cb:Dynamic->Dynamic->Void = callbacks.get(i);
                    cb(arg1, arg2);
                }
            }
            else if (numArgs == 3) {
                for (i in 0...len) {
                    var cb:Dynamic->Dynamic->Dynamic->Void = callbacks.get(i);
                    cb(arg1, arg2, arg3);
                }
            }
            else {
                var args:Array<Dynamic> = arg1;
                for (i in 0...len) {
                    var cb:Dynamic = callbacks.get(i);
                    Reflect.callMethod(null, cb, args);
                }
            }
            pool.release(callbacks);
            callbacks = null;
        }
        
        if (item.didEmit != null) {
            if (numArgs == 0) {
                item.didEmit();
            }
            else if (numArgs == 1) {
                item.didEmit(arg1);
            }
            else if (numArgs == 2) {
                item.didEmit(arg1, arg2);
            }
            else if (numArgs == 3) {
                item.didEmit(arg1, arg2, arg3);
            }
            else {
                var args:Array<Dynamic> = arg1;
                Reflect.callMethod(null, item.didEmit, args);
            }
        }

    }

/// On

    public function wrapOn(index:Int):Dynamic {

        var item = items[index];
        if (item == null) {
            item = new EventDispatcherItem();
            items[index] = item;
        }

        var wrapped:Dynamic = item.wrappedOn;
        if (wrapped == null) {
            wrapped = function(#if tracker_optional_owner ?owner:Dynamic #else owner:Null<Dynamic> #end, ?cb:Dynamic) {
                // On some targets (lua), args could be offset
                // by one if owner was not provided
                if (cb != null) {
                    on(index, owner, cb);
                }
                else {
                    cb = owner;
                    on(index, null, cb);
                }
            };
            item.wrappedOn = wrapped;
        }

        return wrapped;

    }

    public function on(index:Int, #if tracker_optional_owner ?owner:Entity #else owner:Null<Entity> #end, cb:Dynamic):Void {

        var item = items[index];
        if (item == null) {
            item = new EventDispatcherItem();
            items[index] = item;
        }

        if (item.willListen != null) {
            if (item.cbOnOwnerUnbindArray == null && item.cbOnceOwnerUnbindArray == null) {
                item.willListen();
            }
        }

        // Map owner to handler
        if (owner != null) {
            if (owner.destroyed) {
                throw 'Failed to bind dynamic event because owner is destroyed!';
            }
            var destroyCb:Entity->Void;
            destroyCb = function(_) {
                if (cb != null) {
                    off(index, cb);
                }
                cb = null;
                owner = null;
                destroyCb = null;
            };
            owner.onceDestroy(null, destroyCb);
            if (item.cbOnOwnerUnbindArray == null) {
                item.cbOnOwnerUnbindArray = [];
            }
            item.cbOnOwnerUnbindArray.push(function() {
                if (owner != null && destroyCb != null) {
                    owner.offDestroy(destroyCb);
                }
                owner = null;
                destroyCb = null;
                cb = null;
            });
        } else {
            if (item.cbOnOwnerUnbindArray == null) {
                item.cbOnOwnerUnbindArray = [];
            }
            item.cbOnOwnerUnbindArray.push(null);
        }

        // Add handler
        if (item.cbOnArray == null) {
            item.cbOnArray = [];
        }
        item.cbOnArray.push(cb);

    }

/// Once

    public function wrapOnce(index:Int):Dynamic {

        var item = items[index];
        if (item == null) {
            item = new EventDispatcherItem();
            items[index] = item;
        }

        var wrapped:Dynamic = item.wrappedOnce;
        if (wrapped == null) {
            wrapped = function(#if tracker_optional_owner ?owner:Dynamic #else owner:Null<Dynamic> #end, ?cb:Dynamic) {
                // On some targets (lua), args could be offset
                // by one if owner was not provided
                if (cb != null) {
                    once(index, owner, cb);
                }
                else {
                    cb = owner;
                    once(index, null, cb);
                }
            };
            item.wrappedOnce = wrapped;
        }

        return wrapped;

    }

    public function once(index:Int, #if tracker_optional_owner ?owner:Entity #else owner:Null<Entity> #end, cb:Dynamic):Void {

        var item = items[index];
        if (item == null) {
            item = new EventDispatcherItem();
            items[index] = item;
        }

        if (item.willListen != null) {
            if (item.cbOnOwnerUnbindArray == null && item.cbOnceOwnerUnbindArray == null) {
                item.willListen();
            }
        }

        // Map owner to handler
        if (owner != null) {
            if (owner.destroyed) {
                throw 'Failed to bind dynamic event because owner is destroyed!';
            }
            var destroyCb:Entity->Void;
            destroyCb = function(_) {
                if (cb != null) {
                    off(index, cb);
                }
                cb = null;
                owner = null;
                destroyCb = null;
            };
            owner.onceDestroy(null, destroyCb);
            if (item.cbOnceOwnerUnbindArray == null) {
                item.cbOnceOwnerUnbindArray = [];
            }
            item.cbOnceOwnerUnbindArray.push(function() {
                if (owner != null && destroyCb != null) {
                    owner.offDestroy(destroyCb);
                }
                owner = null;
                destroyCb = null;
                cb = null;
            });
        } else {
            if (item.cbOnceOwnerUnbindArray == null) {
                item.cbOnceOwnerUnbindArray = [];
            }
            item.cbOnceOwnerUnbindArray.push(null);
        }

        // Add handler
        if (item.cbOnceArray == null) {
            item.cbOnceArray = [];
        }
        item.cbOnceArray.push(cb);

    }

/// Off

    public function wrapOff(index:Int):Dynamic {

        var item = items[index];
        if (item == null) {
            item = new EventDispatcherItem();
            items[index] = item;
        }

        var wrapped:Dynamic = item.wrappedOff;
        if (wrapped == null) {
            wrapped = function(?cb:Dynamic) {
                off(index, cb);
            };
            item.wrappedOff = wrapped;
        }

        return wrapped;

    }

    public function off(index:Int, cb:Dynamic):Void {

        var item = items[index];
        if (item == null) return;

        if (cb != null) {
            var index:Int;
            var unbind:Void->Void;
            if (item.cbOnArray != null) {
                index = item.cbOnArray.indexOf(cb);
                if (index != -1) {
                    item.cbOnArray.splice(index, 1);
                    unbind = item.cbOnOwnerUnbindArray[index];
                    if (unbind != null) unbind();
                    item.cbOnOwnerUnbindArray.splice(index, 1);
                }
            }
            if (item.cbOnceArray != null) {
                index = item.cbOnceArray.indexOf(cb);
                if (index != -1) {
                    item.cbOnceArray.splice(index, 1);
                    unbind = item.cbOnceOwnerUnbindArray[index];
                    if (unbind != null) unbind();
                    item.cbOnceOwnerUnbindArray.splice(index, 1);
                }
            }
        } else {
            if (item.cbOnOwnerUnbindArray != null) {
                for (i in 0...item.cbOnOwnerUnbindArray.length) {
                    var unbind = item.cbOnOwnerUnbindArray[i];
                    if (unbind != null) unbind();
                }
                item.cbOnOwnerUnbindArray = null;
            }
            if (item.cbOnceOwnerUnbindArray != null) {
                for (i in 0...item.cbOnceOwnerUnbindArray.length) {
                    var unbind = item.cbOnceOwnerUnbindArray[i];
                    if (unbind != null) unbind();
                }
                item.cbOnceOwnerUnbindArray = null;
            }
            item.cbOnArray = null;
            item.cbOnceArray = null;
        }

    }

/// Listens

    public function wrapListens(index:Int):Dynamic {

        var item = items[index];
        if (item == null) {
            item = new EventDispatcherItem();
            items[index] = item;
        }

        var wrapped:Dynamic = item.wrappedListens;
        if (wrapped == null) {
            wrapped = function() {
                return listens(index);
            };
            item.wrappedListens = wrapped;
        }

        return wrapped;

    }

    public function listens(index:Int):Bool {

        var item = items[index];
        if (item == null) return false;

        return (item.cbOnArray != null && item.cbOnArray.length > 0)
            || (item.cbOnceArray != null && item.cbOnceArray.length > 0);

    }

}

@:allow(tracker.EventDispatcher)
private class EventDispatcherItem {

    var willEmit:Dynamic = null;

    var didEmit:Dynamic = null;

    var willListen:Dynamic = null;

    var wrappedEmit:Dynamic = null;

    var wrappedEmitNumArgs:Int = -1;

    var wrappedOn:Dynamic = null;

    var wrappedOnce:Dynamic = null;

    var wrappedOff:Dynamic = null;

    var wrappedListens:Dynamic = null;

    var cbOnArray:Array<Dynamic> = [];

    var cbOnceArray:Array<Dynamic> = [];

    var cbOnOwnerUnbindArray:Array<Dynamic> = [];

    var cbOnceOwnerUnbindArray:Array<Dynamic> = [];

    public function new() {}

}
