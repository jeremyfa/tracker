package tracker.macros;

import haxe.macro.Context;
import haxe.macro.Expr;

using StringTools;

class EventsMacro {

    @:allow(tracker.macros.ObservableMacro)
    @:allow(tracker.macros.SerializableMacro)
    static var _nextEventIndexes:Map<String,Int> = new Map();

    macro static public function build():Array<Field> {

        #if tracker_debug_macro
        trace(Context.getLocalClass() + ' -> BEGIN EventsMacro.build()');
        #end

        var fields = Context.getBuildFields();

        // Should we dispatch events dynamically?
        var localClass = Context.getLocalClass().get();

        // Get entity type
        #if tracker_ceramic
        var entityTypeStr = 'ceramic.Entity';
        #else
        var entityTypeStr = TrackerMacro.entityTypeStr;
        if (entityTypeStr == null)
            entityTypeStr = 'tracker.Entity';
        #end

        // Get next event index for this class path
        var classPath = localClass.pack != null && localClass.pack.length > 0 ? localClass.pack.join('.') + '.' + localClass.name : localClass.name;
        var nextEventIndex = _nextEventIndexes.exists(classPath) ? _nextEventIndexes.get(classPath) : 1;

        // Check if we inherit from Entity
        var inheritsFromEntity = (classPath == entityTypeStr);
        var parentHold = localClass.superClass;
        var parent = parentHold != null ? parentHold.t : null;
        while (parent != null) {

            if (!inheritsFromEntity && parentHold.t.toString() == entityTypeStr) {
                inheritsFromEntity = true;
                break;
            }

            parentHold = parent.get().superClass;
            parent = parentHold != null ? parentHold.t : null;
        }

        // Check if events should be dispatched dynamically by default on this class
        #if (!completion && !display)
        var dynamicDispatch = #if tracker_dynamic_dispatch true #else hasDynamicEventsMeta(localClass.meta.get()) #end;
        #else
        var dynamicDispatch = false;
        #end

        // Gather all emit{EventName}
        var allEmits:Map<String,Bool> = new Map();

        // Check class fields
        var fieldsByName = new Map<String,Bool>();
        for (field in fields) {
            fieldsByName.set(field.name, true);
        }

        var newFields = [];

        // Also check parent fields
        var parentHold = localClass.superClass;
        var parent = parentHold != null ? parentHold.t : null;
        var numParents = 0;
        while (parent != null) {

            for (field in parent.get().fields.get()) {
                fieldsByName.set(field.name, true);

                if (field.name.startsWith('emit')) {
                    allEmits.set(field.name.substring(4), true);
                }
                else if (field.meta.has('event')) {
                    allEmits.set(field.name.charAt(0).toUpperCase() + field.name.substring(1), true);
                }
            }

            parentHold = parent.get().superClass;
            parent = parentHold != null ? parentHold.t : null;
            numParents++;
        }

        // In case of dynamic dispatch, check if event dispatcher
        // field was added already on current class fields
        var dispatcherName:String = null;
        if (dynamicDispatch) {
            dispatcherName = '__events' + numParents;
            if (!fieldsByName.exists(dispatcherName)) {
                EventsMacro.createEventDispatcherField(Context.currentPos(), newFields, dispatcherName);
            }
        }

        for (field in fields) {
            if (hasEventMeta(field)) {
                nextEventIndex = createEventFields(
                    field, newFields, fields, fieldsByName, dynamicDispatch, nextEventIndex, dispatcherName, inheritsFromEntity,
                    #if (display || completion)
                    false
                    #else
                    hasSynchronizedMeta(field)
                    #end
                );
            }
            else {
                // Keep field
                newFields.push(field);
            }
        }

        for (field in newFields) {
            if (field.name.startsWith('emit')) {
                allEmits.set(field.name.substring(4), true);
            }
        }

        // Check that {will|did}Emit{EventName} and willListen{EventName} match an existing event
        for (field in newFields) {
            if (field.name.startsWith('willEmit')) {
                if (!allEmits.exists(field.name.substring(8))) {
                    throw new Error("No event with name `" + field.name.charAt(8).toLowerCase() + field.name.substring(9) + "` will ever be emitted by this class", field.pos);
                }
            }
            else if (field.name.startsWith('didEmit')) {
                if (!allEmits.exists(field.name.substring(7))) {
                    throw new Error("No event with name `" + field.name.charAt(7).toLowerCase() + field.name.substring(8) + "` will ever be emitted by this class", field.pos);
                }
            }
            else if (field.name.startsWith('willListen')) {
                if (!allEmits.exists(field.name.substring(10))) {
                    throw new Error("No event with name `" + field.name.charAt(10).toLowerCase() + field.name.substring(11) + "` will ever be emitted by this class", field.pos);
                }
            }
        }

        // Store next event index for this class path
        _nextEventIndexes.set(classPath, nextEventIndex);

        #if tracker_debug_macro
        trace(Context.getLocalClass() + ' -> END EventsMacro.build()');
        #end

        return newFields;

    }

    @:allow(tracker.macros.ObservableMacro)
    @:allow(tracker.macros.SerializableMacro)
    static function createEventDispatcherField(currentPos:Position, fields:Array<Field>, dispatcherName:String):Void {

        fields.push({
            pos: currentPos,
            name: dispatcherName,
            kind: FProp(
                'get', 'null',
                macro :tracker.EventDispatcher,
                null
            ),
            access: [APrivate],
            doc: '',
            meta: [{
                name: ':noCompletion',
                params: [],
                pos: currentPos
            }]
        });

        fields.push({
            pos: currentPos,
            name: 'get_' + dispatcherName,
            kind: FFun({
                args: [],
                ret: macro :tracker.EventDispatcher,
                expr: macro {
                    if (this.$dispatcherName == null)
                        this.$dispatcherName = new tracker.EventDispatcher();
                    return this.$dispatcherName;
                }
            }),
            access: [APrivate],
            doc: '',
            meta: [{
                name: ':noCompletion',
                params: [],
                pos: currentPos
            }]
        });

    }

