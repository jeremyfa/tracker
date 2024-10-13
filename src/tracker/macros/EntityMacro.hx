package tracker.macros;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.TypeTools;

using StringTools;
using haxe.macro.ExprTools;

class EntityMacro {

    #if (haxe_ver < 4)
    static var onReused:Bool = false;
    #end

    static var processed:Map<String,Bool> = new Map();

    static var hasSuperDestroy:Bool = false;

    macro static public function build():Array<Field> {

        #if tracker_debug_macro
        trace(Context.getLocalClass() + ' -> BEGIN EntityMacro.build()');
        #end

        #if (haxe_ver < 4)
        if (!onReused) {
            onReused = true;
            Context.onMacroContextReused(function() {
                processed = new Map();
                return true;
            });
        }
        #end

        var localClass = Context.getLocalClass().get();
        var fields = Context.getBuildFields();
        var classPath = Context.getLocalClass().toString();
        var parentHold = localClass.superClass;
        var parent = parentHold != null ? parentHold.t : null;
        var parentConstructor = null;
        while (parent != null) {

            var clazz = parent.get();

            if (parentConstructor == null) {
                parentConstructor = clazz.constructor?.get();
            }

            parentHold = clazz.superClass;
            parent = parentHold != null ? parentHold.t : null;
        }

        var newFields:Array<Field> = [];

        var constructor = null;
        var autorunMarked = null;
        for (field in fields) {
            if (field.name == 'new') {
                constructor = field;
                #if (display || completion)
                break;
                #end
            }
            #if (!display && !completion)
            else if (field.name == '_autorunMarkedMethods') {
                autorunMarked = field;
            }
            #end
        }

        var componentFields = [];
        var ownFields:Array<Field> = null;

        #if (!display && !completion)
        var hasDestroyOverride = false;
        #end
        for (field in fields) {

            #if (!display && !completion)
            if (!hasDestroyOverride && field.name == 'destroy') {
                hasDestroyOverride = true;
            }
            #end

            var hasMeta = hasRelevantMeta(field);
            if (hasMeta.bool(0) || hasMeta.bool(1)) { // has owner or component meta
                if (ownFields == null) {
                    ownFields = [];
                }
                ownFields.push(field);
                newFields.push(field);
            }
            else {
                newFields.push(field);
            }

            if (hasMeta.bool(3)) { // has autorun meta

                switch(field.kind) {
                    case FieldType.FFun(f):
                        var fieldName = field.name;

                        constructor = createConstructorIfNeeded(constructor, parentConstructor, newFields, classPath);

                        if (autorunMarked == null) {
                            autorunMarked = {
                                name: '_autorunMarkedMethods',
                                doc: null,
                                meta: [{
                                    name: ':noCompletion',
                                    params: [],
                                    pos: Context.currentPos()
                                }],
                                access: [AOverride],
                                kind: FFun({
                                    params: [],
                                    args: [],
                                    ret: null,
                                    expr: macro {
                                        if (destroyed) return;
                                        super._autorunMarkedMethods();
                                    }
                                }),
                                pos: Context.currentPos()
                            };

                            newFields.push(autorunMarked);
                        }

                        // Add autorun calls in constructor tail
                        switch (constructor.kind) {
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

                                // Add our expression
                                switch (fn.expr.expr) {
                                    case EBlock(exprs):
                                        fn.expr.expr = EBlock(exprs.concat([
                                            macro this.autorun(this.$fieldName)
                                        ]));
                                    default:
                                }

                            default:
                                throw new Error("Invalid constructor", field.pos);
                        }

                        // Add autorun calls in _autorunMarkedMethods()
                        switch (autorunMarked.kind) {
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

                                // Add our expression
                                switch (fn.expr.expr) {
                                    case EBlock(exprs):
                                        fn.expr.expr = EBlock(exprs.concat([
                                            macro this.autorun(this.$fieldName)
                                        ]));
                                    default:
                                }

                            default:
                                throw new Error("Invalid constructor", field.pos);
                        }

                    default:
                        throw new Error("Invalid autorun meta usage", field.pos);
                }

            }
        }

        #if (!display && !completion)
        // In some cases, destroy override is a requirement, add it if not there already
        if (ownFields != null && !hasDestroyOverride) {
            newFields.push({
                pos: Context.currentPos(),
                name: 'destroy',
                kind: FFun({
                    args: [],
                    ret: macro :Void,
                    expr: macro {
                        super.destroy();
                    }
                }),
                access: [AOverride],
                meta: []
            });
        }
        #end

        var isProcessed = processed.exists(classPath);
        if (!isProcessed) {
            processed.set(classPath, true);

            for (field in newFields) {
                if (field.name == 'destroy') {

                    switch(field.kind) {
                        case FieldType.FFun(fn):

                            // Ensure expr is surrounded with a block and tranform super.destroy() calls.
                            // Check that super.destroy() call exists at the same time
                            hasSuperDestroy = false;

                            switch (fn.expr.expr) {
                                case EBlock(exprs):
                                    fn.expr = transformSuperDestroy(fn.expr);
                                default:
                                    fn.expr.expr = EBlock([{
                                        pos: fn.expr.pos,
                                        expr: transformSuperDestroy(fn.expr).expr
                                    }]);
                            }

                            if (!hasSuperDestroy) {
                                Context.error("Call to super.destroy() is required", field.pos);
                            }

                            switch (fn.expr.expr) {
                                case EBlock(exprs):

                                    // Check lifecycle state first and continue only
                                    // if the entity is not destroyed already
                                    // Mark destroyed, but still allow call to super.destroy()
                                    exprs.unshift(macro {
                                        if (_lifecycleState <= -2) return;
                                        _lifecycleState = -2;
                                    });

                                    // Destroy owned entities as well
                                    if (ownFields != null) {
                                        for (ownField in ownFields) {
                                            final name = ownField.name;
                                            var complexType = null;
                                            var resolvedType = null;
                                            switch ownField.kind {
                                                case FVar(t, e) | FProp(_, _, t, e):
                                                    complexType = t;
                                                    if (complexType == null && e != null) {
                                                        switch e.expr {
                                                            case ENew(t, params):
                                                                complexType = TPath(t);
                                                            case _:
                                                        }
                                                    }
                                                    try {
                                                        resolvedType = Context.resolveType(complexType, Context.currentPos());
                                                    }
                                                    catch (e:Dynamic) {}
                                                case _:
                                            }
                                            var isArray = false;
                                            var isMap = false;
                                            switch resolvedType {
                                                case TAbstract(t, params):
                                                    final tStr = t.toString();
                                                    if (params.length > 0) {
                                                        isArray = tStr.endsWith('Array');
                                                        isMap = tStr.endsWith('Map');
                                                    }
                                                case TInst(t, params):
                                                    final tStr = t.toString();
                                                    if (params.length > 0) {
                                                        isArray = tStr.endsWith('Array');
                                                        isMap = tStr.endsWith('Map');
                                                    }
                                                case _:
                                            }
                                            if (isArray) {
                                                exprs.unshift(macro {
                                                    var toDestroy = this.$name;
                                                    if (toDestroy != null) {
                                                        var i = toDestroy.length - 1;
                                                        while (i >= 0) {
                                                            final item = toDestroy[i];
                                                            if (item != null) {
                                                                item.destroy();
                                                            }
                                                            i--;
                                                        }
                                                        this.$name = null;
                                                    }
                                                });
                                            }
                                            else if (isMap) {
                                                exprs.unshift(macro {
                                                    var toDestroy = this.$name;
                                                    if (toDestroy != null) {
                                                        var itemsToDestroy = null;
                                                        for (key in toDestroy.keys()) {
                                                            final item = toDestroy.get(key);
                                                            if (item != null) {
                                                                if (itemsToDestroy == null) {
                                                                    itemsToDestroy = [];
                                                                }
                                                                itemsToDestroy.push(item);
                                                            }
                                                        }
                                                        if (itemsToDestroy != null) {
                                                            for (i in 0...itemsToDestroy.length) {
                                                                itemsToDestroy[i].destroy();
                                                            }
                                                        }
                                                        this.$name = null;
                                                    }
                                                });
                                            }
                                            else {
                                                exprs.unshift(macro {
                                                    var toDestroy = this.$name;
                                                    if (toDestroy != null) {
                                                        toDestroy.destroy();
                                                        this.$name = null;
                                                    }
                                                });
                                            }
                                        }
                                    }

                                default:
                            }

                        default:
                    }
                }
            }
        }

        #if tracker_debug_macro
        trace(Context.getLocalClass() + ' -> END EntityMacro.build()');
        #end

        return newFields;

    }

