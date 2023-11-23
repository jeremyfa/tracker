package tracker.macros;

import haxe.macro.Context;
import haxe.macro.Expr;

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

        var fields = Context.getBuildFields();
        var classPath = Context.getLocalClass().toString();

        var newFields:Array<Field> = [];

        var constructor = null;
        for (field in fields) {
            if (field.name == 'new') {
                constructor = field;
                break;
            }
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

            var hasMeta = hasOwnerOrComponentMeta(field);
            if (hasMeta == 1 || hasMeta == 2 || hasMeta == 3) { // has owner or component meta
                if (ownFields == null) {
                    ownFields = [];
                }
                ownFields.push(field);
                newFields.push(field);
            }
            else {
                newFields.push(field);
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

    static function hasOwnerOrComponentMeta(field:Field):Int {

        if (field.meta == null || field.meta.length == 0) return 0;

        var hasComponentMeta = false;
        var hasOwnerMeta = false;

        for (meta in field.meta) {
            if (meta.name == 'component') {
                hasComponentMeta = true;
            }
            else if (meta.name == 'owner') {
                hasOwnerMeta = true;
            }
        }

        if (hasComponentMeta && hasOwnerMeta) {
            return 3;
        }
        else if (hasComponentMeta) {
            return 2;
        }
        else if (hasOwnerMeta) {
            return 1;
        }
        else {
            return 0;
        }

    }

}