    @:allow(tracker.macros.ObservableMacro)
    @:allow(tracker.macros.SerializableMacro)
    static function createEventFields(field:Field, newFields:Array<Field>, existingFields:Array<Field>, fieldsByName:Map<String,Bool>, dynamicDispatch:Bool, eventIndex:Int, dispatcherName:String, inheritsFromEntity:Bool, threadSafe:Bool):Int {

        // Still allow a field to be generated with static dispatch, even
        // if default is to generate dynamic dispatch
        if (dynamicDispatch && hasStaticEventMeta(field)) {
            dynamicDispatch = false;
        }

        #if tracker_ceramic
        var entityType = macro :ceramic.Entity;
        #else
        var entityType = TrackerMacro.entityType;
        if (entityType == null)
            entityType = macro :tracker.Entity;
        #end

        #if (!tracker_synchronized || completion || display)
        threadSafe = false;
        #end

        switch (field.kind) {

            case FieldType.FFun(fn):

                if (field.access.indexOf(AStatic) != -1) {
                    throw new Error("Event cannot be static", field.pos);
                }

                var hasPrivateModifier = false;
                if (field.access.indexOf(APrivate) != -1) {
                    hasPrivateModifier = true;
                }

                var hasPublicModifier = false;
                if (field.access.indexOf(APublic) != -1) {
                    hasPublicModifier = true;
                }

                var handlerName = 'handle' + [for (arg in fn.args) arg.name.substr(0,1).toUpperCase() + arg.name.substr(1)].join('');
                var handlerType = TFunction([for (arg in fn.args) TNamed(arg.name, arg.type)], macro :Void);
                var handlerTypeBoxed = TFunction([for (i in 0...fn.args.length+1) macro :Dynamic], macro :Void);
                var handlerNumArgs = fn.args.length;
                var handlerCallArgs = [for (arg in fn.args) macro $i{arg.name}];
                var handlerCallArgsBoxed = [macro $i{'callbacks'}, macro $i{'len'}].concat([for (arg in fn.args) macro $i{arg.name}]);
                var sanitizedName = field.name;
                while (sanitizedName.startsWith('_')) sanitizedName = sanitizedName.substr(1);
                while (sanitizedName.endsWith('_')) sanitizedName = sanitizedName.substr(0, sanitizedName.length - 1);
                var capitalName = sanitizedName.substr(0,1).toUpperCase() + sanitizedName.substr(1);
                var onName = 'on' + capitalName;
                var onceName = 'once' + capitalName;
                var offName = 'off' + capitalName;
                var emitName = 'emit' + capitalName;
                var listensName = 'listens' + capitalName;
                var mutexName = 'mutex' + capitalName;
                var doc = field.doc;
                var origDoc = field.doc;
                if (doc == null || doc == '') {
                    doc = sanitizedName + ' event';
                }

                // Explicit boxing at emit call is required on c++ target to prevent
                // implicit boxing for each callback bound to event
                var needsBoxing = false;
                if (Context.defined('cpp')) {
                    if (fn.args.length > 0) {
                        needsBoxing = true;
                    }
                }

                var lock = macro null;
                var unlock = macro null;
                var lockable = macro false;

#if (!display && !completion)

                var cbOnArray = '__cbOn' + capitalName;
                var cbOnceArray = '__cbOnce' + capitalName;
                var cbOnOwnerUnbindArray = '__cbOnOwnerUnbind' + capitalName;
                var cbOnceOwnerUnbindArray = '__cbOnceOwnerUnbind' + capitalName;
                var onOwnerArray = '__onOwner' + capitalName;
                var onceOwnerArray = '__onceOwner' + capitalName;
                var emitNameBoxed = emitName + 'Boxed';

                #if tracker_debug_events
                var cbOnPosArray = '__cbOnPos' + capitalName;
                var cbOncePosArray = '__cbOncePos' + capitalName;
                #end

                if (threadSafe) {
                    lock = macro this.$mutexName.acquire();
                    unlock = macro this.$mutexName.release();
                    lockable = macro true;
                }

                if (!dynamicDispatch) {

                    // Create __cbOn{Name}
                    var cbOnField = {
                        pos: field.pos,
                        name: cbOnArray,
                        kind: FVar(TPath({
                            name: 'Null',
                            pack: [],
                            params: [
                                TPType(
                                    TPath({
                                        name: 'Array',
                                        pack: [],
                                        params: [
                                            TPType(
                                                handlerType
                                            )
                                        ]
                                    })
                                )
                            ]
                        })),
                        access: [APrivate],
                        doc: doc,
                        meta: [{
                            name: ':noCompletion',
                            params: [],
                            pos: field.pos
                        }]
                    };
                    newFields.push(cbOnField);

                    // Create __cbOnce{Name}
                    var cbOnceField = {
                        pos: field.pos,
                        name: cbOnceArray,
                        kind: FVar(TPath({
                            name: 'Null',
                            pack: [],
                            params: [
                                TPType(
                                    TPath({
                                        name: 'Array',
                                        pack: [],
                                        params: [
                                            TPType(
                                                handlerType
                                            )
                                        ]
                                    })
                                )
                            ]
                        })),
                        access: [APrivate],
                        doc: doc,
                        meta: [{
                            name: ':noCompletion',
                            params: [],
                            pos: field.pos
                        }]
                    };
                    newFields.push(cbOnceField);

                    #if tracker_debug_events

                    // Create __cbOnPos{Name}
                    var cbOnPosField = {
                        pos: field.pos,
                        name: cbOnPosArray,
                        kind: FVar(TPath({
                            name: 'Null',
                            pack: [],
                            params: [
                                TPType(
                                    TPath({
                                        name: 'Array',
                                        pack: [],
                                        params: [
                                            TPType(
                                                macro :haxe.PosInfos
                                            )
                                        ]
                                    })
                                )
                            ]
                        })),
                        access: [APrivate],
                        doc: doc,
                        meta: [{
                            name: ':noCompletion',
                            params: [],
                            pos: field.pos
                        }]
                    };
                    newFields.push(cbOnPosField);

                    // Create __cbOncePos{Name}
                    var cbOncePosField = {
                        pos: field.pos,
                        name: cbOncePosArray,
                        kind: FVar(TPath({
                            name: 'Null',
                            pack: [],
                            params: [
                                TPType(
                                    TPath({
                                        name: 'Array',
                                        pack: [],
                                        params: [
                                            TPType(
                                                macro :haxe.PosInfos
                                            )
                                        ]
                                    })
                                )
                            ]
                        })),
                        access: [APrivate],
                        doc: doc,
                        meta: [{
                            name: ':noCompletion',
                            params: [],
                            pos: field.pos
                        }]
                    };
                    newFields.push(cbOncePosField);
                    #end

                    // Create __cbOnOwnerUnbind{Name}
                    var cbOnOwnerUnbindField = {
                        pos: field.pos,
                        name: cbOnOwnerUnbindArray,
                        kind: FVar(TPath({
                            name: 'Null',
                            pack: [],
                            params: [
                                TPType(
                                    TPath({
                                        name: 'Array',
                                        pack: [],
                                        params: [
                                            TPType(
                                                macro :Void->Void
                                            )
                                        ]
                                    })
                                )
                            ]
                        })),
                        access: [APrivate],
                        doc: doc,
                        meta: [{
                            name: ':noCompletion',
                            params: [],
                            pos: field.pos
                        }]
                    };
                    newFields.push(cbOnOwnerUnbindField);

                    // Create __cbOnceOwnerUnbind{Name}
                    var cbOnceOwnerUnbindField = {
                        pos: field.pos,
                        name: cbOnceOwnerUnbindArray,
                        kind: FVar(TPath({
                            name: 'Null',
                            pack: [],
                            params: [
                                TPType(
                                    TPath({
                                        name: 'Array',
                                        pack: [],
                                        params: [
                                            TPType(
                                                macro :Void->Void
                                            )
                                        ]
                                    })
                                )
                            ]
                        })),
                        access: [APrivate],
                        doc: doc,
                        meta: [{
                            name: ':noCompletion',
                            params: [],
                            pos: field.pos
                        }]
                    };
                    newFields.push(cbOnceOwnerUnbindField);

                }

                // Bind hooks
                //

                var fnWillEmit = 'willEmit' + capitalName;
                var fnDidEmit = 'didEmit' + capitalName;
                var fnWillListen = 'willListen' + capitalName;

                var willEmit = macro null;
                if (fieldsByName.exists(fnWillEmit)) {
                    if (dynamicDispatch) {
                        willEmit = macro this.$dispatcherName.setWillEmit($v{eventIndex}, this.$fnWillEmit);
                    }
                    else {
                        willEmit = macro this.$fnWillEmit($a{handlerCallArgs});
                    }
                }

                var didEmit = macro null;
                if (fieldsByName.exists(fnDidEmit)) {
                    if (dynamicDispatch) {
                        didEmit = macro this.$dispatcherName.setDidEmit($v{eventIndex}, this.$fnDidEmit);
                    }
                    else {
                        didEmit = macro this.$fnDidEmit($a{handlerCallArgs});
                    }
                }

                var willListen = macro null;
                if (fieldsByName.exists(fnWillListen)) {
                    if (dynamicDispatch) {
                        willListen = macro this.$dispatcherName.setWillListen($v{eventIndex}, this.$fnWillListen);
                    }
                    else {
                        willListen = macro {
                            if (this.$cbOnArray == null && this.$cbOnceArray == null) {
                                this.$fnWillListen();
                            }
                        };
                    }
                }

                if (threadSafe) {
                    var mutexField = {
                        pos: field.pos,
                        name: mutexName,
                        kind: FVar(TPath({
                                pack: ['tracker'],
                                name: 'RecursiveMutex'
                            }),
                            macro new tracker.RecursiveMutex()
                        ),
                        access: [APrivate],
                        doc: doc,
                        meta: [{
                            name: ':noCompletion',
                            params: [],
                            pos: field.pos
                        }]
                    };
                    newFields.push(mutexField);
                }

                var fnCanEmit = 'canEmit' + capitalName;

                var trackOnOwner = macro null;
                var trackOnceOwner = macro null;
                var untrackOnOwner = macro null;
                var untrackOnceOwner = macro null;
                var untrackAllOnAndOnceOwners = macro null;
                var onceOwnerCanEmitTest = macro true;
                var onOwnerCanEmitTest = macro true;
                var pushInOnceOwnerArray = macro null;
                var assignNewOnceOwnerArray = macro null;
                var canEmit = macro null;
                if (fieldsByName.exists(fnCanEmit)) {

                    var onOwnerArrayField = {
                        pos: field.pos,
                        name: onOwnerArray,
                        kind: FVar(TPath({
                            name: 'Null',
                            pack: [],
                            params: [
                                TPType(
                                    TPath({
                                        name: 'Array',
                                        pack: [],
                                        params: [
                                            TPType(
                                                #if tracker_ceramic
                                                macro :ceramic.Entity
                                                #else
                                                macro :tracker.Entity
                                                #end
                                            )
                                        ]
                                    })
                                )
                            ]
                        })),
                        access: [APrivate],
                        doc: doc,
                        meta: [{
                            name: ':noCompletion',
                            params: [],
                            pos: field.pos
                        }]
                    };
                    newFields.push(onOwnerArrayField);

                    var onceOwnerArrayField = {
                        pos: field.pos,
                        name: onceOwnerArray,
                        kind: FVar(TPath({
                            name: 'Null',
                            pack: [],
                            params: [
                                TPType(
                                    TPath({
                                        name: 'Array',
                                        pack: [],
                                        params: [
                                            TPType(
                                                #if tracker_ceramic
                                                macro :ceramic.Entity
                                                #else
                                                macro :tracker.Entity
                                                #end
                                            )
                                        ]
                                    })
                                )
                            ]
                        })),
                        access: [APrivate],
                        doc: doc,
                        meta: [{
                            name: ':noCompletion',
                            params: [],
                            pos: field.pos
                        }]
                    };
                    newFields.push(onceOwnerArrayField);

                    if (dynamicDispatch) {
                        // TODO
                        throw '$fnCanEmit is not supported when using dynamic dispatch';
                    }
                    else {
                        trackOnOwner = macro {
                            if (this.$onOwnerArray == null) {
                                this.$onOwnerArray = [];
                            }
                            this.$onOwnerArray.push(owner);
                        };
                        trackOnceOwner = macro {
                            if (this.$onceOwnerArray == null) {
                                this.$onceOwnerArray = [];
                            }
                            this.$onceOwnerArray.push(owner);
                        };
                        untrackOnOwner = macro {
                            this.$onOwnerArray.splice(index, 1);
                        };
                        untrackOnceOwner = macro {
                            this.$onceOwnerArray.splice(index, 1);
                        };
                        untrackAllOnAndOnceOwners = macro {
                            this.$onOwnerArray = null;
                            this.$onceOwnerArray = null;
                        };
                        onOwnerCanEmitTest = macro this.$fnCanEmit(this.$onOwnerArray[ii]);
                        onceOwnerCanEmitTest = macro this.$fnCanEmit(this.$onceOwnerArray[ii]);
                        pushInOnceOwnerArray = macro {
                            newOnceOwnerArray.push(this.$onceOwnerArray[ii]);
                        };
                        assignNewOnceOwnerArray = macro {
                            this.$onceOwnerArray = newOnceOwnerArray;
                        };
                    }
                }
#end


#if (documentation && dox_events)
                var doxEventField = {
                    pos: field.pos,
                    name: '_dox_event_' + field.name,
                    kind: FFun({
                        args: fn.args,
                        ret: macro :Void,
                        expr: macro {}
                    }),
                    access: [APublic],
                    doc: field.doc,
                    meta: [{
                        name: ':dox',
                        params: [macro show],
                        pos: Context.currentPos()
                    }]
                };
                newFields.push(doxEventField);
#end

                if (dynamicDispatch) {

                    // Create emit{Name}()
                    //
                    var emitField = {
                        pos: field.pos,
                        name: emitName,
                        kind: FProp('get', 'never', handlerType),
                        access: [hasPublicModifier ? APublic : APrivate],
                        doc: doc,
                        meta: hasPrivateModifier ? [{
                            name: ':noCompletion',
                            params: [],
                            pos: field.pos
                        }] : []
                    };
                    newFields.push(emitField);
                    var get_emitField = {
                        pos: field.pos,
                        name: 'get_' + emitName,
                        kind: FFun({
                            args: [],
                            ret: handlerType,
                            expr: macro {
#if (!display && !completion)
                                $lock;
                                $willEmit;
                                $didEmit;
                                final res = this.$dispatcherName.wrapEmit($v{eventIndex}, $v{handlerNumArgs});
                                $unlock;
                                return res;
#else
                                return null;
#end
                            }
                        }),
#if (haxe_server || telemetry)
                        access: [APrivate],
#else
                        access: [AInline, APrivate],
#end
                        doc: doc,
                        meta: [{
                            name: ':dce',
                            params: [],
                            pos: field.pos
                        }]
                    };
                    newFields.push(get_emitField);

                    var onField = {
                        pos: field.pos,
                        name: onName,
                        kind: FProp('get', 'never', TFunction([
                            TOptional(entityType),
                            handlerType
                        ], macro :Void)),
                        access: [hasPrivateModifier ? APrivate : APublic],
                        doc: doc,
                        meta: hasPrivateModifier ? [{
                            name: ':noCompletion',
                            params: [],
                            pos: field.pos
                        }] : []
                    };
                    newFields.push(onField);
                    var get_onField = {
                        pos: field.pos,
                        name: 'get_' + onName,
                        kind: FFun({
                            args: [],
                            ret: TFunction([
                                TOptional(entityType),
                                handlerType
                            ], macro :Void),
                            expr: macro {
#if (!display && !completion)
                                $lock;
                                $willListen;
                                final res = this.$dispatcherName.wrapOn($v{eventIndex});
                                $unlock;
                                return res;
#else
                                return null;
#end
                            }
                        }),
#if (haxe_server || telemetry)
                        access: [APrivate],
#else
                        access: [AInline, APrivate],
#end
                        doc: doc,
                        meta: [{
                            name: ':dce',
                            params: [],
                            pos: field.pos
                        }]
                    };
                    newFields.push(get_onField);

                    var onceField = {
                        pos: field.pos,
                        name: onceName,
                        kind: FProp('get', 'never', TFunction([
                            TOptional(entityType),
                            handlerType
                        ], macro :Void)),
                        access: [hasPrivateModifier ? APrivate : APublic],
                        doc: doc,
                        meta: hasPrivateModifier ? [{
                            name: ':noCompletion',
                            params: [],
                            pos: field.pos
                        }] : []
                    };
                    newFields.push(onceField);
                    var get_onceField = {
                        pos: field.pos,
                        name: 'get_' + onceName,
                        kind: FFun({
                            args: [],
                            ret: TFunction([
                                TOptional(entityType),
                                handlerType
                            ], macro :Void),
                            expr: macro {
#if (!display && !completion)
                                $lock;
                                $willListen;
                                final res = this.$dispatcherName.wrapOnce($v{eventIndex});
                                $unlock;
                                return res;
#else
                                return null;
#end
                            }
                        }),
#if (haxe_server || telemetry)
                        access: [APrivate],
#else
                        access: [AInline, APrivate],
#end
                        doc: doc,
                        meta: [{
                            name: ':dce',
                            params: [],
                            pos: field.pos
                        }]
                    };
                    newFields.push(get_onceField);

                    var offField = {
                        pos: field.pos,
                        name: offName,
                        kind: FProp('get', 'never', TFunction([
                            handlerType
                        ], macro :Void)),
                        access: [hasPrivateModifier ? APrivate : APublic],
                        doc: doc,
                        meta: hasPrivateModifier ? [{
                            name: ':noCompletion',
                            params: [],
                            pos: field.pos
                        }] : []
                    };
                    newFields.push(offField);
                    var get_offField = {
                        pos: field.pos,
                        name: 'get_' + offName,
                        kind: FFun({
                            args: [],
                            ret: TFunction([
                                handlerType
                            ], macro :Void),
                            expr: macro {
                                $lock;
                                final res = this.$dispatcherName.wrapOff($v{eventIndex});
                                $unlock;
                                return res;
                            }
                        }),
#if (haxe_server || telemetry)
                        access: [APrivate],
#else
                        access: [AInline, APrivate],
#end
                        doc: doc,
                        meta: [{
                            name: ':dce',
                            params: [],
                            pos: field.pos
                        }]
                    };
                    newFields.push(get_offField);

                    var listensField = {
                        pos: field.pos,
                        name: listensName,
                        kind: FProp('get', 'never', macro :Void->Bool),
                        access: [hasPrivateModifier ? APrivate : APublic],
                        doc: doc,
                        meta: hasPrivateModifier ? [{
                            name: ':noCompletion',
                            params: [],
                            pos: field.pos
                        }] : []
                    };
                    newFields.push(listensField);
                    var get_listensField = {
                        pos: field.pos,
                        name: 'get_' + listensName,
                        kind: FFun({
                            args: [],
                            ret: macro :Void->Bool,
                            expr: macro {
                                $lock;
                                final res = this.$dispatcherName.wrapListens($v{eventIndex});
                                $unlock;
                                return res;
                            }
                        }),
#if (haxe_server || telemetry)
                        access: [APrivate],
#else
                        access: [AInline, APrivate],
#end
                        doc: doc,
                        meta: [{
                            name: ':dce',
                            params: [],
                            pos: field.pos
                        }]
                    };
                    newFields.push(get_listensField);

#if documentation
                    for (field in [onField, onceField, offField, listensField]) {
                        if (field.meta == null) {
                            field.meta = [];
                        }
                        field.meta.push({
                            name: ':dox',
                            params: [macro hide],
                            pos: field.pos
                        });
                    }
#end

                }
                else {

                    if (needsBoxing) {
                        var emitField = {
                            pos: field.pos,
                            name: emitName,
                            kind: FFun({
                                args: fn.args,
                                ret: macro :Void,
#if (!display && !completion)
                                expr: macro {
                                    $lock;
                                    $willEmit;
                                    var len = 0;
                                    if (this.$cbOnArray != null) len += this.$cbOnArray.length;
                                    if (this.$cbOnceArray != null) len += this.$cbOnceArray.length;
                                    if (len > 0) {
                                        #if tracker_ceramic
                                        var pool = $lockable ? new ceramic.ArrayPool(len) : ceramic.ArrayPool.pool(len);
                                        #else
                                        var pool = $lockable ? new tracker.ArrayPool(len) : tracker.ArrayPool.pool(len);
                                        #end
                                        var callbacks = pool.get();
                                        #if tracker_debug_events
                                        var callbacksPos = [];
                                        #end
                                        var i = 0;
                                        if (this.$cbOnArray != null) {
                                            for (ii in 0...this.$cbOnArray.length) {
                                                var canEmit = $onOwnerCanEmitTest;
                                                if (canEmit) {
                                                    #if tracker_debug_events
                                                    callbacksPos.push(this.$cbOnPosArray[ii]);
                                                    #end
                                                    callbacks.set(i, this.$cbOnArray[ii]);
                                                    i++;
                                                }
                                                else {
                                                    len--;
                                                }
                                            }
                                        }
                                        if (this.$cbOnceArray != null) {
                                            var newCbOnceOwnerUnbindArray = null;
                                            var newCbOnceArray = null;
                                            var newOnceOwnerArray = null;
                                            for (ii in 0...this.$cbOnceArray.length) {
                                                var canEmit = $onceOwnerCanEmitTest;
                                                if (canEmit) {
                                                    #if tracker_debug_events
                                                    callbacksPos.push(this.$cbOncePosArray[ii]);
                                                    #end
                                                    callbacks.set(i, this.$cbOnceArray[ii]);
                                                    this.$cbOnceArray[ii] = null;
                                                    var unbind = this.$cbOnceOwnerUnbindArray[ii];
                                                    this.$cbOnceOwnerUnbindArray[ii] = null;
                                                    if (unbind != null) unbind();
                                                    i++;
                                                }
                                                else {
                                                    len--;
                                                    if (newCbOnceOwnerUnbindArray == null) {
                                                        newCbOnceOwnerUnbindArray = [];
                                                        newCbOnceArray = [];
                                                        newOnceOwnerArray = [];
                                                    }
                                                    newCbOnceOwnerUnbindArray.push(this.$cbOnceOwnerUnbindArray[ii]);
                                                    newCbOnceArray.push(this.$cbOnceArray[ii]);
                                                    $pushInOnceOwnerArray;
                                                }
                                            }
                                            this.$cbOnceOwnerUnbindArray = newCbOnceOwnerUnbindArray;
                                            this.$cbOnceArray = newCbOnceArray;
                                            $assignNewOnceOwnerArray;
                                        }
                                        this.$emitNameBoxed($a{handlerCallArgsBoxed});
                                        pool.release(callbacks);
                                        callbacks = null;
                                    }
                                    $didEmit;
                                    $unlock;
                                }
#else
                                expr: macro {}
#end
                            }),
                            access: [hasPublicModifier ? APublic : APrivate],
                            doc: doc,
                            meta: hasPrivateModifier ? [{
                                name: ':noCompletion',
                                params: [],
                                pos: field.pos
                            }] : []
                        };
                        newFields.push(emitField);

#if (!display && !completion)
                        var emitFieldBoxed = {
                            pos: field.pos,
                            name: emitNameBoxed,
                            kind: FFun({
                                args: [{
                                    name: '_cbsArray',
                                    type: #if tracker_ceramic macro :ceramic.ReusableArray<Any> #else macro :tracker.ReusableArray<Any> #end
                                }, {
                                    name: '_cbsLen',
                                    type: macro :Int
                                }].concat([for (i in 0...fn.args.length) {
                                    name: fn.args[i].name,
                                    type: macro :Dynamic
                                }]),
                                ret: macro :Void,
                                expr: macro {
                                    $lock;
                                    for (i in 0..._cbsLen) {
                                        var cb:Dynamic = _cbsArray.get(i);
                                        _cbsArray.set(i, null);
                                        cb($a{handlerCallArgs});
                                        cb = null;
                                    }
                                    $unlock;
                                }
                            }),
                            access: [APrivate],
                            doc: '',
                            meta: []
                        };
                        newFields.push(emitFieldBoxed);
#end
                    }
                    else {
                        var emitField = {
                            pos: field.pos,
                            name: emitName,
                            kind: FFun({
                                args: fn.args,
                                ret: macro :Void,
#if (!display && !completion)
                                expr: macro {
                                    @:nullSafety(Off) {
                                        $lock;
                                        $willEmit;
                                        var len = 0;
                                        if (this.$cbOnArray != null) len += this.$cbOnArray.length;
                                        if (this.$cbOnceArray != null) len += this.$cbOnceArray.length;
                                        if (len > 0) {
                                            #if tracker_ceramic
                                            var pool = $lockable ? new ceramic.ArrayPool(len) : ceramic.ArrayPool.pool(len);
                                            #else
                                            var pool = $lockable ? new tracker.ArrayPool(len) : tracker.ArrayPool.pool(len);
                                            #end
                                            var callbacks = pool.get();
                                            #if tracker_debug_events
                                            var callbacksPos = [];
                                            #end
                                            var i = 0;
                                            if (this.$cbOnArray != null) {
                                                for (ii in 0...this.$cbOnArray.length) {
                                                    var canEmit = $onOwnerCanEmitTest;
                                                    if (canEmit) {
                                                        #if tracker_debug_events
                                                        callbacksPos.push(this.$cbOnPosArray[ii]);
                                                        #end
                                                        callbacks.set(i, this.$cbOnArray[ii]);
                                                        i++;
                                                    }
                                                    else {
                                                        len--;
                                                    }
                                                }
                                            }
                                            if (this.$cbOnceArray != null) {
                                                var newCbOnceOwnerUnbindArray = null;
                                                var newCbOnceArray = null;
                                                var newOnceOwnerArray = null;
                                                for (ii in 0...this.$cbOnceArray.length) {
                                                    var canEmit = $onceOwnerCanEmitTest;
                                                    if (canEmit) {
                                                        #if tracker_debug_events
                                                        callbacksPos.push(this.$cbOncePosArray[ii]);
                                                        #end
                                                        callbacks.set(i, this.$cbOnceArray[ii]);
                                                        this.$cbOnceArray[ii] = null;
                                                        var unbind = this.$cbOnceOwnerUnbindArray[ii];
                                                        this.$cbOnceOwnerUnbindArray[ii] = null;
                                                        if (unbind != null) unbind();
                                                        i++;
                                                    }
                                                    else {
                                                        len--;
                                                        if (newCbOnceOwnerUnbindArray == null) {
                                                            newCbOnceOwnerUnbindArray = [];
                                                            newCbOnceArray = [];
                                                            newOnceOwnerArray = [];
                                                        }
                                                        newCbOnceOwnerUnbindArray.push(this.$cbOnceOwnerUnbindArray[ii]);
                                                        newCbOnceArray.push(this.$cbOnceArray[ii]);
                                                        $pushInOnceOwnerArray;
                                                    }
                                                }
                                                this.$cbOnceOwnerUnbindArray = newCbOnceOwnerUnbindArray;
                                                this.$cbOnceArray = newCbOnceArray;
                                                $assignNewOnceOwnerArray;
                                            }
                                            for (i in 0...len) {
                                                var cb:Dynamic = callbacks.get(i);
                                                cb($a{handlerCallArgs});
                                            }
                                            pool.release(callbacks);
                                            callbacks = null;
                                        }
                                        $didEmit;
                                        $unlock;
                                    }
                                }
#else
                                expr: macro {}
#end
                            }),
                            access: [hasPublicModifier ? APublic : APrivate],
                            doc: doc,
                            meta: hasPrivateModifier ? [{
                                name: ':noCompletion',
                                params: [],
                                pos: field.pos
                            }] : []
                        };
                        newFields.push(emitField);
                    }

                    // Create on{Name}()
                    var onField = {
                        pos: field.pos,
                        name: onName,
                        kind: FFun({
                            args: [
                                {
                                    name: 'owner',
                                    type: TPath({
                                        name: 'Null',
                                        pack: [],
                                        params: [
                                            TPType(entityType)
                                        ]
                                    }),
                                    opt: #if tracker_optional_owner true #else false #end
                                },
                                {
                                    name: handlerName,
                                    type: handlerType
                                }
                                #if tracker_debug_events
                                ,{
                                    name: 'pos',
                                    type: macro :haxe.PosInfos,
                                    opt: true
                                }
                                #end
                            ],
                            ret: macro :Void,
#if (!display && !completion)
                            expr: macro {
                                @:nullSafety(Off) {
                                    $lock;
                                    $willListen;
                                    // Map owner to handler
                                    if (owner != null) {
                                        if (owner.destroyed) {
                                            $unlock;
                                            throw 'Failed to bind event ' + $v{sanitizedName} + ' because owner is destroyed!';
                                        }
                                        var destroyCb;//:tracker.Entity->Void;
                                        destroyCb = function(_) {
                                            if ($i{handlerName} != null) {
                                                this.$offName($i{handlerName});
                                                $i{handlerName} = null;
                                            }
                                            owner = null;
                                            destroyCb = null;
                                        };
                                        owner.onceDestroy(null, destroyCb);
                                        if (this.$cbOnOwnerUnbindArray == null) {
                                            this.$cbOnOwnerUnbindArray = [];
                                        }
                                        this.$cbOnOwnerUnbindArray.push(function() {
                                            if (owner != null && destroyCb != null) {
                                                owner.offDestroy(destroyCb);
                                            }
                                            owner = null;
                                            destroyCb = null;
                                            $i{handlerName} = null;
                                        });
                                    } else {
                                        if (this.$cbOnOwnerUnbindArray == null) {
                                            this.$cbOnOwnerUnbindArray = [];
                                        }
                                        this.$cbOnOwnerUnbindArray.push(null);
                                    }

                                    // Check handler
                                    #if tracker_check_handlers
                                    if ($i{handlerName} == null || !Reflect.isFunction($i{handlerName})) {
                                        $unlock;
                                        throw $v{sanitizedName} + " is not a function!";
                                    }
                                    #end

                                    // Add handler
                                    #if tracker_debug_events
                                    if (this.$cbOnPosArray == null) {
                                        this.$cbOnPosArray = [];
                                    }
                                    this.$cbOnPosArray.push(pos);
                                    #end
                                    if (this.$cbOnArray == null) {
                                        this.$cbOnArray = [];
                                    }
                                    this.$cbOnArray.push($i{handlerName});

                                    $trackOnOwner;
                                    $unlock;
                                }
                            }
#else
                            expr: macro {}
#end
                        }),
                        access: [hasPrivateModifier ? APrivate : APublic],
                        doc: doc,
                        meta: []
                    };
                    newFields.push(onField);

                    // Create once{Name}()
                    var onceField = {
                        pos: field.pos,
                        name: onceName,
                        kind: FFun({
                            args: [
                                {
                                    name: 'owner',
                                    type: TPath({
                                        name: 'Null',
                                        pack: [],
                                        params: [
                                            TPType(entityType)
                                        ]
                                    }),
                                    opt: #if tracker_optional_owner true #else false #end
                                },
                                {
                                    name: handlerName,
                                    type: handlerType
                                }
                                #if tracker_debug_events
                                ,{
                                    name: 'pos',
                                    type: macro :haxe.PosInfos,
                                    opt: true
                                }
                                #end
                            ],
                            ret: macro :Void,
#if (!display && !completion)
                            expr: macro {
                                @:nullSafety(Off) {
                                    $lock;
                                    $willListen;
                                    // Map owner to handler
                                    if (owner != null) {
                                        if (owner.destroyed) {
                                            $unlock;
                                            throw 'Failed to bind event ' + $v{sanitizedName} + ' because owner is destroyed!';
                                        }
                                        var destroyCb;//:tracker.Entity->Void;
                                        destroyCb = function(_) {
                                            if ($i{handlerName} != null) {
                                                this.$offName($i{handlerName});
                                                $i{handlerName} = null;
                                            }
                                            owner = null;
                                            destroyCb = null;
                                        };
                                        owner.onceDestroy(null, destroyCb);
                                        if (this.$cbOnceOwnerUnbindArray == null) {
                                            this.$cbOnceOwnerUnbindArray = [];
                                        }
                                        this.$cbOnceOwnerUnbindArray.push(function() {
                                            if (owner != null && destroyCb != null) {
                                                owner.offDestroy(destroyCb);
                                            }
                                            owner = null;
                                            destroyCb = null;
                                            $i{handlerName} = null;
                                        });
                                    } else {
                                        if (this.$cbOnceOwnerUnbindArray == null) {
                                            this.$cbOnceOwnerUnbindArray = [];
                                        }
                                        this.$cbOnceOwnerUnbindArray.push(null);
                                    }

                                    // Check handler
                                    #if tracker_check_handlers
                                    if ($i{handlerName} == null || !Reflect.isFunction($i{handlerName})) {
                                        throw $v{sanitizedName} + " is not a function!";
                                    }
                                    #end

                                    // Add handler
                                    #if tracker_debug_events
                                    if (this.$cbOncePosArray == null) {
                                        this.$cbOncePosArray = [];
                                    }
                                    this.$cbOncePosArray.push(pos);
                                    #end
                                    if (this.$cbOnceArray == null) {
                                        this.$cbOnceArray = [];
                                    }
                                    this.$cbOnceArray.push($i{handlerName});

                                    $trackOnceOwner;
                                    $unlock;
                                }
                            }
#else
                            expr: macro {}
#end
                        }),
                        access: [hasPrivateModifier ? APrivate : APublic],
                        doc: doc,
                        meta: []
                    };
                    newFields.push(onceField);

                    // Create off{Name}()
                    var offField = {
                        pos: field.pos,
                        name: offName,
                        kind: FFun({
                            args: [
                                {
                                    name: handlerName,
                                    type: handlerType,
                                    opt: true
                                }
                            ],
                            ret: macro :Void,
#if (!display && !completion)
                            expr: macro {
                                @:nullSafety(Off) {
                                    $lock;
                                    if ($i{handlerName} != null) {
                                        var index:Int;
                                        var unbind:Void->Void;
                                        if (this.$cbOnArray != null) {
                                            index = this.$cbOnArray.indexOf($i{handlerName});
                                            if (index != -1) {
                                                this.$cbOnArray.splice(index, 1);
                                                unbind = this.$cbOnOwnerUnbindArray[index];
                                                if (unbind != null) unbind();
                                                this.$cbOnOwnerUnbindArray.splice(index, 1);
                                                $untrackOnOwner;
                                            }
                                        }
                                        if (this.$cbOnceArray != null) {
                                            index = this.$cbOnceArray.indexOf($i{handlerName});
                                            if (index != -1) {
                                                this.$cbOnceArray.splice(index, 1);
                                                unbind = this.$cbOnceOwnerUnbindArray[index];
                                                if (unbind != null) unbind();
                                                this.$cbOnceOwnerUnbindArray.splice(index, 1);
                                                $untrackOnceOwner;
                                            }
                                        }
                                    } else {
                                        if (this.$cbOnOwnerUnbindArray != null) {
                                            for (i in 0...this.$cbOnOwnerUnbindArray.length) {
                                                var unbind = this.$cbOnOwnerUnbindArray[i];
                                                if (unbind != null) unbind();
                                            }
                                            this.$cbOnOwnerUnbindArray = null;
                                        }
                                        if (this.$cbOnceOwnerUnbindArray != null) {
                                            for (i in 0...this.$cbOnceOwnerUnbindArray.length) {
                                                var unbind = this.$cbOnceOwnerUnbindArray[i];
                                                if (unbind != null) unbind();
                                            }
                                            this.$cbOnceOwnerUnbindArray = null;
                                        }
                                        this.$cbOnArray = null;
                                        this.$cbOnceArray = null;
                                        $untrackAllOnAndOnceOwners;
                                    }
                                    $unlock;
                                }
                            }
#else
                            expr: macro {}
#end
                        }),
                        access: [hasPrivateModifier ? APrivate : APublic],
                        doc: doc,
                        meta: []
                    };
                    newFields.push(offField);

                    // Create listens{Name}()
                    var listensField = {
                        pos: field.pos,
                        name: listensName,
                        kind: FFun({
                            args: [],
                            ret: macro :Bool,
#if (!display && !completion)
                            expr: macro {
                                $lock;
                                final res = @:nullSafety(Off) ((this.$cbOnArray != null && this.$cbOnArray.length > 0)
                                    || (this.$cbOnceArray != null && this.$cbOnceArray.length > 0));
                                $unlock;
                                return res;
                            }
#else
                            expr: macro {
                                return false;
                            }
#end
                        }),
#if (haxe_server || telemetry)
                        access: [hasPrivateModifier ? APrivate : APublic],
#else
                        access: [hasPrivateModifier ? APrivate : APublic, AInline],
#end
                        doc: origDoc != doc ? 'Does it listen to ' + doc : doc,
                        meta: []
                    };
                    newFields.push(listensField);

                    // Add or patch unbindEvents() method

                    var unbindEventsField:Field = null;
                    for (aField in existingFields) {
                        if (aField.name == 'unbindEvents') {
                            unbindEventsField = aField;
                            break;
                        }
                    }

                    if (unbindEventsField == null) {
                        // Create unbindEvents() method
                        var isOverriding = fieldsByName.exists('unbindEvents');
                        unbindEventsField = {
                            pos: field.pos,
                            name: 'unbindEvents',
                            kind: FFun({
                                args: [],
                                ret: macro :Void,
                                expr: isOverriding ? (macro {
                                    super.unbindEvents();
                                    $lock;
                                    this.$offName();
                                    $unlock;
                                }) : (macro {
                                    $lock;
                                    this.$offName();
                                    $unlock;
                                })
                            }),
                            access: isOverriding ? [APublic, AOverride] : [APublic],
                            doc: '',
                            meta: []
                        }
                        if (isOverriding) {
                            unbindEventsField.meta.push({
                                name: ':dox',
                                params: [macro hide],
                                pos: field.pos
                            });
                        }
                        existingFields.push(unbindEventsField);
                    }
                    else {
                        // Inject code in existing method
                        switch (unbindEventsField.kind) {
                            case FFun(fn):
                                // Ensure expr is surrounded with a block
                                switch (fn.expr.expr) {
                                    case EBlock(exprs):
                                    default:
                                        fn.expr.expr = EBlock([{
                                            pos: fn.expr.pos,
                                            expr: fn.expr.expr
                                        }]);
                                }

                                switch (fn.expr.expr) {
                                    case EBlock(exprs):

                                        exprs.push(macro {
                                            $lock;
                                            this.$offName();
                                            $unlock;
                                        });

                                    default:
                                        throw new Error("Invalid unbindEvents body", unbindEventsField.pos);
                                }
                            default:
                        }
                    }

#if documentation
                    for (field in [onField, onceField, offField, listensField]) {
                        if (field.meta == null) {
                            field.meta = [];
                        }
                        field.meta.push({
                            name: ':dox',
                            params: [macro hide],
                            pos: field.pos
                        });
                    }
#end
                }

            default:
                throw new Error("Invalid event syntax", field.pos);
        }

        return dynamicDispatch ? eventIndex + 1 : eventIndex;

    }