    static function createConstructorIfNeeded(constructor:Field, parentConstructor:haxe.macro.Type.ClassField, newFields:Array<Field>, classPath:String):Field {

        if (constructor == null) {

            // Implicit constructor override because it is needed to initialize components

            var constructorArgs = [];
            var constructorExpr = new StringBuf();
            constructorExpr.add('{ super(');

            if (parentConstructor != null) {

                var didResolveConstructorField = false;
                try {
                    switch TypeTools.follow(parentConstructor.type) {
                        case TFun(args, ret):
                            didResolveConstructorField = true;
                            if (args != null) {
                                for (a in 0...args.length) {
                                    var arg = args[a];
                                    constructorArgs.push({
                                        name: arg.name,
                                        opt: arg.opt,
                                        type: arg.t != null ? TypeTools.toComplexType(arg.t) : null
                                    });
                                    if (a > 0) {
                                        constructorExpr.add(', ');
                                    }
                                    constructorExpr.add(arg.name);
                                }
                            }
                        default:
                    }
                }
                catch (e:Dynamic) {
                    didResolveConstructorField = false;
                }

                if (!didResolveConstructorField) {
                    Context.warning('Failed to resolve parent constructor field for class ' + classPath, Context.currentPos());
                }
            }
            constructorExpr.add('); }');

            constructor = {
                name: 'new',
                doc: null,
                meta: [],
                access: [APublic],
                kind: FFun({
                    params: [],
                    args: constructorArgs,
                    ret: null,
                    expr: Context.parse(constructorExpr.toString(), Context.currentPos())
                }),
                pos: Context.currentPos()
            };

            newFields.push(constructor);
        }

        return constructor;

    }

    /** Replace `super.destroy();`
        with `{ _lifecycleState = -1; super.destroy(); }`
        */
    static function transformSuperDestroy(e:Expr):Expr {

        // This super.destroy() call patch ensures
        // the parent destroy() method will not ignore our call as it would normally do
        // when the object is marked destroyed.

        switch (e.expr) {
            case ECall({expr: EField({expr: EConst(CIdent('super')), pos: _}, 'destroy'), pos: _}, _):
                hasSuperDestroy = true;
                return macro { _lifecycleState = -1; ${e}; };
            default:
                return ExprTools.map(e, transformSuperDestroy);
        }

    }

    static function hasRelevantMeta(field:Field):Flags {

        if (field.meta == null || field.meta.length == 0) return 0;

        var flags:Flags = 0;

        for (meta in field.meta) {
            if (meta.name == 'component') {
                flags.setBool(0, true);
            }
            #if (!completion && !display)
            else if (meta.name == 'owner') {
                flags.setBool(1, true);
            }
            else if (meta.name == 'autorun') {
                flags.setBool(3, true);
            }
            #end
        }

        return flags;

    }

}