    static function hasEventMeta(field:Field):Bool {

        if (field.meta == null || field.meta.length == 0) return false;

        for (meta in field.meta) {
            if (meta.name == 'event') {
                return true;
            }
        }

        return false;

    }

    static function hasSynchronizedMeta(field:Field):Bool {

        if (field.meta == null || field.meta.length == 0) return false;

        for (meta in field.meta) {
            if (meta.name == 'synchronized') {
                return true;
            }
        }

        return false;

    }

    static function hasStaticEventMeta(field:Field):Bool {

        if (field.meta == null || field.meta.length == 0) return false;

        for (meta in field.meta) {
            if (meta.name == 'staticEvent') {
                return true;
            }
        }

        return false;
    }

    @:allow(tracker.macros.ObservableMacro)
    @:allow(tracker.macros.SerializableMacro)
    static function hasDynamicEventsMeta(metas:Null<Metadata>):Bool {

        if (metas == null || metas.length == 0) return false;

        for (meta in metas) {
            if (meta.name == 'dynamicEvents') {
                return true;
            }
        }

        return false;

    }

    static function isEmpty(expr:Expr) {

        if (expr == null) return true;

        return switch (expr.expr) {
            case ExprDef.EBlock(exprs): exprs.length == 0;
            default: false;
        }

    }

}
